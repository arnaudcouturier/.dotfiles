#!/usr/bin/env bash
# Equibop Arch package regression: exactly one Discord client entry, and it
# is the vendor-tracking git build. Static only: no Arch host, sudo, or
# network needed. Vendor evidence (AUR RPC, fetched once by the author, not
# by this test): equibop-git 3.3.0-2 by creations, source
# https://github.com/Equicord/Equibop (the same upstream the Fedora pinned
# RPM releases from), Depends electron, Provides equibop=3.3.0, Conflicts
# equibop — so installing it replaces the non-git client instead of
# co-installing a second one, and the ~/.config/equibop home plus the CLI
# launch/theme paths stay valid.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# shellcheck source=tests/lib/test-arch-isolation.sh
source "${TEST_DIR}/lib/test-arch-isolation.sh"

BUNDLE="${TEST_ARCH_REPO_ROOT}/packages/arch.bundle"

equibop_die() {
  printf 'test-equibop-git: %s\n' "$*" >&2
  exit 1
}

[[ -f ${BUNDLE} ]] || equibop_die 'packages/arch.bundle missing'

# Exactly one equibop client line: the -git build. A bare `aur "equibop"`
# entry beside it would co-install two conflicting clients.
count="$(grep -c -i 'equibop' "${BUNDLE}")"
((count == 1)) || equibop_die "expected exactly one equibop entry, found ${count}"
grep -Eq '^aur "equibop-git"' "${BUNDLE}" || equibop_die 'arch.bundle must carry aur "equibop-git"'
grep -Eq '^aur "equibop"' "${BUNDLE}" && equibop_die 'stale bare aur "equibop" entry still present'

# No second Discord client beside it.
grep -Eiq '^(aur|repo) "(discord|vesktop|equibop-bin|webcord|armcord)"' "${BUNDLE}" \
  && equibop_die 'a second Discord client entry is present'

# Scope: Fedora keeps its own vendor RPM path; this switch is Arch-only.
grep -Eq '^rpm "equibop"' "${TEST_ARCH_REPO_ROOT}/packages/fedora.bundle" \
  || equibop_die 'fedora.bundle lost its vendor equibop RPM (Arch-only switch must not touch Fedora)'

printf 'equibop: single Arch client aur "equibop-git", Fedora vendor RPM untouched.\n'
