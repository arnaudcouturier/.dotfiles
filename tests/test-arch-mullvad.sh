#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# Mullvad VPN daemon management: the package gate decides, never the unit.
# Selected (mullvad-vpn installed) + missing unit is a broken install and
# fails loudly; deselected is a silent noop. Verify reports missing,
# disabled, and inactive as distinct diagnostics. Setup proves the exact
# `systemctl enable --now` command through logging sudo (nothing executes);
# core tailscale/docker behavior is pinned unchanged.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox

# Logging sudo: records enable commands without executing anything.
cat >"${TEST_ARCH_BIN}/sudo" <<EOF
#!/usr/bin/env bash
printf 'sudo %s\n' "\$*" >>"$(test_arch_calls_log)"
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/sudo"

# pacman stub: only the Mullvad query is modeled (present iff
# TEST_MULLVAD_PKG=1); everything else is absent.
cat >"${TEST_ARCH_BIN}/pacman" <<EOF
#!/usr/bin/env bash
printf 'pacman %s\n' "\$*" >>"$(test_arch_calls_log)"
if [[ "\$1" == -Q && "\$2" == mullvad-vpn ]]; then
  [[ "\${TEST_MULLVAD_PKG:-0}" == 1 ]] && exit 0 || exit 1
fi
exit 1
EOF
chmod 755 -- "${TEST_ARCH_BIN}/pacman"

# systemctl stub: unit existence, enabled, and active each driven by env;
# enable --now logs and succeeds (idempotent by systemd contract).
cat >"${TEST_ARCH_BIN}/systemctl" <<EOF
#!/usr/bin/env bash
printf 'systemctl %s\n' "\$*" >>"$(test_arch_calls_log)"
case "\$1" in
  cat) [[ "\${TEST_UNIT_PRESENT:-0}" == 1 ]] && exit 0 || exit 1 ;;
  is-enabled) [[ "\${TEST_ENABLED:-0}" == 1 ]] && exit 0 || exit 1 ;;
  is-active) [[ "\${TEST_ACTIVE:-0}" == 1 ]] && exit 0 || exit 1 ;;
  enable) exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod 755 -- "${TEST_ARCH_BIN}/systemctl"

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-guard.sh"
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-system.sh"
test_arch_arm_cleanup

SYSTEM_LIB="${TEST_ARCH_REPO_ROOT}/lib/arch-system.sh"
WORK="${TEST_ARCH_SANDBOX}/work"
mkdir -p -- "${WORK}"
reset_calls() { : >"$(test_arch_calls_log)"; }

# --- Wiring (static, narrow): package gate, required enable, core intact. ---
grep -Fq 'pacman -Q mullvad-vpn' "${SYSTEM_LIB}" \
  || test_arch_die 'mullvad management must gate on package presence'
grep -Fq 'arch_enable_system_unit mullvad-daemon.service' "${SYSTEM_LIB}" \
  || test_arch_die 'mullvad enable missing'
if grep -Eq 'arch_enable_system_unit mullvad-daemon.service +optional' "${SYSTEM_LIB}"; then
  test_arch_die 'mullvad enable must be required, not optional (missing unit with installed package is a broken install)'
fi
grep -Fq 'for service in tailscaled.service docker.service; do' "${SYSTEM_LIB}" \
  || test_arch_die 'core tailscale/docker opportunistic loop changed'
grep -Fq 'arch_system_setup_mullvad' "${SYSTEM_LIB}" \
  || test_arch_die 'setup helper must be wired into the services step'
# Service provisioning stays in lib: no dot surface, no bundle churn.
if grep -q 'mullvad' "${TEST_ARCH_REPO_ROOT}/dot"; then
  test_arch_die 'mullvad wiring stays in lib/arch-system.sh (no dot changes)'
fi
test_arch_assert_eq 1 "$(grep -c '^repo "mullvad-vpn"' "${TEST_ARCH_REPO_ROOT}/packages/arch.bundle")" \
  'bundle keeps exactly one mullvad-vpn entry (no package additions)'

# --- Positive: installed + present enables with the exact command. ---
export TEST_MULLVAD_PKG=1 TEST_UNIT_PRESENT=1
reset_calls
arch_system_setup_mullvad >/dev/null
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo systemctl enable --now -- mullvad-daemon.service' \
  'setup must run the exact vendor enable command'

# --- Idempotent: a healthy re-run re-enables cleanly. ---
arch_system_setup_mullvad >/dev/null
test_arch_assert_eq 2 "$(grep -c 'sudo systemctl enable --now -- mullvad-daemon.service' "$(test_arch_calls_log)")" \
  're-run must repeat the idempotent enable without failing'

# --- Negative: installed + missing unit is a broken install, fails loud. ---
export TEST_UNIT_PRESENT=0
reset_calls
set +e
( arch_system_setup_mullvad >"${WORK}/setup.out" 2>&1 )
setup_status=$?
set -e
((setup_status != 0)) || test_arch_die 'missing unit with installed package must fail'
test_arch_assert_contains "${WORK}/setup.out" 'mullvad-daemon.service' \
  'broken-install error must name the unit'
if grep -q 'enable --now' "$(test_arch_calls_log)"; then
  test_arch_die 'broken install must fail before attempting enable'
fi

# --- Silent noop: deselected package touches nothing and says nothing. ---
export TEST_MULLVAD_PKG=0 TEST_UNIT_PRESENT=0
reset_calls
mullvad_out="$(arch_system_setup_mullvad 2>&1)"
[[ -z ${mullvad_out} ]] || test_arch_die "deselected package must stay silent, got: ${mullvad_out}"
test_arch_assert_not_called sudo 'deselected package never elevates'

# --- Verify: installed + missing unit reports distinctly. ---
export TEST_MULLVAD_PKG=1 TEST_UNIT_PRESENT=0
arch_system_verify >"${WORK}/verify-missing.out" 2>&1 || true
test_arch_assert_contains "${WORK}/verify-missing.out" 'mullvad-daemon.service is missing' \
  'verify must report a missing unit distinctly'

# --- Verify: installed + disabled reports distinctly. ---
export TEST_UNIT_PRESENT=1 TEST_ENABLED=0 TEST_ACTIVE=1
arch_system_verify >"${WORK}/verify-disabled.out" 2>&1 || true
test_arch_assert_contains "${WORK}/verify-disabled.out" 'not enabled' \
  'verify must report a disabled daemon distinctly'
if grep -q 'not active' "${WORK}/verify-disabled.out"; then
  test_arch_die 'disabled-only drift must not also report inactive'
fi

# --- Verify: installed + inactive reports distinctly. ---
export TEST_ENABLED=1 TEST_ACTIVE=0
arch_system_verify >"${WORK}/verify-inactive.out" 2>&1 || true
test_arch_assert_contains "${WORK}/verify-inactive.out" 'not active' \
  'verify must report an inactive daemon distinctly'
if grep -q 'not enabled' "${WORK}/verify-inactive.out"; then
  test_arch_die 'inactive-only drift must not also report disabled'
fi

# --- Verify: healthy reports nothing; deselected reports nothing. ---
export TEST_ENABLED=1 TEST_ACTIVE=1
arch_system_verify >"${WORK}/verify-healthy.out" 2>&1 || true
if grep -qi 'mullvad' "${WORK}/verify-healthy.out"; then
  test_arch_die 'healthy daemon must produce no mullvad diagnostics'
fi
export TEST_MULLVAD_PKG=0
arch_system_verify >"${WORK}/verify-absent.out" 2>&1 || true
if grep -qi 'mullvad' "${WORK}/verify-absent.out"; then
  test_arch_die 'deselected package must produce no mullvad diagnostics'
fi

test_arch_assert_no_live_paths 'mullvad daemon management'
printf 'Mullvad daemon follows the package: required when selected, silent when deselected.\n'
