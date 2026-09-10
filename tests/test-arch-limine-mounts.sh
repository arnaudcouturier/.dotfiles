#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# H3: Limine mount bookkeeping restores read-only mounts, and setup never
# clobbers dot's EXIT trap (sudo-refresher leak). Direct function tests plus
# the real no-config setup path with stubbed mount/findmnt/pacman.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox

# Scripted externals: findmnt mount fields honor TEST_MOUNT_OPTIONS;
# mount and sudo log; pacman install succeeds; no limine.conf exists.
cat >"${TEST_ARCH_BIN}/findmnt" <<EOF
#!/usr/bin/env bash
printf 'findmnt %s\n' "\$*" >>"$(test_arch_calls_log)"
printf '%s\n' "\${TEST_MOUNT_OPTIONS:-rw,relatime}"
EOF
chmod 755 -- "${TEST_ARCH_BIN}/findmnt"
cat >"${TEST_ARCH_BIN}/mount" <<EOF
#!/usr/bin/env bash
printf 'mount %s\n' "\$*" >>"$(test_arch_calls_log)"
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/mount"
cat >"${TEST_ARCH_BIN}/sudo" <<EOF
#!/usr/bin/env bash
printf 'sudo %s\n' "\$*" >>"$(test_arch_calls_log)"
case "\$*" in
  'test -f '*) exit 1 ;;
  'pacman -S '*) exit 0 ;;
  findmnt*) exec "\$@" ;;
  *) exit 0 ;;
esac
EOF
chmod 755 -- "${TEST_ARCH_BIN}/sudo"
for cmd in pacman lsblk efibootmgr; do
  test_arch_stub_command "${cmd}"
done

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-guard.sh"
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-limine.sh"
test_arch_arm_cleanup
# Chain dot's cleanup behind sandbox cleanup: this test asserts setup
# preserves the EXIT trap, so both must be armed to observe it.
# shellcheck disable=SC2064
trap "cleanup_dot; rm -rf -- '${TEST_ARCH_SANDBOX}'" EXIT

# --- Read-only mount widens once; already-writable mounts untouched. ---
export TEST_MOUNT_OPTIONS='ro,relatime'
: >"$(test_arch_calls_log)"
arch_limine_ensure_mount_writable '/boot'
arch_limine_ensure_mount_writable '/boot'
test_arch_assert_eq 1 "$(grep -c 'sudo mount --options remount,rw --target /boot' "$(test_arch_calls_log)")" \
  'widen recorded once despite two calls'
export TEST_MOUNT_OPTIONS='rw,relatime'
: >"$(test_arch_calls_log)"
arch_limine_ensure_mount_writable '/boot-rw'
test_arch_assert_not_called mount 'writable mount never remounted'

# --- Restore narrows every widened mount and clears the list. ---
export TEST_MOUNT_OPTIONS='ro,relatime'
arch_limine_ensure_mount_writable '/boot'
: >"$(test_arch_calls_log)"
arch_limine_restore_mounts
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo mount --options remount,ro --target /boot' \
  'restore narrows the widened mount'
: >"$(test_arch_calls_log)"
arch_limine_restore_mounts
test_arch_assert_not_called mount 'second restore is a silent no-op'

# --- H3: setup's no-config path leaves dot's EXIT trap intact. ---
before_trap="$(trap -p EXIT)"
[[ ${before_trap} == *cleanup_dot* ]] || test_arch_die 'dot EXIT trap not armed before setup'
set +e
arch_limine_setup >/dev/null 2>&1
setup_status=$?
set -e
((setup_status == 0)) || test_arch_die 'no-config setup should skip cleanly'
after_trap="$(trap -p EXIT)"
[[ ${after_trap} == *cleanup_dot* ]] \
  || test_arch_die "H3: limine setup clobbered dot's EXIT trap (sudo refresher leaks); got <${after_trap:-none}>"

# Probing well-known /boot candidates with read-only `test -f` is the
# candidate scan itself (safe); what must never happen here is a write.
if grep -E -q -- 'sudo (install|cp|mv|tee|chmod)|mount --options|efibootmgr --create' "$(test_arch_calls_log)"; then
  test_arch_die "no-config setup attempted a write: $(grep -E -- 'sudo (install|cp|mv|tee|chmod)|mount --options|efibootmgr --create' "$(test_arch_calls_log)" | head -n 3)"
fi
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo test -f /boot/limine/limine.conf' 'candidate scan ran'
printf 'Limine mount bookkeeping restores; the EXIT trap survives setup.\n'
