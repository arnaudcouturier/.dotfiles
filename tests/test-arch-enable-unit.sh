#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# arch_enable_system_unit (lib/arch-guard.sh): absent units skip when
# optional and die when required; present units go through sudo systemctl.
# systemctl answers from a fixture, so no live systemd state is involved.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-guard.sh"

test_arch_make_sandbox

# Fixture: only present.service is known to systemd.
cat >"${TEST_ARCH_BIN}/systemctl-units.sh" <<EOF
#!/usr/bin/env bash
printf 'systemctl %s\n' "\$*" >>"$(test_arch_calls_log)"
if [[ \$1 == cat ]]; then
  [[ \$3 == present.service ]] && exit 0
  exit 1
fi
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/systemctl-units.sh"
cp -- "${TEST_ARCH_BIN}/systemctl-units.sh" "${TEST_ARCH_BIN}/systemctl"

# Logging sudo: records elevation without executing anything live.
cat >"${TEST_ARCH_BIN}/sudo" <<EOF
#!/usr/bin/env bash
printf 'sudo %s\n' "\$*" >>"$(test_arch_calls_log)"
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/sudo"

# Absent optional unit: skip with exit 0, no elevation.
arch_enable_system_unit 'absent-timer.service' optional >/dev/null
test_arch_assert_not_called sudo 'absent optional unit never elevates'

# Absent required unit: die with a repair hint.
set +e
hint="$(arch_enable_system_unit 'absent-core.service' 2>&1)"
hint_status=$?
set -e
((hint_status != 0)) || test_arch_die 'absent required unit was enabled silently'
printf '%s\n' "${hint}" >"${TEST_ARCH_SANDBOX}/hint.txt"
test_arch_assert_contains "${TEST_ARCH_SANDBOX}/hint.txt" 'absent-core.service' 'failure names the unit'

# Present unit: enable through sudo systemctl, exactly once.
arch_enable_system_unit 'present.service' >/dev/null
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo systemctl enable --now -- present.service' \
  'present unit enabled through sudo'

test_arch_assert_no_live_paths 'unit enable'
printf 'Unit enables skip absent optionals and route through sudo.\n'
