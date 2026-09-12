#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# Every arch_*_verify function completes on an unequipped Fedora host
# without mutating anything: no sudo beyond `-n` probes, no enables,
# installs, writes, or account changes. All externals answer from stubs.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox

# Fail-closed sudo: any privileged mutation attempt dies loudly.
test_arch_stub_command sudo

# Deterministic read-only fixtures for every external a verify can query.
cat >"${TEST_ARCH_BIN}/findmnt" <<EOF
#!/usr/bin/env bash
printf 'findmnt %s\n' "\$*" >>"$(test_arch_calls_log)"
printf '%s\n' "\${TEST_FINDMNT_FSTYPE:-ext4}"
EOF
chmod 755 -- "${TEST_ARCH_BIN}/findmnt"
cat >"${TEST_ARCH_BIN}/systemctl" <<EOF
#!/usr/bin/env bash
printf 'systemctl %s\n' "\$*" >>"$(test_arch_calls_log)"
exit 1
EOF
chmod 755 -- "${TEST_ARCH_BIN}/systemctl"
for cmd in pacman pacman-conf swapon sysctl lsblk efibootmgr id getent Hyprland lspci; do
  test_arch_stub_command "${cmd}"
done
# findmnt-output override for the btrfs pass is env-driven; the rest stay mute.

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
for module in arch-guard arch-system arch-gpu arch-gaming arch-snapshots arch-greeter arch-limine; do
  # shellcheck source=/dev/null
  source "${TEST_ARCH_REPO_ROOT}/lib/${module}.sh"
done
test_arch_arm_cleanup

export WORKSTATION_GPU=none

run_verify() {
  local label=$1
  shift
  set +e
  "$@" >/dev/null 2>&1
  local status=$?
  set -e
  ((status == 0 || status == 1)) \
    || test_arch_die "${label} exited ${status} (0/1 only; 99/127 means a stub leaked or crashed)"
  printf '%s -> %d\n' "${label}" "${status}" >>"${TEST_ARCH_SANDBOX}/verify-status.txt"
}

: >"${TEST_ARCH_SANDBOX}/verify-status.txt"
export TEST_FINDMNT_FSTYPE=ext4
run_verify system-ext4 arch_system_verify
run_verify gpu arch_gpu_verify
run_verify gaming arch_gaming_verify
run_verify snapshots-ext4 arch_snapshots_verify
run_verify greeter arch_greeter_verify
run_verify limine arch_limine_verify
export TEST_FINDMNT_FSTYPE=btrfs
run_verify snapshots-btrfs arch_snapshots_verify

# --- No mutation, ever: denylist over every logged call. ---
denied='pacman -S|systemctl enable|systemctl start|systemctl disable|systemctl daemon| install | cp | mv | tee|useradd|usermod| mount |mkinitcpio|yay -S|sysctl --load|efibootmgr --create|chmod /etc'
if grep -E -q -- "${denied}" "$(test_arch_calls_log)"; then
  test_arch_die "a verify function reached a mutating call: $(grep -E -- "${denied}" "$(test_arch_calls_log)" | head -n 3)"
fi

# --- sudo appears only as `-n` read probes, never as elevation. ---
if grep -q '^sudo ' "$(test_arch_calls_log)"; then
  grep '^sudo ' "$(test_arch_calls_log)" | grep -vqE '^sudo -n (true|snapper)' \
    && test_arch_die "a verify function elevated beyond a read probe: $(grep '^sudo ' "$(test_arch_calls_log)" | head -n 3)"
fi

test_arch_assert_no_live_paths 'verify sweep'
printf 'All verify functions complete without mutation:\n'
cat -- "${TEST_ARCH_SANDBOX}/verify-status.txt"
