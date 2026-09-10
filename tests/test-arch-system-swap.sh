#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# M1: swap-policy activation must restart (not merely start) the zram swap
# unit, or a re-run after a template change never activates the new policy
# without a reboot. Sequencing asserted through logging sudo (no execution):
# both templates deploy, daemon reloads, the unit restarts, sysctl loads.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox

# Logging sudo: records the activation sequence without executing anything.
# Deploy reads hit the real templates (read-only) and miss live /etc.
cat >"${TEST_ARCH_BIN}/sudo" <<EOF
#!/usr/bin/env bash
printf 'sudo %s\n' "\$*" >>"$(test_arch_calls_log)"
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/sudo"

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-guard.sh"
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-system.sh"
test_arch_arm_cleanup

arch_system_setup_swap_policy >/dev/null
LOG="$(test_arch_calls_log)"

# Both policies deploy before anything activates.
test_arch_assert_contains "${LOG}" 'sudo install --mode=0644 --' 'templates deploy through sudo'
test_arch_assert_contains "${LOG}" 'zram-generator.conf' 'zram policy deployed'
test_arch_assert_contains "${LOG}" '99-arch-zram.conf' 'sysctl policy deployed'

# Ordered activation: reload, then (re)start swap, then sysctl.
reload_line="$(grep -n 'daemon-reload' "${LOG}" | head -n1 | cut -d: -f1)"
swap_line="$(grep -nE 'systemctl (restart|start|stop) dev-zram0.swap' "${LOG}" | head -n1 | cut -d: -f1)"
sysctl_line="$(grep -n 'sysctl --load' "${LOG}" | head -n1 | cut -d: -f1)"
[[ -n ${reload_line} && -n ${swap_line} && -n ${sysctl_line} ]] \
  || test_arch_die 'M1: activation sequence incomplete (reload/start/sysctl)'
((reload_line < swap_line && swap_line < sysctl_line)) \
  || test_arch_die 'M1: activation out of order (reload, then swap, then sysctl)'

# The repair path: restart (or stop/start), never a bare start that
# no-ops when the unit is already active.
if grep -Eq -- 'systemctl restart dev-zram0.swap' "${LOG}"; then
  printf 'swap unit restarts on re-run.\n'
elif grep -Eq -- 'systemctl stop dev-zram0.swap' "${LOG}"; then
  printf 'swap unit stop/starts on re-run.\n'
else
  test_arch_die 'M1: swap activation is a bare start; re-running after a template change never applies it without a reboot'
fi

# Isolation basis here is execution, not paths: sudo is a non-executing
# logger, so these live /etc targets are named but never touched (deploy
# reads hit real templates; existence checks miss live /etc harmlessly).
# What this test proves is the exact call shape a real run would execute.
[[ ${HOME} == "${TEST_ARCH_SANDBOX}"/* ]] \
  || test_arch_die 'swap policy: HOME escaped the sandbox'
printf 'Swap policy deploys both templates and reactivates the unit.\n'
