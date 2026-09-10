#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# tests/test-arch-apps-opencode2.sh — the Arch bundle carries OpenCode V2 beta
# as an AUR entry without substituting the stable CLI or renaming products.
#
# Evidence: npm @opencode-ai/cli@beta and @opencode/cli@beta both expose
# bin.opencode2 (opencode2 binary); Arch extra ships stable `opencode`
# (binary opencode, wrong product); AUR opencode-beta Provides opencode2 and
# installs /usr/bin/opencode2. No package is literally named opencode2.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox
test_arch_arm_cleanup

BUNDLE="${TEST_ARCH_REPO_ROOT}/packages/arch.bundle"

[[ -r ${BUNDLE} ]] || test_arch_die 'packages/arch.bundle missing'

# Exactly one opencode-beta entry, filed as an AUR package.
test_arch_assert_eq 1 "$(grep -cE '^aur "opencode-beta"(#| )' "${BUNDLE}")" 'one aur opencode-beta entry'

# The entry's own comment names the opencode2 binary, so a search for
# "opencode2" lands on the why, not just the package name.
test_arch_assert_contains "${BUNDLE}" 'opencode2' 'bundle comment names the opencode2 binary'

# No silent substitution: the stable CLI must not be filed as the answer,
# and no literal opencode2 package name may appear (none exists upstream).
if grep -Eq '^repo "opencode"([[:space:]]|#|$)' "${BUNDLE}"; then
  test_arch_die 'stable repo "opencode" must not stand in for opencode2'
fi
if grep -Eq '^(repo|aur) "opencode2"([[:space:]]|#|$)' "${BUNDLE}"; then
  test_arch_die 'no literal "opencode2" package exists upstream; the entry must stay opencode-beta'
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

test_arch_assert_no_live_paths 'opencode2 bundle entry'
printf 'opencode2 stays an explicit AUR beta entry; equibop-git untouched.\n'
