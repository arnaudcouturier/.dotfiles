#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# arch_system_setup_pacman_options with the accepted internal fixture seam:
# an optional config-path parameter defaulting to /etc/pacman.conf (no
# distro env override — gating and elevation stay unconditional). Probes a
# temp config first: if the implementation ignores the argument, the probe
# dies safely on a missing /etc/pacman.conf and the test skips pending.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

# Probing is only safe when no live pacman.conf exists to be mis-edited.
[[ ! -e /etc/pacman.conf ]] || { printf 'SEAM PENDING: live /etc/pacman.conf present; probe unsafe\n'; exit 3; }

test_arch_make_sandbox

# Scripted pacman-conf: consulted only for the live path, never for
# fixtures. Sudo passes through onto temp paths only.
cat >"${TEST_ARCH_BIN}/pacman-conf" <<EOF
#!/usr/bin/env bash
printf 'pacman-conf %s\n' "\$*" >>"$(test_arch_calls_log)"
if [[ \$1 == --repo-list ]]; then
  printf 'multilib\n'
  exit 0
fi
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/pacman-conf"
test_arch_stub_passthrough_sudo

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-system.sh"
test_arch_arm_cleanup

WORK="${TEST_ARCH_SANDBOX}/pacman with spaces"
mkdir -p -- "${WORK}"
write_fixture() {
  cat >"${WORK}/pacman.conf" <<'EOF'
[options]
#Color
#VerbosePkgLists
#ParallelDownloads = 5

#[multilib]
#Include = /etc/pacman.d/mirrorlist

[core]
Include = /etc/pacman.d/mirrorlist
EOF
}
write_fixture

# --- Seam probe: does the implementation honor a config argument? ---
set +e
( arch_system_setup_pacman_options "${WORK}/pacman.conf" >/dev/null 2>&1 )
probe_status=$?
set -e
if ! grep -q '^\[multilib\]$' "${WORK}/pacman.conf"; then
  printf 'SEAM PENDING: arch_system_setup_pacman_options ignores its config argument (optional-path seam not yet implemented)\n'
  exit 3
fi
((probe_status == 0)) || test_arch_die 'seam honored the path but failed to apply'

# --- Idempotent: the second run changes nothing. ---
cp -- "${WORK}/pacman.conf" "${WORK}/after-first.conf"
arch_system_setup_pacman_options "${WORK}/pacman.conf" >/dev/null
cmp -s -- "${WORK}/after-first.conf" "${WORK}/pacman.conf" \
  || test_arch_die 'second pacman run was not byte-identical'

# --- Options enabled exactly once; unrelated sections untouched. ---
test_arch_assert_eq 1 "$(grep -c '^Color$' "${WORK}/pacman.conf")" 'Color enabled once'
test_arch_assert_eq 1 "$(grep -c '^ParallelDownloads' "${WORK}/pacman.conf")" 'ParallelDownloads enabled once'
test_arch_assert_contains "${WORK}/pacman.conf" '[multilib]' 'multilib enabled'
test_arch_assert_contains "${WORK}/pacman.conf" '[core]' 'unrelated section preserved'

# --- A config without the standard commented multilib section is refused. ---
printf '[options]\n#Color\n' >"${WORK}/bare.conf"
set +e
( arch_system_setup_pacman_options "${WORK}/bare.conf" >/dev/null 2>&1 )
bare_status=$?
set -e
((bare_status != 0)) || test_arch_die 'non-standard pacman.conf was rewritten'

# --- A converged config triggers no edits at all. ---
cat >"${WORK}/converged.conf" <<'EOF'
[options]
Color
VerbosePkgLists
ParallelDownloads = 5

[multilib]
Include = /etc/pacman.d/mirrorlist

[core]
Include = /etc/pacman.d/mirrorlist
EOF
: >"$(test_arch_calls_log)"
arch_system_setup_pacman_options "${WORK}/converged.conf" >/dev/null
if grep -q 'sudo ' "$(test_arch_calls_log)"; then
  test_arch_die 'converged config was re-edited'
fi
[[ ! -e ${WORK}/converged.conf.dotfiles-backup ]] \
  || test_arch_die 'converged config grew a backup'

# --- First write keeps a backup; later runs never overwrite it. ---
test_arch_assert_contains "${WORK}/pacman.conf.dotfiles-backup" '#[multilib]' 'backup keeps the original' 

test_arch_assert_no_live_paths 'pacman options'
printf 'pacman.conf tuning is idempotent and refuses unknown layouts.\n'
