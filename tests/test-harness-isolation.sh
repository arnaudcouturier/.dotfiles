#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# Self-test for the isolation harness itself: sandboxing, stub logging,
# and the live-path guard. Must stay green; everything else builds on it.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox

# HOME is sandboxed.
test_arch_assert_eq "${TEST_ARCH_HOME}" "${HOME}" 'sandbox HOME is exported'
[[ ${HOME} != "${TEST_ARCH_LIVE_HOME}" ]] \
  || test_arch_die 'HOME still points at the live home'

# Stubs log their calls and fail closed (exit 99) by default.
test_arch_stub_command sudo
set +e
TEST_ARCH_STUB_EXIT=99 sudo -- anything at all
sudo_status=$?
set -e
test_arch_assert_eq 99 "${sudo_status}" 'default stub exits 99'
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo -- anything at all' 'stub logged its arguments'
test_arch_assert_not_called pacman 'pacman stub untouched'

# Output stubs print canned output and exit 0, still logging the call.
printf 'intel\n' >"${TEST_ARCH_SANDBOX}/vendors.txt"
test_arch_stub_command lspci
test_arch_stub_output lspci "${TEST_ARCH_SANDBOX}/vendors.txt"
vendors="$(lspci -n)"
test_arch_assert_eq 'intel' "${vendors}" 'output stub prints its fixture'
test_arch_assert_contains "$(test_arch_calls_log)" 'lspci -n' 'output stub logged its call'

# The live-path guard passes for a sandbox-only run.
test_arch_assert_no_live_paths 'sandbox-only run'

printf 'harness isolation holds: HOME=%s\n' "${HOME}"
