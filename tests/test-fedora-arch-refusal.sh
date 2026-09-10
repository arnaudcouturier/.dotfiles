#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# Fedora refuses Arch-specific commands before any elevation, network, or
# mutation, and the Fedora bundle stays free of Arch-only verbs. Runs
# against the existing ./dot on this Fedora host; read-only paths only.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox

# Closed stubs first in PATH: if ./dot reaches for elevation, package
# managers, or the network on a refusal path, the call is logged and dies.
for cmd in sudo pacman dnf yay curl stow flatpak rpm; do
  test_arch_stub_command "${cmd}"
done

DOT="${TEST_ARCH_REPO_ROOT}/dot"

# The AUR verb is Arch-only: Fedora must refuse it, naming the Fedora
# bundle as the place for a verified source instead.
set +e
refusal_output="$("${DOT}" package add some-test-package --aur 2>&1)"
refusal_status=$?
set -e
((refusal_status != 0)) || test_arch_die 'aur verb accepted on Fedora'
printf '%s\n' "${refusal_output}" >"${TEST_ARCH_SANDBOX}/refusal.txt"
test_arch_assert_contains "${TEST_ARCH_SANDBOX}/refusal.txt" 'Arch-only' 'refusal names the Arch-only verb'

# Refusal happened before elevation, package managers, and the network.
for cmd in sudo pacman dnf yay curl; do
  test_arch_assert_not_called "${cmd}" "refusal path never reaches ${cmd}"
done

# Read-only listing still works and serves the Fedora bundle.
bundle_list="$("${DOT}" package list)"
printf '%s\n' "${bundle_list}" >"${TEST_ARCH_SANDBOX}/bundle.txt"
test_arch_assert_contains "${TEST_ARCH_SANDBOX}/bundle.txt" 'repo "fish"' 'Fedora bundle lists fish'

# Fedora unchanged: no Arch-only verb may appear in the Fedora bundle.
if grep -Eq '^(aur)[[:space:]]' "${TEST_ARCH_REPO_ROOT}/packages/fedora.bundle"; then
  test_arch_die 'packages/fedora.bundle contains an Arch-only verb'
fi

test_arch_assert_no_live_paths 'fedora refusal probes'
printf 'Fedora refuses Arch-only verbs before any elevation or network.\n'
