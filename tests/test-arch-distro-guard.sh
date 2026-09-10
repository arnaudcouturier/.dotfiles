#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# require_arch_system (lib/arch-guard.sh) refuses non-Arch machines before
# any sudo, network, or mutation. Uses the real detect_distro/die/log
# helpers from ./dot (sourced with `help` so main only prints usage).
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
for cmd in sudo pacman curl efibootmgr mount systemctl dnf; do
  test_arch_stub_command "${cmd}"
done

# This Fedora host is refused: non-zero, names Arch, changes nothing.
set +e
refusal="$(require_arch_system 2>&1)"
refusal_status=$?
set -e
((refusal_status != 0)) || test_arch_die 'require_arch_system passed on Fedora'
printf '%s\n' "${refusal}" >"${TEST_ARCH_SANDBOX}/refusal.txt"
test_arch_assert_contains "${TEST_ARCH_SANDBOX}/refusal.txt" 'Arch-only' 'refusal names the Arch-only gate'
test_arch_assert_contains "${TEST_ARCH_SANDBOX}/refusal.txt" 'Nothing was changed' 'refusal promises no mutation'

# The gate itself never elevates, installs, or reaches the network.
for cmd in sudo pacman curl efibootmgr mount systemctl dnf; do
  test_arch_assert_not_called "${cmd}" "gate never reaches ${cmd}"
done

# An Arch distro passes the gate (detect_distro honors a preset DISTRO).
DISTRO=arch require_arch_system
test_arch_assert_not_called sudo 'passing the gate still calls nothing'

test_arch_assert_no_live_paths 'distro gate probes'
printf 'Arch gate refuses Fedora before any elevation or mutation.\n'
