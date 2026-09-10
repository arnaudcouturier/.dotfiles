#!/usr/bin/env bash
# lib/arch-mega.sh — MEGA vendor repository for Arch (MEGAsync plus Thunar integration).
#
# The user explicitly asked for MEGA Sync with its Arch Extra file manager
# integration on the Thunar desktop, so trusting the vendor's pinned signing
# key and adding its pacman repository is authorized setup code below — it is
# generated here, never executed on this Fedora host. Arch gating, elevation,
# and the `pacman -Syu` install itself stay with the integrator (`dot`):
# this module only exposes the repository seam behind setup/verify functions.
#
# Source evidence (read-only vendor fetch, 2026-09-10):
#   landing page  https://mega.io/desktop  embeds
#     https://mega.nz/linux/repo/Arch_Extra/x86_64/megasync-x86_64.pkg.tar.zst
#     https://mega.nz/linux/repo/Arch_Extra/x86_64/thunar-megasync-x86_64.pkg.tar.zst
#   repo index    https://mega.nz/linux/repo/Arch_Extra/x86_64/  holds
#     megasync-6.5.1-1 plus thunar-megasync-6.2.0-1 (MEGA Desktop App plugin
#     for Thunar, DEPENDS thunar and megasync>=5.3.0) with per-package .sig
#     files and one signed pacman database. The database filename carries an
#     INFERRED vendor prefix — only DEB_Arch_Extra.db exists (no bare
#     Arch_Extra.db, 404-probed) — so the pacman section below must read
#     [DEB_Arch_Extra] for pacman to find its <section>.db. No
#     vendor-published pacman.conf snippet was found (mega.io/linux 404,
#     help pages 404, ArchWiki 0 hits); the mapping is behavior-inferred and
#     must be confirmed on Arch via `pacman -Si megasync thunar-megasync`.
#   signing key   https://mega.nz/linux/repo/Arch_Extra/x86_64/DEB_Arch_Extra.key
#     MegaLimited <support@mega.co.nz>, rsa4096 2022-01-12, expires 2032-01-10,
#     fingerprint B01C 8118 8048 0C85 4C73 EC7E 1A66 4B78 7094 A482.
#     Verified Good signature on the Thunar package in an isolated temp
#     GNUPGHOME; the package SHA256 matches the AUR megasync-bin PKGBUILD
#     through a second independent primary.
#
# Sourced library, not a script: definitions only at source time, so
# arch-check stays non-mutating. Requires dot's log_*/die/require_command
# helpers (source dot first, as the tests do). Callers run require_arch_system
# before any setup call; the functions below never gate the distro themselves
# so fixture-driven tests can exercise them on any host with stubs.

# shellcheck disable=SC2016 # $arch below is a pacman literal, never shell-expanded.
set -euo pipefail

# Idempotent source guard: re-sourcing after the readonly constants below
# would die under set -e, so return early on the second load.
[[ -n ${ARCH_MEGA_LOADED:-} ]] && return 0
ARCH_MEGA_LOADED=1

# Pinned vendor identity. Literals stay whole for grep: never interpolate
# the section name or fingerprint into a larger pattern.
readonly ARCH_MEGA_REPO_SECTION='DEB_Arch_Extra'
readonly ARCH_MEGA_REPO_SERVER='https://mega.nz/linux/repo/Arch_Extra/$arch'
# Contract name of the vendor sync database, for the integrator and tests.
# shellcheck disable=SC2034
readonly ARCH_MEGA_REPO_DB='DEB_Arch_Extra.db'
readonly ARCH_MEGA_KEY_FINGERPRINT='B01C811880480C854C73EC7E1A664B787094A482'
readonly ARCH_MEGA_KEY_URL='https://mega.nz/linux/repo/Arch_Extra/x86_64/DEB_Arch_Extra.key'
# Vendor packages this repository exists to provide, client before plugin
# (thunar-megasync DEPENDS megasync>=5.3.0).
readonly ARCH_MEGA_PACKAGES=(megasync thunar-megasync)
# The comment markers MEGA's own package writes around the section it adds to
# pacman.conf (observed verbatim on a provisioned machine, 2026-09-10). Its
# post_install removes any block wrapped in these markers and appends its own
# [DEB_Arch_Extra] with the weaker 'SigLevel = Required TrustedOnly', so it
# replaces our pinned block rather than stacking a second one; dot re-asserts
# the pinned section after the repo transaction for exactly that reason. We
# re-emit the markers around the pinned block to keep the vendor bookkeeping
# shape recognizable, and the writer below still collapses any state that
# does accumulate two copies; the markers are comments, so they change
# nothing for pacman.
readonly ARCH_MEGA_VENDOR_MARKER_BEGIN='###REPO for MEGA###'
readonly ARCH_MEGA_VENDOR_MARKER_END='###END REPO for MEGA###'

# Pacman keyring location. Production always uses the default; tests point it
# at a temp dir through this variable (same override precedent as
# WORKSTATION_GPU in lib/arch-gpu.sh). Never export it in production.
ARCH_MEGA_KEYRING_DIR="${ARCH_MEGA_KEYRING_DIR:-/etc/pacman.d/gnupg}"

# How many [DEB_Arch_Extra] sections a pacman.conf holds. Prints a number.
# Used to tell missing (0) from converged (1) from duplicated (>1) configs.
arch_mega_config_section_count() {
  local config=${1:-/etc/pacman.conf}
  grep -cE '^\[DEB_Arch_Extra\][[:space:]]*$' -- "${config}" 2>/dev/null || true
}

# Print the line numbers of every [DEB_Arch_Extra] header, space separated.
# Diagnostics only: a message that names the lines turns a hand edit into a
# one-liner instead of a hunt.
arch_mega_config_section_lines() {
  local config=${1:-/etc/pacman.conf}
  # No section is normal on first install: return success with empty output,
  # while still propagating read errors. grep's no-match status aborts init
  # under errexit before the missing section can be written.
  awk '/^\[DEB_Arch_Extra\][[:space:]]*$/ {
    printf "%s%d", separator, NR; separator = " "
  } END { if (separator != "") printf "\n" }' "${config}"
}

# Print the body lines of the [DEB_Arch_Extra] section (header and the next
# section header excluded). The optional 1-based index selects one
# occurrence, for inspecting a duplicated config copy by copy; the default
# (0) prints every occurrence, which is one section on a converged config.
# Empty when the section is absent.
arch_mega_config_section_body() {
  local config=${1:-/etc/pacman.conf} index=${2:-0}
  awk -v section='[DEB_Arch_Extra]' -v want="${index}" '
    /^\[/ {
      in_section = ($0 == section)
      if (in_section) seen++
      next
    }
    in_section && (want == 0 || want == seen) { print }
  ' "${config}" 2>/dev/null
}

# True when one section body carries EXACTLY the pinned directives: one
# pinned Server line and one SigLevel line requiring both package and
# database signatures — nothing else. Comments are stripped first (a comment
# containing 'Never' must not falsely reject a healthy config), then every
# remaining line must match: an Include smuggling another config file, a
# duplicate evil Server beside the good one, a duplicate SigLevel, or any
# unknown directive all fail.
arch_mega_section_is_pinned() {
  local body=$1 stripped server_count siglevel_count total
  stripped="$(sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<"${body}" | grep -v '^$' || true)"
  [[ -n ${stripped} ]] || return 1
  server_count="$(grep -cE '^Server[[:space:]]*=[[:space:]]*https://mega\.nz/linux/repo/Arch_Extra/\$arch$' <<<"${stripped}" || true)"
  siglevel_count="$(grep -cE '^SigLevel[[:space:]]*=[[:space:]]*Required[[:space:]]+DatabaseRequired$' <<<"${stripped}" || true)"
  total="$(grep -c . <<<"${stripped}" || true)"
  [[ ${server_count} == 1 && ${siglevel_count} == 1 && ${total} == 2 ]] || return 1
  return 0
}

# True when the MEGA vendor repository is configured exactly: one section,
# pinned. Duplicated sections are never "configured" — pacman refuses to
# register the same database twice — so this stays the strict end-state
# check that verify reports and setup converges on.
arch_mega_vendor_repo_configured() {
  local config=${1:-/etc/pacman.conf}
  [[ -r ${config} ]] || return 1
  [[ $(arch_mega_config_section_count "${config}") == 1 ]] || return 1
  arch_mega_section_is_pinned "$(arch_mega_config_section_body "${config}")"
}

# Print ${config} with every [DEB_Arch_Extra] section removed, header and
# body alike. Blank lines are held back and flushed by the next kept line, so
# a section that was appended with its own leading blank line takes that line
# with it; every other byte of the file survives verbatim.
arch_mega_config_without_vendor_sections() {
  local config=$1
  awk -v section='[DEB_Arch_Extra]' \
      -v begin_marker="${ARCH_MEGA_VENDOR_MARKER_BEGIN}" \
      -v end_marker="${ARCH_MEGA_VENDOR_MARKER_END}" '
    # The vendor markers go with the block: dropped wherever they sit, then
    # re-emitted around the pinned section, so neither can accumulate.
    $0 == begin_marker || $0 == end_marker { next }
    /^[[:space:]]*$/ { blanks = blanks $0 "\n"; next }
    /^\[/ { drop = ($0 == section) }
    { if (!drop) { printf "%s", blanks; print }; blanks = "" }
    END { printf "%s", blanks }
  ' "${config}"
}

# Classify one --with-colons key listing already scoped to the pinned
# fingerprint. Prints exactly one word: 'trusted' (exact primary
# fingerprint, single primary, full/ultimate validity), 'invalid' (second
# primary, revocation marker, fingerprint mismatch, or a revoked/expired/
# invalid/disabled validity), or 'untrusted' (present but not locally
# signed — e.g. fresh '-' validity). Pure parser: no sudo, no network, no
# keyring writes; unit-tested below against live-observed gpg 2.4 forms.
arch_mega_key_trust_status() {
  local out=$1 pub_count fpr pub validity
  pub_count="$(grep -c '^pub:' <<<"${out}")"
  [[ ${pub_count} == 1 ]] || { printf 'invalid\n'; return 0; }
  grep -q '^rev:' <<<"${out}" && { printf 'invalid\n'; return 0; }
  fpr="$(awk -F: '/^fpr:/ {print $10; exit}' <<<"${out}")"
  [[ ${fpr} == "${ARCH_MEGA_KEY_FINGERPRINT}" ]] || { printf 'invalid\n'; return 0; }
  pub="$(grep '^pub:' <<<"${out}" | head -n 1)"
  [[ -n ${pub} ]] || { printf 'invalid\n'; return 0; }
  validity="$(cut -d: -f2 <<<"${pub}")"
  case "${validity}" in
    f | u) printf 'trusted\n' ;;
    r | e | i | d) printf 'invalid\n' ;;
    *) printf 'untrusted\n' ;;
  esac
  return 0
}

# True when the pinned vendor key is present in the pacman keyring AND
# locally signed (full/ultimate validity). Presence alone is not trust: an
# added-but-unsigned key reports validities like '-' and returns 1 so setup
# repairs it with --lsign-key and a second invocation converges. The exact
# primary fingerprint plus the validity column decide, never a bare exit
# status: a scoped listing that answers for another key, or an unsigned one,
# fails here. Read-only: no import, no signing, no refresh, no network.
arch_mega_key_trusted() {
  local keyring="${ARCH_MEGA_KEYRING_DIR:-/etc/pacman.d/gnupg}" out
  # --no-auto-check-trustdb: listing-only, never refreshes or writes the
  # system trustdb (gpg would otherwise recompute it as a side effect).
  out="$(sudo gpg --homedir "${keyring}" --batch --no-auto-check-trustdb --with-colons --list-keys "${ARCH_MEGA_KEY_FINGERPRINT}" 2>/dev/null)" || return 1
  [[ $(arch_mega_key_trust_status "${out}") == trusted ]] || return 1
  return 0
}

# Abort a staged config write: restore the caller's CLEANUP_PATH, drop the
# staging file, and die. The live config is never touched on this path.
arch_mega_abort_staged() {
  local staged=$1 prev_cleanup=$2
  shift 2
  CLEANUP_PATH="${prev_cleanup}"
  rm -f -- "${staged}"
  die "$@"
}

# Validate a staged pacman.conf, then install it over ${config}: parse it
# with pacman-conf on the live config (the test seam revalidates the pinned
# section instead), keep one restorable backup of the first edit, and
# install 0644. The live config is only ever replaced by a file that already
# validated, so a rejected staging file leaves the machine untouched. Both
# writers below — the append and the duplicate collapse — go through here so
# neither can grow its own weaker path.
arch_mega_deploy_staged_config() {
  local config=$1 staged=$2 live=$3 prev_cleanup=$4 backup
  if [[ ${live} == true ]]; then
    sudo pacman-conf --config "${staged}" >/dev/null \
      || arch_mega_abort_staged "${staged}" "${prev_cleanup}" "arch-mega: the staged ${config} is not parseable; live config untouched."
    sudo pacman-conf --config "${staged}" --repo-list 2>/dev/null | grep -Fxq "${ARCH_MEGA_REPO_SECTION}" \
      || arch_mega_abort_staged "${staged}" "${prev_cleanup}" "arch-mega: the staged config does not expose [${ARCH_MEGA_REPO_SECTION}]; live config untouched."
  else
    arch_mega_vendor_repo_configured "${staged}" \
      || arch_mega_abort_staged "${staged}" "${prev_cleanup}" 'arch-mega: the staged config fails revalidation; original untouched.'
  fi
  backup="${config}.dotfiles-backup"
  if [[ ! -e ${backup} ]]; then
    sudo cp --archive -- "${config}" "${backup}" \
      || arch_mega_abort_staged "${staged}" "${prev_cleanup}" "arch-mega: cannot back up ${config}."
  fi
  sudo install --mode=0644 -- "${staged}" "${config}" \
    || arch_mega_abort_staged "${staged}" "${prev_cleanup}" "arch-mega: cannot deploy ${config}; restore ${backup}."
  rm -f -- "${staged}"
  CLEANUP_PATH="${prev_cleanup}"
}

# Bring ${config} to exactly one pinned [DEB_Arch_Extra] section: strip every
# copy that is there, then append the canonical block after the official
# repos (pacman resolves first-match-wins, so a vendor-last position keeps
# vendor names from ever shadowing official packages). This is the only
# writer of the section, so every starting state — missing, duplicated, or
# drifted — converges on the same end state instead of asking for a hand
# edit. Convergence cannot weaken anything: the block is generated from the
# pinned constants, so a rewrite can only restore the strong Server/SigLevel
# over whatever drifted. Duplicates matter because pacman registers one
# database per repository name and refuses a second registration ("failed to
# register sync database", which yay surfaces as "Database should be null"),
# which breaks every pacman transaction on the machine. The pre-repair file
# survives once at ${config}.dotfiles-backup, and the staged file is parsed
# before it replaces anything.
arch_mega_write_pinned_section() {
  local config=$1 live=$2 count=$3
  local prev_cleanup="${CLEANUP_PATH:-}" staged previous_lines
  # Read the header lines before the write: the backup is only taken on the
  # first edit, so quoting it afterwards could name a stale file.
  previous_lines="$(arch_mega_config_section_lines "${config}")"
  staged="$(mktemp "${TMPDIR:-/tmp}/arch-mega-pacman.XXXXXX")" \
    || die 'arch-mega: cannot stage the pacman config.'
  CLEANUP_PATH="${staged}"
  arch_mega_config_without_vendor_sections "${config}" >"${staged}" \
    || arch_mega_abort_staged "${staged}" "${prev_cleanup}" "arch-mega: cannot read ${config}."
  printf '\n%s\n[%s]\nSigLevel = Required DatabaseRequired\nServer = %s\n%s\n' \
    "${ARCH_MEGA_VENDOR_MARKER_BEGIN}" "${ARCH_MEGA_REPO_SECTION}" \
    "${ARCH_MEGA_REPO_SERVER}" "${ARCH_MEGA_VENDOR_MARKER_END}" >>"${staged}"
  arch_mega_deploy_staged_config "${config}" "${staged}" "${live}" "${prev_cleanup}"
  if ((count > 0)); then
    log_warn "arch-mega: replaced ${count} duplicate or drifted [DEB_Arch_Extra] section(s) in ${config} (was at line(s) ${previous_lines}) with the pinned definition; the previous file is at ${config}.dotfiles-backup."
  fi
  log_ok 'arch-mega: MEGA vendor repository configured (Thunar file manager integration source).'
}

# Fetch, verify, add and locally sign the pinned vendor key. Called only
# when the keyring probe says the key is not already trusted, so a machine
# whose key is good does no network work at all — a config-only repair must
# not hang or die on a flaky link with the repository still broken. Every
# rejection here is fail-closed: nothing reaches the live keyring unless the
# fetched file carries exactly the pinned fingerprint, one primary key, no
# revocation, and a live validity.
arch_mega_trust_vendor_key() {
  # Fetch the vendor key over TLS (no pipe-to-shell) and inspect it in an
  # isolated temp GNUPGHOME: the subshell owns its EXIT trap, so the caller's
  # traps are preserved and nothing touches the live keyring during
  # inspection. The import is scoped to the pinned fingerprint AND the whole
  # temp keyring must hold exactly one primary key: a scoped listing alone
  # would hide an extra bundled primary, while subkey packets (own fpr
  # lines, like the vendor's encryption subkey) stay allowed. Observed real
  # schema (gpg 2.4, vendor key): pub validity '-' fresh, 'e' expired,
  # 'r' revoked; expiry is field 7 (0 = never).
  local prev_cleanup="${CLEANUP_PATH:-}" tmpkey colons inspect_rc=0
  tmpkey="$(mktemp "${TMPDIR:-/tmp}/arch-mega-key.XXXXXX")" \
    || die 'arch-mega: cannot create a temp file for the vendor key.'
  CLEANUP_PATH="${tmpkey}"
  curl -fsSL --retry 3 -o "${tmpkey}" "${ARCH_MEGA_KEY_URL}" \
    || { CLEANUP_PATH="${prev_cleanup}"; rm -f -- "${tmpkey}"; die "arch-mega: failed to download ${ARCH_MEGA_KEY_URL}."; }
  colons="$(
    tmphome="$(mktemp -d "${TMPDIR:-/tmp}/arch-mega-gpg.XXXXXX")" || exit 10
    trap 'rm -rf -- "${tmphome}"' EXIT
    export GNUPGHOME="${tmphome}"
    gpg --batch --quiet --import -- "${tmpkey}" >/dev/null 2>&1 || exit 11
    scoped="$(gpg --batch --no-auto-check-trustdb --with-colons --list-keys -- "${ARCH_MEGA_KEY_FINGERPRINT}" 2>/dev/null)" || exit 12
    primaries="$(gpg --batch --no-auto-check-trustdb --with-colons --list-keys 2>/dev/null | grep -c '^pub:' || true)"
    (( primaries == 1 )) || exit 14
    printf '%s\n' "${scoped}"
  )" || inspect_rc=$?
  case "${inspect_rc}" in
    0) ;;
    14) { CLEANUP_PATH="${prev_cleanup}"; rm -f -- "${tmpkey}"; die 'arch-mega: vendor key file bundles extra primary keys besides the pinned one; refusing.'; } ;;
    *) { CLEANUP_PATH="${prev_cleanup}"; rm -f -- "${tmpkey}"; die 'arch-mega: unable to inspect the fetched vendor key with gpg.'; } ;;
  esac
  local fpr_first pub_line validity expires now
  fpr_first="$(awk -F: '/^fpr:/ {print $10; exit}' <<<"${colons}")"
  [[ ${fpr_first} == "${ARCH_MEGA_KEY_FINGERPRINT}" ]] \
    || { CLEANUP_PATH="${prev_cleanup}"; rm -f -- "${tmpkey}"; die 'arch-mega: vendor key fingerprint mismatch: the fetched key is not the pinned MEGA key; refusing.'; }
  grep -q '^rev:' <<<"${colons}" \
    && { CLEANUP_PATH="${prev_cleanup}"; rm -f -- "${tmpkey}"; die 'arch-mega: vendor key carries a revocation; refusing.'; }
  pub_line="$(grep '^pub:' <<<"${colons}" | head -n 1)"
  [[ -n ${pub_line} ]] \
    || { CLEANUP_PATH="${prev_cleanup}"; rm -f -- "${tmpkey}"; die 'arch-mega: vendor key has no public-key packet; refusing.'; }
  validity="$(cut -d: -f2 <<<"${pub_line}")"
  expires="$(cut -d: -f7 <<<"${pub_line}")"
  # Fail-closed validity whitelist: '-' is a fresh import (observed on the
  # real vendor key), 'u'/'f' are owned or locally signed. Revoked,
  # expired, invalid, or disabled keys — and anything unrecognised — refuse.
  # The '^rev:' grep above stays as a secondary tripwire only; validity is
  # the real signal (verified against live gpg 2.4 output).
  case "${validity}" in
    - | u | f) ;;
    r | e | i | d) { CLEANUP_PATH="${prev_cleanup}"; rm -f -- "${tmpkey}"; die 'arch-mega: vendor key is revoked, expired, invalid, or disabled; refusing.'; } ;;
    *) { CLEANUP_PATH="${prev_cleanup}"; rm -f -- "${tmpkey}"; die "arch-mega: vendor key reports unexpected validity '${validity}'; refusing."; } ;;
  esac
  now="$(date +%s)"
  if [[ -n ${expires} && ${expires} != 0 ]] && ((expires <= now)); then
    CLEANUP_PATH="${prev_cleanup}"; rm -f -- "${tmpkey}"
    die 'arch-mega: vendor key past its expiry date; refusing.'
  fi

  # Add the verified local key file (never --recv-keys: a keyserver lookup
  # would defeat the pinned fetched source), then locally sign it so pacman
  # trusts vendor signatures under the default TrustedOnly policy.
  sudo pacman-key --add "${tmpkey}" \
    || { CLEANUP_PATH="${prev_cleanup}"; rm -f -- "${tmpkey}"; die 'arch-mega: pacman-key --add failed for the verified vendor key.'; }
  sudo pacman-key --lsign-key "${ARCH_MEGA_KEY_FINGERPRINT}" \
    || { CLEANUP_PATH="${prev_cleanup}"; rm -f -- "${tmpkey}"; die 'arch-mega: pacman-key --lsign-key failed for the vendor key.'; }
  rm -f -- "${tmpkey}"
  CLEANUP_PATH="${prev_cleanup}"
}

# Set up the MEGA vendor repository: verify architecture, classify the
# existing config, ensure the pinned key is added and locally signed, then
# write the repository after the official ones and revalidate. Safe to
# re-run: a converged machine changes nothing and fetches nothing, and every
# other state — missing, duplicated, or drifted — converges on the pinned
# section rather than stopping for a hand edit. That matters because the
# vendor's own megasync package rewrites the section from its post_install
# with a weaker SigLevel, so a machine gets drifted (or, if two copies ever
# accumulate, duplicated) by an install nobody drove by hand. Trust still
# fails loud: a wrong key, or a foreign [mega] section we do not own, dies
# before any mutation, and the section written can only be the pinned one,
# never a relaxed signature policy. The optional path is a
# test seam (tests exercise edits on temp files); production always uses the
# default. Call only after require_arch_system and begin_elevation.
arch_mega_setup_vendor_repo() {
  local config=${1:-/etc/pacman.conf}
  local keyring="${ARCH_MEGA_KEYRING_DIR:-/etc/pacman.d/gnupg}"
  local live=false
  if [[ ${config} == /etc/pacman.conf ]]; then
    live=true
  fi

  # Vendor publishes Arch_Extra for x86_64 only: refuse anything else before
  # any trust or config mutation.
  local machine
  machine="$(uname -m)"
  [[ ${machine} == x86_64 ]] \
    || die "arch-mega: unsupported architecture '${machine}': MEGA publishes Arch_Extra for x86_64 only."

  [[ -r ${config} ]] || die "arch-mega: pacman config not found: ${config}."
  if [[ ${live} == true ]]; then
    require_command pacman-conf
  fi
  require_command curl
  require_command gpg

  # Classify the existing config before touching trust or files. A foreign
  # [mega]/[megasync] section is the one shape we never own: it configures
  # some other repository under a name we cannot vouch for, so it still
  # refuses. Everything under our own section name is ours to converge.
  local count needs_config=true
  count="$(arch_mega_config_section_count "${config}")"
  if grep -qiE '^\[(mega|megasync)\][[:space:]]*$' -- "${config}"; then
    die "arch-mega: a foreign [mega]/[megasync] section exists in ${config}; remove it by hand so only [DEB_Arch_Extra] configures the vendor repo."
  fi
  arch_mega_vendor_repo_configured "${config}" && needs_config=false

  # Read-only trust probe first: a trusted key plus a converged config means
  # zero changes and zero network below.
  local trusted=false
  arch_mega_key_trusted && trusted=true
  if [[ ${needs_config} == false && ${trusted} == true ]]; then
    if [[ ${live} == true ]]; then
      pacman-conf --repo-list 2>/dev/null | grep -Fxq "${ARCH_MEGA_REPO_SECTION}" \
        || die "arch-mega: [${ARCH_MEGA_REPO_SECTION}] is configured but pacman does not list it; check ${config}."
    fi
    log_ok 'arch-mega: MEGA vendor repository already configured and trusted.'
    return 0
  fi

  # Trust work only when the local keyring is not already good: a
  # config-only repair (the vendor package added its own duplicate section)
  # then needs no network at all.
  if [[ ${trusted} == false ]]; then
    arch_mega_trust_vendor_key
  fi

  # One writer for every state that is not already converged — missing,
  # duplicated, or drifted all end at the same pinned section. See the
  # writer for why convergence can only strengthen the config, and for the
  # vendor-last positioning that keeps vendor names from shadowing official
  # packages.
  if [[ ${needs_config} == true ]]; then
    arch_mega_write_pinned_section "${config}" "${live}" "${count}"
  else
    log_ok 'arch-mega: vendor key trust repaired.'
  fi

  arch_mega_vendor_repo_configured "${config}" \
    || die "arch-mega: repository still not configured after setup; check ${config}."
  arch_mega_key_trusted \
    || die 'arch-mega: vendor key still untrusted after setup; rerun under a fresh sudo timestamp.'
  log_ok 'arch-mega: MEGA vendor repository ready: sync it with pacman -Syu, then install megasync thunar-megasync.'
}

# Check the MEGA vendor repository without changing anything: config
# presence AND key trust (presence alone passes nothing — an added-but-
# unsigned key reports 'untrusted' as its own nonzero diagnostic). Reports
# drift; never writes, imports, signs, refreshes, or fetches. Keyring reads
# are listing-only (no trustdb mutation) and fall back to a non-interactive
# sudo probe when the keyring is root-owned. The optional path is a test
# seam (production always uses the default); the pacman/pacman-key/
# pacman-conf probes themselves are stubbed in tests.
arch_mega_verify_vendor_repo() {
  local failed=0
  local config=${1:-/etc/pacman.conf}
  # Duplicated sections get their own diagnostic: they are not drift but a
  # pacman-fatal config (the same database registered twice), and arch-setup
  # collapses identical copies, so the report must name what it sees.
  local sections
  sections="$(arch_mega_config_section_count "${config}")"
  if ((sections > 1)); then
    log_error "arch-mega: ${sections} [DEB_Arch_Extra] sections in ${config} (lines $(arch_mega_config_section_lines "${config}")); pacman cannot register one database twice. Run ./dot arch-setup."
    failed=1
  else
    arch_mega_vendor_repo_configured "${config}" \
      || { log_error "arch-mega: MEGA vendor repository missing or drifted in ${config}. Run ./dot arch-setup."; failed=1; }
  fi
  pacman-conf --repo-list 2>/dev/null | grep -Fxq "${ARCH_MEGA_REPO_SECTION}" \
    || { log_error 'arch-mega: pacman does not list [DEB_Arch_Extra]; the sync database was never fetched. Run ./dot arch-setup.'; failed=1; }
  # Presence is not trust: reuse the genuine validity probe read-only. Every
  # listing below carries --no-auto-check-trustdb, so verify never refreshes
  # or writes the system trustdb; the only writers are the explicit
  # pacman-key --add/--lsign-key calls in setup.
  local keyring="${ARCH_MEGA_KEYRING_DIR:-/etc/pacman.d/gnupg}" key_out key_status
  key_out="$(gpg --homedir "${keyring}" --batch --no-auto-check-trustdb --with-colons --list-keys "${ARCH_MEGA_KEY_FINGERPRINT}" 2>/dev/null)" || key_out=''
  if [[ -z ${key_out} ]]; then
    key_out="$(sudo -n gpg --homedir "${keyring}" --batch --no-auto-check-trustdb --with-colons --list-keys "${ARCH_MEGA_KEY_FINGERPRINT}" 2>/dev/null)" || key_out=''
  fi
  if [[ -z ${key_out} ]]; then
    log_error 'arch-mega: vendor signing key B01C811880480C854C73EC7E1A664B787094A482 not in the pacman keyring. Run ./dot arch-setup.'
    failed=1
  else
    key_status="$(arch_mega_key_trust_status "${key_out}")"
    case "${key_status}" in
      trusted) ;;
      untrusted)
        log_error 'arch-mega: vendor key present but not locally signed (untrusted); signatures will not verify. Run ./dot arch-setup.'
        failed=1
        ;;
      *)
        log_error 'arch-mega: vendor key invalid (revoked, expired, or fingerprint mismatch). Run ./dot arch-setup.'
        failed=1
        ;;
    esac
  fi
  local pkg
  for pkg in "${ARCH_MEGA_PACKAGES[@]}"; do
    pacman -Si -- "${pkg}" >/dev/null 2>&1 \
      || { log_error "arch-mega: ${pkg} not visible to pacman; sync the vendor database. Run ./dot arch-setup after the bundle installs."; failed=1; }
  done
  return "${failed}"
}
