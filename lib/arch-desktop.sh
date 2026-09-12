#!/usr/bin/env bash
set -euo pipefail
# arch-desktop.sh — Caelestia user integration for Arch-only desktops.
#
# Sourced library, not a script: dot sources this file for arch-setup /
# arch-check after lib/arch-guard.sh. Definitions only at source time; the
# arch_desktop_* functions below are the whole contract surface (five
# orchestrators decided by the lead contract, plus small list/predicate
# helpers and the user-file deploy they share).
#
# Ownership seam:
# - This module owns ONLY home-side desktop integration: the home-arch/
#   overlay (stowed, Stow ownership, no backups — the repo's stow contract),
#   except the two compositor-owned user files, which deploy as real files
#   (copy-once, never stowed: Hyprland itself recreates them within
#   milliseconds when missing, so no stow scan can own the path, and
#   upstream defines both as user-edited),
#   the Caelestia installer run and upstream tree validation, the night
#   light patch, and home-side theme enables for kept apps. Everything runs as the desktop user: no sudo anywhere here.
# - The lead owns dot, gating, packages, /etc and systemd, greetd, and
#   Limine.
# - Upstream Caelestia owns ~/.config/hypr/hyprland.lua, the whole
#   ~/.config/hypr/hyprland/ tree, ~/.local/state/caelestia/*, and
#   ~/.config/uwsm/*: this module patches execs.lua and verifies the rest,
#   but never overwrites generated files wholesale.
#
# Dot-provided interface (must exist before sourcing): DOTFILES_DIR, HOME,
# log_step/log_ok/log_info/log_warn/log_error, die, require_command.
# The vocabulary matches dot on purpose: one concept, one spelling, so a
# search for any of these names lands in exactly one definition site.
#
# Idempotent source guard (ARCH_DESKTOP_SOURCED marker): a same-process
# repeat source returns here with zero side effects instead of dying on
# readonly redeclaration. The marker is set only after the caller vars
# validate below, so a failed source never marks half-loaded.
if [[ -n ${ARCH_DESKTOP_SOURCED:-} ]]; then
  # Explicit source-vs-execute split (same outcome as return-or-exit, but
  # both halves stay reachable to static analysis).
  if [[ "${BASH_SOURCE[0]:-}" != "${0:-}" ]]; then
    return 0
  fi
  exit 0
fi

# Explicit validation (not :? expansion): :? aborts non-interactive shells
# but merely continues an interactive source, which would mark half-loaded.
# These returns stop the source in every mode before anything is defined.
if [[ -z ${DOTFILES_DIR:-} ]]; then
  printf 'arch-desktop.sh must be sourced after DOTFILES_DIR is set\n' >&2
  if [[ "${BASH_SOURCE[0]:-}" != "${0:-}" ]]; then
    return 1
  fi
  exit 1
fi
if [[ -z ${HOME:-} ]]; then
  printf 'arch-desktop.sh must be sourced with HOME set\n' >&2
  if [[ "${BASH_SOURCE[0]:-}" != "${0:-}" ]]; then
    return 1
  fi
  exit 1
fi
readonly ARCH_DESKTOP_SOURCED=1

# Overlay source: the Arch-only home tree, mirrored on $HOME like home/.
readonly ARCH_DESKTOP_OVERLAY_DIR="${DOTFILES_DIR}/home-arch"
# Deployed Hyprland entry file: upstream-owned, real file, never a symlink.
readonly ARCH_DESKTOP_HYPR_MAIN_CONFIG="${HOME}/.config/hypr/hyprland.lua"

# Internal locations (upstream-owned or XDG-derived; verified, never defined
# as contract because only this module reads them).
readonly ARCH_DESKTOP_HYPR_CONFIG_DIR="${HOME}/.config/hypr"
readonly ARCH_DESKTOP_HYPR_EXECS_CONFIG="${HOME}/.config/hypr/hyprland/execs.lua"
readonly ARCH_DESKTOP_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
readonly ARCH_DESKTOP_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
readonly ARCH_DESKTOP_CAELESTIA_STATE_DIR="${ARCH_DESKTOP_STATE_HOME}/caelestia"
readonly ARCH_DESKTOP_CAELESTIA_STATE_FILE="${ARCH_DESKTOP_CAELESTIA_STATE_DIR}/dots-state.json"
readonly ARCH_DESKTOP_CAELESTIA_DOTS_DIR="${ARCH_DESKTOP_CAELESTIA_STATE_DIR}/dots"
readonly ARCH_DESKTOP_UWSM_CONFIG_DIR="${ARCH_DESKTOP_CONFIG_HOME}/uwsm"
# Hyprland Lua config generation Caelestia requires; below it the old .conf
# format cannot express the deployed tree.
readonly ARCH_DESKTOP_MIN_HYPRLAND='0.55.0'
# Caelestia shell autostart and module wiring this integration requires in
# the deployed tree (fail loud when absent, never silently half-themed).
readonly ARCH_DESKTOP_EXECS_REQUIRE_PATTERN="require[[:space:]]*\\([[:space:]]*['\"]hyprland\\.execs['\"][[:space:]]*\\)"
readonly ARCH_DESKTOP_START_EVENT_PATTERN="hl\\.on[[:space:]]*\\([[:space:]]*['\"]hyprland\\.start['\"]"
readonly ARCH_DESKTOP_AUTOSTART_PATTERN="hl\\.exec_cmd[[:space:]]*\\([[:space:]]*['\"]caelestia[[:space:]]+shell[[:space:]]+-d['\"][[:space:]]*\\)"

# arch_desktop_night_light_patch prints the Caelestia night light patch:
# makes the GeoClue + Gammastep startup in generated hyprland/execs.lua obey
# hypr-vars.lua's automaticNightLight flag. Applies with patch --fuzz=0, so
# upstream drift fails loudly instead of half-applying; the failure message
# names this literal for refresh. Internal data, kept beside its applier so
# the patched concept and the patch text share one searchable home.
arch_desktop_night_light_patch() {
  cat <<'ARCH_DESKTOP_EXECS_PATCH'
--- execs.lua
+++ execs.lua
@@ -21,3 +21,5 @@
-    -- Location provider and night light
-    hl.exec_cmd("/usr/lib/geoclue-2.0/demos/agent")
-    hl.exec_cmd("sleep 1 && gammastep")
+    if vars.automaticNightLight ~= false then
+        -- Location provider and night light
+        hl.exec_cmd("/usr/lib/geoclue-2.0/demos/agent")
+        hl.exec_cmd("sleep 1 && gammastep")
+    end
ARCH_DESKTOP_EXECS_PATCH
}

# arch_desktop_require_caller_interface dies unless dot's logging interface
# is present. Internal guard called first by every contract function, so a
# sourcing-order bug fails here with one clear message.
arch_desktop_require_caller_interface() {
  local missing=() symbol
  for symbol in log_step log_ok log_info log_warn log_error die require_command; do
    declare -F "${symbol}" >/dev/null 2>&1 || missing+=("${symbol}")
  done
  if ((${#missing[@]} > 0)); then
    printf 'arch-desktop: missing caller interface: %s\n' "${missing[*]}" >&2
    return 1
  fi
}

# arch_desktop_overlay_relpaths prints every overlay file as a $HOME-relative
# path, one per line in stable order. Internal single source for install
# pre-clean and overlay verification.
arch_desktop_overlay_relpaths() {
  [[ -d ${ARCH_DESKTOP_OVERLAY_DIR} ]] || return 1
  find "${ARCH_DESKTOP_OVERLAY_DIR}" -mindepth 1 -type f -print0 | sort -z \
    | while IFS= read -r -d '' src; do
      printf '%s\n' "${src#"${ARCH_DESKTOP_OVERLAY_DIR}/"}"
    done
  return 0
}

# arch_desktop_override_relpaths prints the DELIBERATE same-path overlays:
# relpaths this overlay intentionally shadows from shared home/ on Arch.
# Dot's distro-aware shared-home exclusion consumes this list. Anything
# colliding with home/ that is NOT listed here dies loudly in install
# instead of silently shadowing. Internal helper, but dot-facing: keep the
# contract names stable and report additions to the lead.
arch_desktop_override_relpaths() {
  # Deliberate Arch shadows of shared home/ paths, one per line.
  printf '%s\n' \
    '.config/ghostty/config'
}

# arch_desktop_deployed_relpaths prints the compositor-owned user files:
# overlay paths deployed as REAL files, never stowed. Hyprland's own
# hyprland.lua recreates these within milliseconds when missing
# (maybe_create), so a stow pre-clean plus a slow tree scan can never own
# the path without racing; upstream also defines both as user-edited
# (monitor layout, default apps), which a symlink would force into the
# repo. Internal single source for install, verify, and dot's stow/doctor
# (dot lazy-sources this module and calls the predicate and deploy below,
# never reimplementing them).
arch_desktop_deployed_relpaths() {
  printf '%s\n' \
    '.config/caelestia/hypr-user.lua' \
    '.config/caelestia/hypr-vars.lua'
}

# arch_desktop_is_deployed_file reports whether relpath deploys as a real
# file instead of a stow symlink. Same shape as is_approved_override.
arch_desktop_is_deployed_file() {
  local rel=$1 candidate
  while IFS= read -r candidate; do
    [[ -n ${candidate} && ${rel} == "${candidate}" ]] && return 0
  done < <(arch_desktop_deployed_relpaths) || true
  return 1
}

# arch_desktop_deploy_user_files copies each deployed template to $HOME as
# a real file. Copy-once semantics: a missing target is copied; a legacy
# symlink to the template is converted; a compositor placeholder (empty or
# exactly `return {}` — the only bytes maybe_create writes) is replaced.
# Anything else is user content and is left alone, so an active monitor
# block survives every re-run. No backups (home files never do), no sudo.
# Dies on a missing template, a foreign symlink, or a non-file target.
arch_desktop_deploy_user_files() {
  arch_desktop_require_caller_interface || return 1
  local rel template target content
  while IFS= read -r rel; do
    [[ -n ${rel} ]] || continue
    template="${ARCH_DESKTOP_OVERLAY_DIR}/${rel}"
    target="${HOME}/${rel}"
    [[ -f ${template} && ! -L ${template} ]] \
      || die "arch_desktop_deploy_user_files: template missing: ${template}"
    if [[ -L ${target} ]]; then
      if [[ "$(realpath -m -- "${target}")" == "$(realpath -m -- "${template}")" ]]; then
        log_info "arch-desktop: converting legacy symlink ${target} to a real file"
        rm -f -- "${target}"
      else
        die "arch_desktop_deploy_user_files: ${target} is a foreign symlink; refusing to deploy over it."
      fi
    fi
    if [[ -e ${target} ]]; then
      [[ -f ${target} && ! -L ${target} ]] \
        || die "arch_desktop_deploy_user_files: ${target} is not a regular file; refusing to deploy over it."
      content="$(cat -- "${target}")"
      if [[ -z ${content} || ${content} == 'return {}' ]]; then
        log_info "arch-desktop: replacing compositor placeholder ${target}"
        cp -- "${template}" "${target}"
      else
        log_info "arch-desktop: keeping user file ${target}"
      fi
    else
      mkdir -p -- "$(dirname -- "${target}")"
      cp -- "${template}" "${target}"
      log_info "arch-desktop: deployed ${target}"
    fi
  done < <(arch_desktop_deployed_relpaths) || true
}

# arch_desktop_is_approved_override reports whether relpath may shadow home/.
arch_desktop_is_approved_override() {
  local rel=$1 candidate
  while IFS= read -r candidate; do
    [[ -n ${candidate} && ${rel} == "${candidate}" ]] && return 0
  done < <(arch_desktop_override_relpaths) || true
  return 1
}

# arch_desktop_overlay_available is non-mutating: 0 iff the overlay dir
# exists and contains files, else 1. Logging only, no sudo.
arch_desktop_overlay_available() {
  arch_desktop_require_caller_interface || return 1
  if [[ -d ${ARCH_DESKTOP_OVERLAY_DIR} ]] \
    && find "${ARCH_DESKTOP_OVERLAY_DIR}" -mindepth 1 -type f -print -quit 2>/dev/null | grep -q .; then
    log_info "arch-desktop: overlay available at ${ARCH_DESKTOP_OVERLAY_DIR}."
    return 0
  fi
  log_warn "arch-desktop: overlay missing or empty at ${ARCH_DESKTOP_OVERLAY_DIR}."
  return 1
}

# arch_desktop_install_overlay stows home-arch/ into $HOME with the repo's
# stow contract: overwrite-without-backup, idempotent re-run, no sudo.
# Pre-clean removes conflicting files and symlinks (including dangling
# ones) for the STOWED set only; deployed user files are owned by
# arch_desktop_deploy_user_files below (no pre-clean touch, so a live
# compositor can never catch the path missing). A real directory collision
# dies like dot's own stow. A target that
# resolves into shared home/ is an UNAPPROVED collision unless its relpath
# is listed by arch_desktop_override_relpaths — deliberate shadows
# (Ghostty) proceed, anything else dies loudly instead of silently
# shadowing a shared config. The stow --ignore literal below must stay
# identical to dot's stow_arch_overlay (stow walks the tree itself, so the
# predicate alone cannot exclude these).
arch_desktop_install_overlay() {
  arch_desktop_require_caller_interface || return 1
  arch_desktop_overlay_available || die 'arch_desktop_install_overlay: overlay missing; refusing a silent no-op.'
  require_command stow
  [[ -d ${ARCH_DESKTOP_OVERLAY_DIR} ]] || die 'arch_desktop_install_overlay: overlay dir vanished.'
  if find "${ARCH_DESKTOP_OVERLAY_DIR}" -mindepth 1 ! -type d ! -type f -print -quit 2>/dev/null | grep -q .; then
    die 'arch_desktop_install_overlay: overlay source contains a symlink or special file; refusing to deploy links.'
  fi
  log_step "arch-desktop: stowing home-arch/ into ${HOME}"
  local rel target resolved
  while IFS= read -r rel; do
    [[ -n ${rel} ]] || continue
    # Deployed user files are owned by the deploy step below: never
    # pre-clean them (a live compositor recreates a missing path within
    # milliseconds, which is exactly the race that aborts stow).
    arch_desktop_is_deployed_file "${rel}" && continue
    target="${HOME}/${rel}"
    if [[ -e ${target} || -L ${target} ]]; then
      if [[ -d ${target} && ! -L ${target} ]]; then
        die "arch_desktop_install_overlay: cannot stow ${rel}: ${target} is a real directory."
      fi
      if [[ -L ${target} ]] && resolved="$(realpath -m -- "${target}" 2>/dev/null)" \
        && [[ ${resolved} == "${DOTFILES_DIR}/home/"* ]] \
        && ! arch_desktop_is_approved_override "${rel}"; then
        die "arch_desktop_install_overlay: ${rel} would shadow shared home/ unapproved; list it in arch_desktop_override_relpaths or remove it from home-arch/."
      fi
      [[ "$(realpath -m -- "${target}")" == "$(realpath -m -- "${ARCH_DESKTOP_OVERLAY_DIR}/${rel}")" ]] && continue
      log_info "arch-desktop: overwriting ${target}"
      rm -f -- "${target}"
    fi
  done < <(arch_desktop_overlay_relpaths) || true
  stow -R --no-folding --ignore='(^|/)node_modules(/|$)' \
    --ignore='(^|/)\.config/caelestia/hypr-(user|vars)\.lua$' \
    -d "${DOTFILES_DIR}" -t "${HOME}" home-arch \
    || die 'arch_desktop_install_overlay: stow failed.'
  arch_desktop_deploy_user_files
  log_ok 'arch-desktop: overlay stowed.'
}

# arch_desktop_expected_execs renders the patch expectation for a generated
# execs.lua into output_file (internal): the source tree's file plus the
# night light guard, or a loud death on upstream drift.
arch_desktop_expected_execs() {
  local source_file=$1 output_file=$2
  require_command patch
  cp -- "${source_file}" "${output_file}"
  arch_desktop_night_light_patch \
    | patch --silent --fuzz=0 --no-backup-if-mismatch "${output_file}" \
    || die 'arch_desktop_expected_execs: Caelestia changed hyprland/execs.lua; refresh the arch_desktop_night_light_patch literal.'
}

# arch_desktop_caelestia_tree_complete is the internal install-state
# validation adapted from the archive: dots-state.json names a checked-out
# revision with the hypr and uwsm components; every file of that revision's
# hypr tree is deployed as a real file matching source (execs.lua matching
# the patch-rendered expectation); no symlinks anywhere under ~/.config/hypr
# (this presupposes the lead's shared hypr/input.lua exclusion on Arch —
# without it a working tree still fails here, loudly, by design).
# Fish is deliberately NOT required in dots-state: the overlay's
# conf.d/caelestia-*.fish snippets replay the scheme and carry the Arch
# terminal look without the installer's
# fish component ever editing the shared stowed fish config.
# Endless-reinstall audit (vendor-verified): the walk compares SOURCE-tracked
# files only. Runtime-mutated files (hypr/scheme/current.lua, scheme.json,
# sequences.txt, gtk.css/thunar.css/fuzzel.ini/discord
# themes) are generated beside the tree, never tracked in dots, so scheme
# switches and theme updates can never dirty this check.
arch_desktop_caelestia_tree_complete() {
  local applied_rev source_rev source_file relative_file target_file expected_file
  local found_file=false
  command -v jq >/dev/null 2>&1 || return 1
  command -v git >/dev/null 2>&1 || return 1
  applied_rev="$(jq -er '.applied_rev | select(type == "string" and length > 0)' "${ARCH_DESKTOP_CAELESTIA_STATE_FILE}" 2>/dev/null)" || return 1
  jq -e '(.enabled_components | type == "array" and index("hypr") != null) and (.enabled_components | index("uwsm") != null)' \
    "${ARCH_DESKTOP_CAELESTIA_STATE_FILE}" >/dev/null 2>&1 || return 1
  [[ -d ${ARCH_DESKTOP_CAELESTIA_DOTS_DIR}/.git ]] || return 1
  source_rev="$(git -C "${ARCH_DESKTOP_CAELESTIA_DOTS_DIR}" rev-parse HEAD 2>/dev/null)" || return 1
  [[ ${source_rev} == "${applied_rev}" && -d ${ARCH_DESKTOP_CAELESTIA_DOTS_DIR}/hypr ]] || return 1
  if find "${ARCH_DESKTOP_CAELESTIA_DOTS_DIR}/hypr" -mindepth 1 ! -type d ! -type f -print -quit 2>/dev/null | grep -q .; then
    return 1
  fi
  while IFS= read -r -d '' source_file; do
    found_file=true
    relative_file="${source_file#"${ARCH_DESKTOP_CAELESTIA_DOTS_DIR}"/hypr/}"
    target_file="${ARCH_DESKTOP_HYPR_CONFIG_DIR}/${relative_file}"
    [[ -f ${target_file} && ! -L ${target_file} ]] || return 1
    if [[ ${relative_file} == hyprland/execs.lua ]]; then
      expected_file="$(mktemp "${TMPDIR:-/tmp}/arch-desktop-expected-XXXXXX")" || return 1
      if ! arch_desktop_expected_execs "${source_file}" "${expected_file}"; then
        rm -f -- "${expected_file}"
        return 1
      fi
      cmp -s -- "${expected_file}" "${target_file}" || { rm -f -- "${expected_file}"; return 1; }
      rm -f -- "${expected_file}"
    else
      cmp -s -- "${source_file}" "${target_file}" || return 1
    fi
  done < <(find "${ARCH_DESKTOP_CAELESTIA_DOTS_DIR}/hypr" -type f -print0 2>/dev/null) || true
  [[ ${found_file} == true ]] || return 1
  [[ -f ${ARCH_DESKTOP_UWSM_CONFIG_DIR}/env && -f ${ARCH_DESKTOP_UWSM_CONFIG_DIR}/env-hyprland ]] || return 1
  ! find "${ARCH_DESKTOP_HYPR_CONFIG_DIR}" -type l -print -quit 2>/dev/null | grep -q .
}

# arch_desktop_run_caelestia_installer runs the upstream dotfiles installer
# for a missing/incomplete tree (internal). Fully flagged + non-interactive:
# every flag is pre-verified against this CLI's own help, so an older
# incompatible CLI dies BEFORE any mutation instead of falling back to a
# guessed interactive run. Component policy, verified against the vendor
# manifest (dots manifest.toml @ tip) — enable exactly uwsm (greeter
# session) + nvim (two additive files into the kept neovim); disable
# firefox (Brave Origin system), fish/starship/fastfetch (their entries
# would detach shared stowed configs), foot/micro (second terminal/editor
# vs kept ghostty/neovim), btop (its workspace launcher hardcodes foot).
# Explicitly disable every optional app component we never want the
# installer to manage (discord/spotify/vscode/vscodium/zed/todoist/zen):
# they default off today, so this is a no-op now, but it holds if upstream
# ever flips one to default on. discord is load-bearing: its package is
# equibop-bin, which Provides/Conflicts equibop against the bundle's
# equibop-git — letting it install prompts `Remove equibop-git?` and blocks
# the non-interactive run. Discord theming still arrives via scheme-time
# apply_discord plus arch_desktop_enable_equibop_theme, never via install.
# --aur-helper yay is deterministic (repo standard; autodetection would take
# paru when present). --noconfirm fits the scripted context (defaults,
# incl. the one-time ~/.config backup; pause skipped). No deploy-only flag
# exists upstream, so package scope is controlled through components; the
# remaining defaults' packages are lead-bundled (installer skips installed).
arch_desktop_run_caelestia_installer() {
  require_command caelestia
  local install_help flag
  install_help="$(caelestia install --help 2>&1)" || install_help=''
  for flag in --noconfirm --disable-components --enable-components --aur-helper; do
    grep -Fq -- "${flag}" <<<"${install_help}" \
      || die "arch_desktop_run_caelestia_installer: installed caelestia-cli lacks ${flag}; upgrade caelestia-cli, then rerun."
  done
  log_step 'arch-desktop: running the Caelestia dotfiles installer'
  log_warn 'arch-desktop: package install + Quickshell build take a while; output follows.'
  local -a installer_args=(
    install --noconfirm
    --aur-helper yay
    --disable-components "firefox,fish,starship,fastfetch,foot,micro,btop,discord,spotify,vscode,vscodium,zed,todoist,zen"
    --enable-components "uwsm,nvim"
  )
  caelestia "${installer_args[@]}" \
    || die 'arch_desktop_run_caelestia_installer: installer failed; read its output above.'
}

# arch_desktop_apply_night_light_patch guards the deployed execs.lua
# (internal): skip when the marker is present; die loudly when the target is
# missing (the tree is required here, never warn-green) or when the patch no
# longer applies (upstream drift); refuse symlinked targets.
arch_desktop_apply_night_light_patch() {
  local target=${ARCH_DESKTOP_HYPR_EXECS_CONFIG}
  require_command patch
  [[ -f ${target} ]] \
    || die "arch_desktop_apply_night_light_patch: missing ${target}; the Caelestia tree is required, run the installer step first."
  [[ ! -L ${target} ]] \
    || die "arch_desktop_apply_night_light_patch: refusing to patch through a symlink: ${target}"
  grep -Fq 'automaticNightLight ~= false' "${target}" && return 0
  arch_desktop_night_light_patch \
    | patch --silent --fuzz=0 --no-backup-if-mismatch "${target}" \
    || die 'arch_desktop_apply_night_light_patch: Caelestia changed hyprland/execs.lua; refresh the arch_desktop_night_light_patch literal.'
  log_ok 'arch-desktop: night light guard applied to hyprland/execs.lua.'
}

# arch_desktop_enable_equibop_theme enables Caelestia's generated Equibop
# theme in the local theme list (internal, kept app only — never installs
# anything): quiet skip when the installer never generated the theme;
# warn-skip when settings are absent (launch Equibop once); loud death only
# when an update is attempted and fails. Config dir stays `equibop/`
# regardless of the package name (`equibop` vs `equibop-git`): the vendor
# config home does not follow the AUR suffix.
arch_desktop_enable_equibop_theme() {
  local config_home theme_file settings_file tmp
  config_home="${ARCH_DESKTOP_CONFIG_HOME}"
  theme_file="${config_home}/equibop/themes/caelestia.theme.css"
  settings_file="${config_home}/equibop/settings/settings.json"
  [[ -f ${theme_file} ]] || {
    log_info 'arch-desktop: no generated Caelestia Equibop theme; leaving Equibop alone.'
    return 0
  }
  require_command jq
  [[ -f ${settings_file} && ! -L ${settings_file} ]] || {
    log_warn "arch-desktop: ${settings_file} missing or linked; launch Equibop once, then rerun."
    return 0
  }
  tmp="$(mktemp "${TMPDIR:-/tmp}/arch-desktop-equibop-XXXXXX")" \
    || die 'arch_desktop_enable_equibop_theme: cannot create a staging file.'
  jq '.enabledThemes = ((if (.enabledThemes | type) == "array" then .enabledThemes else [] end) | if index("caelestia.theme.css") == null then . + ["caelestia.theme.css"] else . end)' \
    "${settings_file}" >"${tmp}" \
    || { rm -f -- "${tmp}"; die "arch_desktop_enable_equibop_theme: cannot update ${settings_file}."; }
  install --mode=0644 "${tmp}" "${settings_file}" \
    || { rm -f -- "${tmp}"; die "arch_desktop_enable_equibop_theme: cannot write ${settings_file}."; }
  rm -f -- "${tmp}"
  log_ok 'arch-desktop: Equibop Caelestia theme enabled.'
}

# arch_desktop_configure_caelestia is the home-side Caelestia runtime
# integration: mutating, idempotent, no sudo. From a minimal setup it
# delivers the desktop: validates the install state, runs the upstream
# installer when the tree is missing/incomplete (fully flagged +
# non-interactive), re-stows the overlay so managed overrides stay
# authoritative over installer defaults, guards execs.lua with the night
# light patch, then gates on the patched tree (patch precedes the gate:
# the check expects patched execs.lua, so gating first would brick every
# pristine first install). Then Equibop theme when supported,
# and a final Hyprland verify. A missing required tree is a loud death,
# never warn-green. Sequence contract: packages (lead) -> this -> overlay
# verify + caelestia verify (greeter gate) -> greeter/limine (lead).
arch_desktop_configure_caelestia() {
  arch_desktop_require_caller_interface || return 1
  require_command pacman
  require_command vercmp
  require_command jq
  require_command git
  local hyprland_version verify_output
  hyprland_version="$(pacman -Q hyprland 2>/dev/null | awk 'NF >= 2 { print $2; exit }')" || hyprland_version=''
  if [[ -z ${hyprland_version} || $(vercmp "${hyprland_version}" "${ARCH_DESKTOP_MIN_HYPRLAND}") -lt 0 ]]; then
    die "arch_desktop_configure_caelestia: Caelestia needs Hyprland ${ARCH_DESKTOP_MIN_HYPRLAND}+; installed: ${hyprland_version:-missing}."
  fi
  if ! arch_desktop_caelestia_tree_complete; then
    log_step 'arch-desktop: Caelestia tree incomplete; installing upstream'
    arch_desktop_run_caelestia_installer
    # The installer writes defaults over this module's managed overrides;
    # re-stow so the overlay stays authoritative (idempotent, same package).
    arch_desktop_install_overlay
  fi
  # Patch BEFORE the gate: tree_complete expects the patched execs.lua, so
  # gating a pristine installer output first would die forever without ever
  # reaching the patch. apply dies loudly on missing target or drift.
  arch_desktop_apply_night_light_patch
  arch_desktop_caelestia_tree_complete \
    || die 'arch_desktop_configure_caelestia: tree incomplete after install and patch; rerun and read the output above.'
  arch_desktop_enable_equibop_theme
  if [[ -f ${ARCH_DESKTOP_HYPR_MAIN_CONFIG} ]]; then
    if verify_output="$(Hyprland --verify-config --config "${ARCH_DESKTOP_HYPR_MAIN_CONFIG}" 2>&1)"; then
      log_ok 'arch-desktop: Hyprland accepts the integrated tree.'
    else
      die "arch_desktop_configure_caelestia: Hyprland rejects the integrated tree: ${verify_output//$'\n'/; }"
    fi
  else
    die "arch_desktop_configure_caelestia: entry file missing after integration: ${ARCH_DESKTOP_HYPR_MAIN_CONFIG}"
  fi
  log_ok 'arch-desktop: Caelestia configured.'
}

# arch_desktop_verify_overlay is non-mutating: 0 iff every STOWED overlay
# file is deployed as a symlink resolving into the overlay source (Stow
# ownership) and every DEPLOYED user file exists as a real, configured file
# (legacy symlinks and compositor placeholders fail: rerun install).
# Never writes, no sudo.
arch_desktop_verify_overlay() {
  arch_desktop_require_caller_interface || return 1
  arch_desktop_overlay_available || return 1
  local failed=0 rel source target content
  while IFS= read -r rel; do
    [[ -n ${rel} ]] || continue
    arch_desktop_is_deployed_file "${rel}" && continue
    source="${ARCH_DESKTOP_OVERLAY_DIR}/${rel}"
    target="${HOME}/${rel}"
    if [[ ! -L ${target} ]]; then
      log_error "arch-desktop: not a stowed symlink: ${target}"
      failed=1
    elif [[ "$(realpath -m -- "${target}")" != "$(realpath -m -- "${source}")" ]]; then
      log_error "arch-desktop: points outside the overlay: ${target}"
      failed=1
    fi
  done < <(arch_desktop_overlay_relpaths) || true
  while IFS= read -r rel; do
    [[ -n ${rel} ]] || continue
    target="${HOME}/${rel}"
    if [[ -L ${target} ]]; then
      log_error "arch-desktop: legacy symlink (not a deployed real file): ${target}; rerun install."
      failed=1
    elif [[ ! -f ${target} ]]; then
      log_error "arch-desktop: user file not deployed: ${target}; rerun install."
      failed=1
    else
      content="$(cat -- "${target}")"
      if [[ -z ${content} || ${content} == 'return {}' ]]; then
        log_error "arch-desktop: unconfigured compositor placeholder: ${target}; rerun install."
        failed=1
      fi
    fi
  done < <(arch_desktop_deployed_relpaths) || true
  if ((failed != 0)); then
    log_error 'arch-desktop: overlay incomplete; rerun install.'
    return 1
  fi
  log_ok 'arch-desktop: overlay complete vs source.'
}

# arch_desktop_verify_caelestia is non-mutating and THE GREETER GATE: 0 iff
# the entry file exists as a real file, the execs require plus shell
# autostart patterns are present, no symlinks sit under ~/.config/hypr, and
# Hyprland --verify-config passes. Read-only checks only, no sudo.
arch_desktop_verify_caelestia() {
  arch_desktop_require_caller_interface || return 1
  require_command Hyprland
  [[ -f ${ARCH_DESKTOP_HYPR_MAIN_CONFIG} && ! -L ${ARCH_DESKTOP_HYPR_MAIN_CONFIG} ]] \
    || die "arch_desktop_verify_caelestia: entry file missing or linked: ${ARCH_DESKTOP_HYPR_MAIN_CONFIG}"
  grep -Eq "${ARCH_DESKTOP_EXECS_REQUIRE_PATTERN}" "${ARCH_DESKTOP_HYPR_MAIN_CONFIG}" \
    || die "arch_desktop_verify_caelestia: entry file does not load hyprland.execs."
  # A && B || die is the intended check-fail shape here (die runs exactly
  # when either pattern is absent), not a mistaken if/then/else.
  # shellcheck disable=SC2015
  grep -Eq "${ARCH_DESKTOP_START_EVENT_PATTERN}" "${ARCH_DESKTOP_HYPR_EXECS_CONFIG}" \
    && grep -Eq "${ARCH_DESKTOP_AUTOSTART_PATTERN}" "${ARCH_DESKTOP_HYPR_EXECS_CONFIG}" \
    || die "arch_desktop_verify_caelestia: shell autostart callback missing in hyprland/execs.lua."
  if find "${ARCH_DESKTOP_HYPR_CONFIG_DIR}" -type l -print -quit 2>/dev/null | grep -q .; then
    die 'arch_desktop_verify_caelestia: symlinked file under ~/.config/hypr (upstream tree must be real files; shared hypr/input.lua must be excluded on Arch).'
  fi
  local verify_output
  if verify_output="$(Hyprland --verify-config --config "${ARCH_DESKTOP_HYPR_MAIN_CONFIG}" 2>&1)"; then
    log_ok 'arch-desktop: Caelestia tree verifies (greeter gate open).'
  else
    die "arch_desktop_verify_caelestia: Hyprland rejects the tree: ${verify_output//$'\n'/; }"
  fi
}
