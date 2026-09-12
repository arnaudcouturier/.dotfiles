#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# tests/test-arch-apps-opencode2.sh — the Arch bundle carries OpenCode as an
# npm-scripts entry (scripts-enabled install) without substituting the wrong
# product or renaming packages.
#
# Evidence (npm registry, Sep 2026): @opencode/cli@beta is 0.0.0-beta-19507
# (bin opencode + opencode2, both the real binary) and @opencode/cli@latest
# is 2.0.0 (bin opencode real after postinstall, opencode2 a shim saying
# "opencode2 is now just opencode"); @opencode-ai/cli@beta is stale at
# 0.0.0-beta-19271. Same anomalyco/opencode repo backs both scopes, so the
# live scope is @opencode/cli. Arch extra ships stable v1 `opencode`
# (binary opencode, wrong product); AUR opencode-beta Provides
# opencode/opencode2 but the dotfiles use the npm route, so it must not
# appear. No package is literally named opencode2.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox
test_arch_arm_cleanup

BUNDLE="${TEST_ARCH_REPO_ROOT}/packages/arch.bundle"

[[ -r ${BUNDLE} ]] || test_arch_die 'packages/arch.bundle missing'

# Exactly one OpenCode entry, filed as npm-scripts (postinstall fetches the
# platform binary; plain npm with --ignore-scripts leaves a stub that dies
# with "postinstall script was not run").
test_arch_assert_eq 1 "$(grep -cE '^npm-scripts "@opencode/cli"(#| )' "${BUNDLE}")" 'one npm-scripts @opencode/cli entry'

# The entry's own comment names the opencode binary, so a search for
# "opencode" lands on the why, not just the package name.
test_arch_assert_contains "${BUNDLE}" 'binary opencode' 'bundle comment names the opencode binary'

# No silent substitution: the stable v1 CLI must not be filed as the answer,
# the AUR beta route must stay out, and no literal opencode2 package name may
# appear (none exists upstream).
if grep -Eq '^repo "opencode"([[:space:]]|#|$)' "${BUNDLE}"; then
  test_arch_die 'stable repo "opencode" must not stand in for OpenCode v2'
fi
if grep -Eq '^aur "opencode-beta"([[:space:]]|#|$)' "${BUNDLE}"; then
  test_arch_die 'opencode-beta must not reappear: OpenCode installs via npm-scripts'
fi
if grep -Eq '^(repo|aur) "opencode2"([[:space:]]|#|$)' "${BUNDLE}"; then
  test_arch_die 'no literal "opencode2" package exists upstream'
fi
if grep -Eq '^npm "@opencode/cli' "${BUNDLE}"; then
  test_arch_die 'plain npm "@opencode/cli" leaves the postinstall stub; the entry must stay npm-scripts'
fi

# The nvim-repair handover is preserved: exactly one Equibop client entry,
# and it stays the git build (provides/conflicts equibop).
test_arch_assert_eq 1 "$(grep -cE '^aur "equibop-git"(#| )' "${BUNDLE}")" 'equibop-git entry preserved'
if grep -Eq '^aur "equibop"([[:space:]]|#|$)' "${BUNDLE}"; then
  test_arch_die 'stale aur "equibop" must not reappear beside equibop-git'
fi

# Every bundle line still parses under Arch verbs (repo/aur/appimage, plus
# npm/npm-scripts for JS-only tools the repos and AUR do not carry).
while IFS= read -r line || [[ -n ${line} ]]; do
  bare="${line%%#*}"
  [[ -n ${bare//[[:space:]]/} ]] || continue
  verb="${bare%%[[:space:]]*}"
  case "${verb}" in
    repo | aur | appimage | npm | npm-scripts) ;;
    *) test_arch_die "non-Arch verb in arch.bundle: ${line}" ;;
  esac
done <"${BUNDLE}"

test_arch_assert_no_live_paths 'opencode bundle entry'
printf 'opencode stays an explicit npm-scripts entry; equibop-git untouched.\n'
