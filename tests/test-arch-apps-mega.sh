#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# shellcheck disable=SC2016 # $arch literals throughout are pacman file content, never expansions.
# tests/test-arch-apps-mega.sh — the MEGA vendor repository seam is secure,
# idempotent, and fail-loud before any trust or config mutation.
#
# Security route evidence (read-only vendor fetch, 2026-09-10, cited not
# re-fetched — this suite uses no network): https://mega.io/desktop embeds
# Arch_Extra x86_64 megasync + thunar-megasync tarballs; the repo index holds
# a signed DEB_Arch_Extra.db plus per-package .sig files; key
# DEB_Arch_Extra.key fingerprints B01C811880480C854C73EC7E1A664B787094A482
# (MegaLimited) and verifies the Thunar package in an isolated GNUPGHOME.
# The gpg/pacman-key/pacman-conf/curl externals below are stubbed with canned
# --with-colons output so parsing and ordering are deterministic; real crypto
# was verified once by hand and must not run in this hermetic suite.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox

PINNED='B01C811880480C854C73EC7E1A664B787094A482'
export ARCH_MEGA_KEYRING_DIR="${TEST_ARCH_SANDBOX}/keyring"
mkdir -p -- "${ARCH_MEGA_KEYRING_DIR}"

# --- stubs ---------------------------------------------------------------

test_arch_stub_passthrough_sudo

cat >"${TEST_ARCH_BIN}/uname" <<EOF
#!/usr/bin/env bash
printf 'uname %s\n' "\$*" >>"$(test_arch_calls_log)"
printf '%s\n' "\${TEST_UNAME_M:-x86_64}"
EOF
chmod 755 -- "${TEST_ARCH_BIN}/uname"

# curl stub: logs, optionally fails, otherwise materialises the -o target.
cat >"${TEST_ARCH_BIN}/curl" <<EOF
#!/usr/bin/env bash
printf 'curl %s\n' "\$*" >>"$(test_arch_calls_log)"
if [[ "\${TEST_CURL_FAIL:-0}" == 1 ]]; then
  exit 1
fi
out=''
prev=''
for a in "\$@"; do
  [[ \${prev} == -o ]] && out=\${a}
  prev=\${a}
done
printf 'fixture-vendor-key-bytes\n' >"\${out}"
EOF
chmod 755 -- "${TEST_ARCH_BIN}/curl"

# gpg stub: canned --with-colons output in VERIFIED real forms (gpg 2.4:
# fresh imports show pub validity '-', expired 'e', revoked 'r', expiry is
# field 7; subkeys carry their own differing fpr lines). TEST_GPG_SHOW_MODE
# drives the fetched-file inspection (good/mismatch/revoked/expired/extrapub/
# fail); TEST_GPG_TRUST_MODE drives the keyring trust probe
# (trusted/untrusted/absent). Scoped (pinned-fpr argument) vs unscoped
# listings are distinguished exactly like the module's two calls, so the
# extra-bundled-primary case is faithful: scoped shows the pinned key while
# the unscoped count sees two primaries.
cat >"${TEST_ARCH_BIN}/gpg" <<EOF
#!/usr/bin/env bash
printf 'gpg %s\n' "\$*" >>"$(test_arch_calls_log)"
if [[ " \$* " == *" --import "* ]]; then
  [[ "\${TEST_GPG_SHOW_MODE:-good}" == fail ]] && exit 1
  exit 0
fi
if [[ " \$* " == *" --list-keys "* ]]; then
  if [[ -e "${TEST_ARCH_SANDBOX}/lsigned" ]]; then
    printf 'pub:f:4096:1:948A482:1780000000:1956528000:::\n'
    printf 'fpr:::::::::${PINNED}:\n'
    exit 0
  fi
  if [[ " \$* " == *" \${HOME} "* ]] || [[ " \$* " == *"--homedir ${TEST_ARCH_SANDBOX}"* ]]; then
    mode="\${TEST_GPG_TRUST_MODE:-trusted}"
  else
    mode="\${TEST_GPG_SHOW_MODE:-good}"
  fi
  case "\${mode}" in
    trusted)
      printf 'pub:f:4096:1:948A482:1780000000:1956528000:::\n'
      printf 'fpr:::::::::${PINNED}:\n'
      printf 'sub:-:4096:1:DEADBEEF:1780000000:1956528000:::\n'
      printf 'fpr:::::::::AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:\n'
      ;;
    untrusted)
      printf 'pub:-:4096:1:948A482:1780000000:1956528000:::\n'
      printf 'fpr:::::::::${PINNED}:\n'
      ;;
    absent) exit 1 ;;
    good)
      printf 'pub:-:4096:1:948A482:1780000000:1956528000:::\n'
      printf 'fpr:::::::::${PINNED}:\n'
      printf 'sub:-:4096:1:DEADBEEF:1780000000:1956528000:::\n'
      printf 'fpr:::::::::AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:\n'
      ;;
    mismatch)
      printf 'pub:-:4096:1:FFFFFFFF:1780000000:1956528000:::\n'
      printf 'fpr:::::::::AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:\n'
      ;;
    revoked)
      printf 'pub:r:4096:1:948A482:1780000000:1780000001:::\n'
      printf 'fpr:::::::::${PINNED}:\n'
      printf 'sub:r:4096:1:DEADBEEF:1780000000:1780000001:::\n'
      printf 'fpr:::::::::AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:\n'
      ;;
    extrapub)
      if [[ " \$* " == *"${PINNED}"* ]]; then
        printf 'pub:-:4096:1:948A482:1780000000:1956528000:::\n'
        printf 'fpr:::::::::${PINNED}:\n'
      else
        printf 'pub:-:4096:1:948A482:1780000000:1956528000:::\n'
        printf 'fpr:::::::::${PINNED}:\n'
        printf 'pub:-:2048:1:EEEEEEEE:1780000000:1956528000:::\n'
        printf 'fpr:::::::::EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE:\n'
      fi
      ;;
    expired)
      printf 'pub:e:4096:1:948A482:1000000000:1100000000:::\n'
      printf 'fpr:::::::::${PINNED}:\n'
      ;;
    fail) exit 1 ;;
  esac
  exit 0
fi
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/gpg"

# pacman-key stub: mutations log and succeed unless TEST_PACMAN_KEY_FAIL=1.
cat >"${TEST_ARCH_BIN}/pacman-key" <<EOF
#!/usr/bin/env bash
printf 'pacman-key %s\n' "\$*" >>"$(test_arch_calls_log)"
if [[ " \$* " == *" --lsign-key "* ]]; then
  touch -- "${TEST_ARCH_SANDBOX}/lsigned"
fi
if [[ "\${TEST_PACMAN_KEY_FAIL:-0}" == 1 ]]; then
  case " \$* " in
    *" --add "* | *" --lsign-key "*) exit 1 ;;
  esac
fi
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/pacman-key"

# pacman-conf stub: emulates --repo-list from the --config file when given.
cat >"${TEST_ARCH_BIN}/pacman-conf" <<EOF
#!/usr/bin/env bash
printf 'pacman-conf %s\n' "\$*" >>"$(test_arch_calls_log)"
cfg=''
prev=''
for a in "\$@"; do
  [[ \${prev} == --config ]] && cfg=\${a}
  prev=\${a}
done
if [[ " \$* " == *" --repo-list "* ]]; then
  if [[ -n \${cfg} && -r \${cfg} ]]; then
    grep -E '^\[.+\]' "\${cfg}" | tr -d '[] \t'
  else
    printf '%s\n' \${TEST_REPO_LIST:-core extra multilib}
  fi
fi
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/pacman-conf"

# pacman stub: -Si visibility driven by TEST_SI_EXIT (0/1).
cat >"${TEST_ARCH_BIN}/pacman" <<EOF
#!/usr/bin/env bash
printf 'pacman %s\n' "\$*" >>"$(test_arch_calls_log)"
if [[ " \$* " == *" -Si "* ]]; then
  exit \${TEST_SI_EXIT:-0}
fi
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/pacman"

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-mega.sh"
test_arch_arm_cleanup

# --- fixtures ------------------------------------------------------------

WORK="${TEST_ARCH_SANDBOX}/work"
mkdir -p -- "${WORK}"

write_minimal_conf() {
  cat >"${WORK}/pacman.conf" <<'EOF'
[options]
Color

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
}

reset_calls() { : >"$(test_arch_calls_log)"; rm -f -- "${TEST_ARCH_SANDBOX}/lsigned"; }

run_setup() {
  local conf=$1
  set +e
  # Subshell: arch_mega_setup_vendor_repo dies (exit) on drift, and only
  # a subshell turns that into a capturable status (same pattern as
  # test-arch-pacman-options.sh). File effects persist; shell state need not.
  ( arch_mega_setup_vendor_repo "${conf}" >"${WORK}/setup.out" 2>&1 )
  local status=$?
  set -e
  printf '%d' "${status}" >"${WORK}/setup.status"
}

setup_status() { cat -- "${WORK}/setup.status"; }
assert_called() { grep -q -- "$1" "$(test_arch_calls_log)" || test_arch_die "$2: expected <$1> to be called"; }
assert_not_called() { grep -q -- "$1" "$(test_arch_calls_log)" && test_arch_die "$2: <$1> must not be called"; return 0; }

# --- 1. converged: trusted key plus exact config changes nothing ---------

write_minimal_conf
cat >>"${WORK}/pacman.conf" <<'EOF'

[DEB_Arch_Extra]
SigLevel = Required DatabaseRequired
Server = https://mega.nz/linux/repo/Arch_Extra/$arch
EOF
cp -- "${WORK}/pacman.conf" "${WORK}/converged.conf"
export TEST_GPG_TRUST_MODE=trusted TEST_REPO_LIST='core extra multilib DEB_Arch_Extra'
reset_calls
run_setup "${WORK}/converged.conf"
test_arch_assert_eq 0 "$(setup_status)" 'converged setup exits 0'
assert_not_called 'curl ' 'converged setup fetches nothing'
assert_not_called 'pacman-key --add' 'converged setup adds no key'
assert_not_called 'pacman-key --lsign-key' 'converged setup signs no key'
grep -q 'gpg --homedir .*--no-auto-check-trustdb' "$(test_arch_calls_log)" \
  || test_arch_die 'converged trust probe must list with --no-auto-check-trustdb (never refresh the trustdb)'
cmp -s -- "${WORK}/pacman.conf" "${WORK}/converged.conf" \
  || test_arch_die 'converged setup rewrote a converged config'
[[ ! -e ${WORK}/converged.conf.dotfiles-backup ]] \
  || test_arch_die 'converged setup grew a backup'

# --- 2. add path: missing section appends once at the end, then converges -

write_minimal_conf
cp -- "${WORK}/pacman.conf" "${WORK}/fresh.conf"
export TEST_GPG_TRUST_MODE=untrusted
reset_calls
run_setup "${WORK}/fresh.conf"
test_arch_assert_eq 0 "$(setup_status)" 'fresh setup exits 0'
test_arch_assert_eq 1 "$(grep -cE '^\[DEB_Arch_Extra\][[:space:]]*$' "${WORK}/fresh.conf")" 'section appended exactly once'
test_arch_assert_contains "${WORK}/fresh.conf" 'SigLevel = Required DatabaseRequired' 'both signatures required'
# shellcheck disable=SC2016 # $arch here is the pacman literal the file must carry.
test_arch_assert_contains "${WORK}/fresh.conf" 'Server = https://mega.nz/linux/repo/Arch_Extra/$arch' 'pinned server line present'
if grep -Eq 'TrustAll|DatabaseOptional|SigLevel = Never' "${WORK}/fresh.conf"; then
  test_arch_die 'staged config weakened signature policy'
fi
if grep -q -- '--recv-keys' "$(test_arch_calls_log)"; then
  test_arch_die 'keyserver lookup defeats the pinned source; --recv-keys is forbidden'
fi
assert_called 'pacman-key --add' 'fresh setup adds the verified key file'
assert_called 'pacman-key --lsign-key' 'fresh setup locally signs the key'
[[ -r ${WORK}/fresh.conf.dotfiles-backup ]] \
  || test_arch_die 'first config write keeps a backup'
cmp -s -- "${WORK}/pacman.conf" "${WORK}/fresh.conf.dotfiles-backup" \
  || test_arch_die 'backup is not the original config'
# Comments and official repos survive byte-identical above the appended tail.
head -n "$(wc -l <"${WORK}/pacman.conf")" -- "${WORK}/fresh.conf" | cmp -s -- "${WORK}/pacman.conf" - \
  || test_arch_die 'official repos/comments were not preserved verbatim'
# Vendor-last ordering: official repos resolve before the vendor section.
for repo in core extra multilib; do
  (( $(grep -nE "^\[${repo}\]" "${WORK}/fresh.conf" | cut -d: -f1) < $(grep -nE '^\[DEB_Arch_Extra\]' "${WORK}/fresh.conf" | cut -d: -f1) )) \
    || test_arch_die "vendor section must sort after [${repo}] so it cannot shadow official packages"
done
# Second run converges: no duplicate, backup kept, no network.
export TEST_GPG_TRUST_MODE=trusted
sha_before="$(sha256sum -- "${WORK}/fresh.conf.dotfiles-backup" | cut -d' ' -f1)"
reset_calls
run_setup "${WORK}/fresh.conf"
test_arch_assert_eq 0 "$(setup_status)" 'second setup exits 0'
test_arch_assert_eq 1 "$(grep -cE '^\[DEB_Arch_Extra\][[:space:]]*$' "${WORK}/fresh.conf")" 'second run appends no duplicate'
test_arch_assert_eq "${sha_before}" "$(sha256sum -- "${WORK}/fresh.conf.dotfiles-backup" | cut -d' ' -f1)" 'backup never overwritten'
assert_not_called 'curl ' 'second setup fetches nothing'

# --- 3. fingerprint mismatch dies before any mutation --------------------

write_minimal_conf
cp -- "${WORK}/pacman.conf" "${WORK}/mismatch.conf"
export TEST_GPG_TRUST_MODE=untrusted TEST_GPG_SHOW_MODE=mismatch
reset_calls
run_setup "${WORK}/mismatch.conf"
[[ $(setup_status) != 0 ]] || test_arch_die 'fingerprint mismatch must fail'
grep -q 'arch-mega: vendor key fingerprint mismatch' "${WORK}/setup.out" \
  || test_arch_die 'mismatch error lacks the arch-mega: context prefix'
cmp -s -- "${WORK}/pacman.conf" "${WORK}/mismatch.conf" \
  || test_arch_die 'mismatch run touched the config'
[[ ! -e ${WORK}/mismatch.conf.dotfiles-backup ]] \
  || test_arch_die 'failed run must not leave a backup'
assert_not_called 'pacman-key --add' 'mismatched key must never reach the keyring'
export TEST_GPG_SHOW_MODE=good

# --- 3b. extra bundled primary: scoped listing shows the pinned key, but ---
# --- the whole file holds a second primary: refuse, subkeys stay allowed ---

write_minimal_conf
cp -- "${WORK}/pacman.conf" "${WORK}/extrapub.conf"
export TEST_GPG_TRUST_MODE=untrusted TEST_GPG_SHOW_MODE=extrapub
reset_calls
run_setup "${WORK}/extrapub.conf"
[[ $(setup_status) != 0 ]] || test_arch_die 'bundled extra primary must fail'
grep -q 'arch-mega: vendor key file bundles extra primary keys' "${WORK}/setup.out" \
  || test_arch_die 'extra-primary error lacks the arch-mega: context prefix'
cmp -s -- "${WORK}/pacman.conf" "${WORK}/extrapub.conf" \
  || test_arch_die 'extra-primary run touched the config'
[[ ! -e ${WORK}/extrapub.conf.dotfiles-backup ]] \
  || test_arch_die 'failed run must not leave a backup'
assert_not_called 'pacman-key --add' 'bundled file must never reach the keyring'
export TEST_GPG_SHOW_MODE=good

# --- 4. revoked / expired keys die ----------------------------------------

for mode in revoked expired; do
  write_minimal_conf
  cp -- "${WORK}/pacman.conf" "${WORK}/${mode}.conf"
  export TEST_GPG_TRUST_MODE=untrusted TEST_GPG_SHOW_MODE="${mode}"
  reset_calls
  run_setup "${WORK}/${mode}.conf"
  [[ $(setup_status) != 0 ]] || test_arch_die "${mode} key must fail"
  grep -q 'arch-mega: vendor key is revoked, expired, invalid, or disabled' "${WORK}/setup.out" \
    || test_arch_die "${mode} rejection must come from the validity column, with the arch-mega: prefix"
  cmp -s -- "${WORK}/pacman.conf" "${WORK}/${mode}.conf" \
    || test_arch_die "${mode} run touched the config"
  assert_not_called 'pacman-key --add' "${mode} key must never reach the keyring"
done
export TEST_GPG_SHOW_MODE=good

# --- 5. duplicates repair; wrong / foreign sections still fail -----------

PINNED_SERVER='https://mega.nz/linux/repo/Arch_Extra/$arch'
PINNED_BODY="SigLevel = Required DatabaseRequired
Server = ${PINNED_SERVER}"

# One pinned section plus a second section carrying the given body.
write_dup_conf() {
  write_minimal_conf
  printf '\n[DEB_Arch_Extra]\n%s\n' "${PINNED_BODY}" >>"${WORK}/pacman.conf"
  printf '\n[DEB_Arch_Extra]\n%s\n' "$1" >>"${WORK}/pacman.conf"
}

# pacman registers one database per repository name and refuses a second
# registration of the same name, so a duplicated section breaks every
# transaction on the machine (yay reports it as "Database should be null").
# init is the supported repair path: identical copies collapse to one.
write_minimal_conf
cp -- "${WORK}/pacman.conf" "${WORK}/append-reference.conf"
write_dup_conf "${PINNED_BODY}"
cp -- "${WORK}/pacman.conf" "${WORK}/dup.conf"
export TEST_GPG_TRUST_MODE=trusted TEST_REPO_LIST='core extra multilib DEB_Arch_Extra'
reset_calls
run_setup "${WORK}/dup.conf"
test_arch_assert_eq 0 "$(setup_status)" 'identical duplicate sections repair instead of blocking init'
test_arch_assert_eq 1 "$(grep -cE '^\[DEB_Arch_Extra\][[:space:]]*$' "${WORK}/dup.conf")" 'collapse leaves exactly one section'
grep -q 'collapsed 2 duplicate' "${WORK}/setup.out" \
  || test_arch_die 'collapse must report what it repaired'
assert_not_called 'curl ' 'a config-only repair fetches nothing'
assert_not_called 'pacman-key --add' 'a config-only repair imports no key'
cmp -s -- "${WORK}/pacman.conf" "${WORK}/dup.conf.dotfiles-backup" \
  || test_arch_die 'collapse keeps the duplicated original as the backup'
# The survivor is byte for byte what a fresh append produces: the repair
# converges on one end state, it does not invent a second layout.
reset_calls
run_setup "${WORK}/append-reference.conf"
test_arch_assert_eq 0 "$(setup_status)" 'reference append exits 0'
cmp -s -- "${WORK}/dup.conf" "${WORK}/append-reference.conf" \
  || test_arch_die 'collapsed config differs from a freshly appended one'

# Copies that disagree are a human decision, never ours to pick: they die
# before any trust or config mutation, naming the header lines.
DRIFTED_BODIES=(
  "${PINNED_BODY}
Include = /tmp/evil.conf"
  "SigLevel = Required DatabaseOptional
Server = ${PINNED_SERVER}"
  "SigLevel = Required DatabaseRequired
Server = https://example.com/evil/\$arch"
)
for drift in "${DRIFTED_BODIES[@]}"; do
  write_dup_conf "${drift}"
  cp -- "${WORK}/pacman.conf" "${WORK}/dupdrift.conf"
  export TEST_GPG_TRUST_MODE=untrusted
  reset_calls
  run_setup "${WORK}/dupdrift.conf"
  [[ $(setup_status) != 0 ]] || test_arch_die "duplicate copy carrying <${drift}> must fail, never collapse"
  grep -q 'do not all carry the pinned Server/SigLevel' "${WORK}/setup.out" \
    || test_arch_die "drifted duplicate <${drift}> lacks the arch-mega: drift message"
  grep -qE 'lines [0-9]+ [0-9]+' "${WORK}/setup.out" \
    || test_arch_die 'drift message must name the section lines so the hand edit is a one-liner'
  cmp -s -- "${WORK}/pacman.conf" "${WORK}/dupdrift.conf" \
    || test_arch_die "drifted duplicate <${drift}> run touched the config"
  [[ ! -e ${WORK}/dupdrift.conf.dotfiles-backup ]] \
    || test_arch_die 'failed collapse must not leave a backup'
  assert_not_called 'pacman-key --add' 'disagreeing duplicates must fail before trust mutation'
done
export TEST_GPG_TRUST_MODE=untrusted

write_minimal_conf
cat >>"${WORK}/pacman.conf" <<'EOF'

[DEB_Arch_Extra]
SigLevel = Required DatabaseOptional
Server = https://mega.nz/linux/repo/Arch_Extra/$arch
EOF
cp -- "${WORK}/pacman.conf" "${WORK}/weak.conf"
reset_calls
run_setup "${WORK}/weak.conf"
[[ $(setup_status) != 0 ]] || test_arch_die 'weakened SigLevel must fail, not silently relax'
assert_not_called 'pacman-key --add' 'weak config must fail before trust mutation'

write_minimal_conf
cat >>"${WORK}/pacman.conf" <<'EOF'

[DEB_Arch_Extra]
SigLevel = Required DatabaseRequired
Server = https://example.com/evil/$arch
EOF
cp -- "${WORK}/pacman.conf" "${WORK}/wrong.conf"
reset_calls
run_setup "${WORK}/wrong.conf"
[[ $(setup_status) != 0 ]] || test_arch_die 'wrong Server must fail'
assert_not_called 'pacman-key --add' 'wrong config must fail before trust mutation'

write_minimal_conf
cat >>"${WORK}/pacman.conf" <<'EOF'

[mega]
SigLevel = Required DatabaseRequired
Server = https://mega.nz/linux/repo/Arch_Extra/$arch
EOF
cp -- "${WORK}/pacman.conf" "${WORK}/foreign.conf"
reset_calls
run_setup "${WORK}/foreign.conf"
[[ $(setup_status) != 0 ]] || test_arch_die 'foreign [mega] section must fail'
assert_not_called 'pacman-key --add' 'foreign config must fail before trust mutation'

# --- 6. unsupported architecture dies before network/trust/config ---------

write_minimal_conf
cp -- "${WORK}/pacman.conf" "${WORK}/arch.conf"
export TEST_UNAME_M=aarch64 TEST_GPG_TRUST_MODE=untrusted
reset_calls
run_setup "${WORK}/arch.conf"
[[ $(setup_status) != 0 ]] || test_arch_die 'non-x86_64 must fail: vendor ships x86_64 only'
grep -q 'arch-mega: unsupported architecture' "${WORK}/setup.out" \
  || test_arch_die 'arch error lacks the arch-mega: context prefix'
assert_not_called 'curl ' 'unsupported arch must not fetch'
assert_not_called 'pacman-key' 'unsupported arch must not touch trust'
[[ ! -e ${WORK}/arch.conf.dotfiles-backup ]] \
  || test_arch_die 'unsupported arch must not back up either'
export TEST_UNAME_M=x86_64

# --- 7. verify stays read-only --------------------------------------------

export TEST_GPG_TRUST_MODE=trusted TEST_SI_EXIT=0 TEST_REPO_LIST='core extra multilib DEB_Arch_Extra'
write_minimal_conf
cat >>"${WORK}/pacman.conf" <<'EOF'

[DEB_Arch_Extra]
SigLevel = Required DatabaseRequired
Server = https://mega.nz/linux/repo/Arch_Extra/$arch
EOF
reset_calls
set +e
arch_mega_verify_vendor_repo "${WORK}/pacman.conf" >/dev/null 2>&1
verify_status=$?
set -e
test_arch_assert_eq 0 "${verify_status}" 'verify passes on a converged fixture'
assert_not_called 'curl ' 'verify fetches nothing'
assert_not_called 'pacman-key --add' 'verify imports nothing'
assert_not_called 'pacman-key --lsign-key' 'verify signs nothing'
assert_not_called 'pacman-key --recv-keys' 'verify never hits a keyserver'

write_minimal_conf
reset_calls
set +e
arch_mega_verify_vendor_repo "${WORK}/pacman.conf" >/dev/null 2>&1
verify_status=$?
set -e
((verify_status != 0)) || test_arch_die 'verify must fail on a missing section'
assert_not_called 'curl ' 'failing verify still fetches nothing'

# Unsynced database: repo configured and key present, but pacman sees no
# packages — reported accurately, still without network or mutation.
cat >>"${WORK}/pacman.conf" <<'EOF'

[DEB_Arch_Extra]
SigLevel = Required DatabaseRequired
Server = https://mega.nz/linux/repo/Arch_Extra/$arch
EOF
export TEST_SI_EXIT=1
reset_calls
set +e
arch_mega_verify_vendor_repo "${WORK}/pacman.conf" >/dev/null 2>&1
verify_status=$?
set -e
((verify_status != 0)) || test_arch_die 'verify must fail when the sync database is missing'
assert_not_called 'curl ' 'unsynced verify fetches nothing'
assert_not_called 'pacman-key --add' 'unsynced verify imports nothing'
export TEST_SI_EXIT=0

# --- 8. verify diagnoses an untrusted key without touching trust ---

write_minimal_conf
cat >>"${WORK}/pacman.conf" <<'EOF'

[DEB_Arch_Extra]
SigLevel = Required DatabaseRequired
Server = https://mega.nz/linux/repo/Arch_Extra/$arch
EOF
export TEST_GPG_TRUST_MODE=untrusted TEST_SI_EXIT=0 TEST_REPO_LIST='core extra multilib DEB_Arch_Extra'
reset_calls
set +e
arch_mega_verify_vendor_repo "${WORK}/pacman.conf" >"${WORK}/verify.out" 2>&1
verify_status=$?
set -e
((verify_status != 0)) || test_arch_die 'verify must fail on a present-but-untrusted key'
grep -q 'arch-mega: vendor key present but not locally signed' "${WORK}/verify.out" \
  || test_arch_die 'untrusted diagnostic lacks the distinctive arch-mega: message'
assert_not_called 'pacman-key --add' 'verify signs nothing'
assert_not_called 'pacman-key --lsign-key' 'verify signs nothing'
assert_not_called 'pacman-key --recv-keys' 'verify never hits a keyserver'
assert_not_called 'pacman-key --refresh-keys' 'verify refreshes nothing'
assert_not_called 'gpg --refresh-keys' 'verify refreshes nothing'
grep -q -- '--no-auto-check-trustdb' "$(test_arch_calls_log)" \
  || test_arch_die 'verify trust listing must carry --no-auto-check-trustdb'
assert_not_called 'pacman-key --updatedb' 'verify updates no database'
assert_not_called 'curl ' 'verify fetches nothing'

# --- 8b. verify names a duplicated section instead of calling it drift ---

write_dup_conf "${PINNED_BODY}"
export TEST_GPG_TRUST_MODE=trusted TEST_SI_EXIT=0
reset_calls
set +e
arch_mega_verify_vendor_repo "${WORK}/pacman.conf" >"${WORK}/verify.out" 2>&1
verify_status=$?
set -e
((verify_status != 0)) || test_arch_die 'verify must fail on duplicated sections'
grep -q '2 \[DEB_Arch_Extra\] sections' "${WORK}/verify.out" \
  || test_arch_die 'duplicate diagnostic must count the sections, not report generic drift'
grep -q 'Run ./dot arch-setup' "${WORK}/verify.out" \
  || test_arch_die 'duplicate diagnostic must name the repair'
assert_not_called 'pacman-key --add' 'verify repairs nothing'
assert_not_called 'curl ' 'duplicate verify fetches nothing'
# Leave a converged fixture behind for the key cases below.
write_minimal_conf
printf '\n[DEB_Arch_Extra]\n%s\n' "${PINNED_BODY}" >>"${WORK}/pacman.conf"

# --- 9. verify reports a missing key distinctly ---

export TEST_GPG_TRUST_MODE=absent
reset_calls
set +e
arch_mega_verify_vendor_repo "${WORK}/pacman.conf" >"${WORK}/verify.out" 2>&1
verify_status=$?
set -e
((verify_status != 0)) || test_arch_die 'verify must fail on a missing key'
grep -q 'arch-mega: vendor signing key .* not in the pacman keyring' "${WORK}/verify.out" \
  || test_arch_die 'missing-key diagnostic lacks the arch-mega: message'
assert_not_called 'pacman-key --add' 'missing-key verify imports nothing'
export TEST_GPG_TRUST_MODE=trusted

# --- 10. configured() accepts only the exact effective directives ------

write_conf_body() {
  write_minimal_conf
  printf '\n[DEB_Arch_Extra]\n%s\n' "$1" >>"${WORK}/pacman.conf"
  cp -- "${WORK}/pacman.conf" "${WORK}/matrix.conf"
}
check_conf() {
  local expected=$1 label=$2 status
  set +e
  arch_mega_vendor_repo_configured "${WORK}/matrix.conf" >/dev/null 2>&1
  status=$?
  set -e
  test_arch_assert_eq "${expected}" "${status}" "${label}"
}

GOOD_BODY='SigLevel = Required DatabaseRequired
Server = https://mega.nz/linux/repo/Arch_Extra/$arch'
write_conf_body "${GOOD_BODY}"
check_conf 0 'exact section configures'

# A comment mentioning Never must not falsely reject a healthy config.
write_minimal_conf
cat >>"${WORK}/pacman.conf" <<'EOF'

# Never hand-edit below: managed by arch-mega.
[DEB_Arch_Extra]
SigLevel = Required DatabaseRequired # Never relax this line.
Server = https://mega.nz/linux/repo/Arch_Extra/$arch
EOF
cp -- "${WORK}/pacman.conf" "${WORK}/matrix.conf"
check_conf 0 'comments (even mentioning Never) do not reject'

write_conf_body "${GOOD_BODY}
Include = /tmp/evil.conf"
check_conf 1 'smuggled Include rejects'

write_conf_body "${GOOD_BODY}
Server = https://example.com/evil/\$arch"
check_conf 1 'duplicate evil Server beside the good one rejects'

write_conf_body "${GOOD_BODY}
SigLevel = TrustedOnly"
check_conf 1 'duplicate SigLevel rejects'

write_conf_body 'Server = https://mega.nz/linux/repo/Arch_Extra/$arch
SigLevel = Required DatabaseRequired'
check_conf 0 'directive order is irrelevant'

write_conf_body "${GOOD_BODY}
CacheDir = /tmp/x"
check_conf 1 'unknown directive rejects'

write_conf_body 'SigLevel = Required DatabaseRequired
server = https://mega.nz/linux/repo/Arch_Extra/$arch'
check_conf 1 'lowercase directive name rejects'

write_conf_body "${GOOD_BODY}"
printf '\n[DEB_Arch_Extra]\n%s\n' "${GOOD_BODY}" >>"${WORK}/matrix.conf"
check_conf 1 'duplicated section rejects'

# --- 11. trust-status parser on live-observed gpg 2.4 forms --------------

VENDOR_FRESH='pub:-:4096:1:1A664B787094A482:1641992489:1957352489::-:::scESC::::::23::0:
fpr:::::::::B01C811880480C854C73EC7E1A664B787094A482:
sub:-:4096:1:CC657CA556002348:1641992489:1957352489:::::e::::::23:
fpr:::::::::48D4F37062092DA6664D42BECC657CA556002348:'
TRUSTED_FORM='pub:f:4096:1:1A664B787094A482:1780000000:1956528000:::
fpr:::::::::B01C811880480C854C73EC7E1A664B787094A482:'
EXPIRED_REAL='pub:e:1024:1:C1D0BD353DFC997D:1789009432:1789009433::u:::sc::::::::0:
fpr:::::::::B01C811880480C854C73EC7E1A664B787094A482:'
REVOKED_FORM='pub:r:4096:1:1A664B787094A482:1641992489:1957352489:::
fpr:::::::::B01C811880480C854C73EC7E1A664B787094A482:'
MISMATCH_FORM='pub:-:4096:1:FFFFFFFF:1780000000:1956528000:::
fpr:::::::::AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:'
TWOPUB_FORM='pub:-:4096:1:1A664B787094A482:1780000000:1956528000:::
fpr:::::::::B01C811880480C854C73EC7E1A664B787094A482:
pub:-:2048:1:EEEEEEEE:1780000000:1956528000:::
fpr:::::::::EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE:'
REVLINE_FORM="${TRUSTED_FORM}
rev:-:4096:1:948A482:1780000000::::"
test_arch_assert_eq 'untrusted' "$(arch_mega_key_trust_status "${VENDOR_FRESH}")" 'fresh vendor import parses untrusted'
test_arch_assert_eq 'trusted' "$(arch_mega_key_trust_status "${TRUSTED_FORM}")" 'locally signed key parses trusted'
test_arch_assert_eq 'invalid' "$(arch_mega_key_trust_status "${EXPIRED_REAL}")" 'live-observed expired form parses invalid'
test_arch_assert_eq 'invalid' "$(arch_mega_key_trust_status "${REVOKED_FORM}")" 'revoked validity parses invalid with no rev line needed'
test_arch_assert_eq 'invalid' "$(arch_mega_key_trust_status "${MISMATCH_FORM}")" 'wrong fingerprint parses invalid'
test_arch_assert_eq 'invalid' "$(arch_mega_key_trust_status "${TWOPUB_FORM}")" 'second primary parses invalid'
test_arch_assert_eq 'invalid' "$(arch_mega_key_trust_status "${REVLINE_FORM}")" 'revocation marker parses invalid'

test_arch_assert_no_live_paths 'mega vendor repo seam'
printf 'MEGA vendor repo setup is idempotent, signed, and fail-loud.\n'
