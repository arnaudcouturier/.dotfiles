#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# Decided install mechanism: the overlay deploys via
# `stow -R --no-folding` into $HOME for the stowed set, while the two
# compositor-owned user files (.config/caelestia/hypr-user.lua,
# hypr-vars.lua) are NEVER stowed: raw stow carries the same --ignore the
# production paths use, and the desktop module deploys them as real files.
# Proves source immutability (home-arch/ checksums identical), idempotent
# re-stow, sandbox-only links, user files untouched by stow, and a narrow
# live-home snapshot that must not move.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

command -v stow >/dev/null 2>&1 || { printf 'SEAM PENDING: GNU stow not installed\n'; exit 3; }

test_arch_make_sandbox

OVERLAY="${TEST_ARCH_REPO_ROOT}/home-arch"
[[ -d ${OVERLAY} ]] || { printf 'SEAM PENDING: home-arch/ overlay missing\n'; exit 3; }

# Narrow live-home snapshot: the managed paths stow would own on Arch.
LIVE_SNAPSHOT="${TEST_ARCH_SANDBOX}/live-before.txt"
: >"${LIVE_SNAPSHOT}"
for rel in .config/ghostty/config \
  .config/gtk-3.0/settings.ini .config/gtk-4.0/settings.ini \
  .config/environment.d/10-desktop-theme.conf .local/bin/hypr-keybinds \
  .config/caelestia/hypr-vars.lua .config/caelestia/hypr-user.lua; do
  if [[ -e ${TEST_ARCH_LIVE_HOME}/${rel} || -L ${TEST_ARCH_LIVE_HOME}/${rel} ]]; then
    stat -c '%Y %n' "${TEST_ARCH_LIVE_HOME}/${rel}" >>"${LIVE_SNAPSHOT}"
    readlink "${TEST_ARCH_LIVE_HOME}/${rel}" >>"${LIVE_SNAPSHOT}" 2>/dev/null || true
  else
    printf 'absent %s\n' "${rel}" >>"${LIVE_SNAPSHOT}"
  fi
done

# Source immutability baseline (content checksums, sorted).
find "${OVERLAY}" -type f -exec sha256sum -- {} + | sort -k2 >"${TEST_ARCH_SANDBOX}/source-before.txt"

# The decided mechanism, twice: install then repair-path re-run. The
# --ignore literal mirrors production (dot's stow_arch_overlay and
# arch_desktop_install_overlay): compositor-owned user files are deployed
# as real files by the desktop module, never stowed. Keep in sync.
STOW_IGNORE='(^|/)\.config/caelestia/hypr-(user|vars)\.lua$'
stow -R --no-folding --ignore="${STOW_IGNORE}" -d "${TEST_ARCH_REPO_ROOT}" -t "${TEST_ARCH_HOME}" home-arch
find "${TEST_ARCH_HOME}" -mindepth 1 | sort >"${TEST_ARCH_SANDBOX}/deployed-first.txt"
stow -R --no-folding --ignore="${STOW_IGNORE}" -d "${TEST_ARCH_REPO_ROOT}" -t "${TEST_ARCH_HOME}" home-arch
find "${TEST_ARCH_HOME}" -mindepth 1 | sort >"${TEST_ARCH_SANDBOX}/deployed-second.txt"

# Idempotent: the second run changes nothing.
cmp -s -- "${TEST_ARCH_SANDBOX}/deployed-first.txt" "${TEST_ARCH_SANDBOX}/deployed-second.txt" \
  || test_arch_die 'second stow run changed the deployed tree'

# Source immutability: stow never writes its source.
find "${OVERLAY}" -type f -exec sha256sum -- {} + | sort -k2 >"${TEST_ARCH_SANDBOX}/source-after.txt"
cmp -s -- "${TEST_ARCH_SANDBOX}/source-before.txt" "${TEST_ARCH_SANDBOX}/source-after.txt" \
  || test_arch_die 'stow modified the overlay source'

# Sandbox-only links: every STOWED file landed as a symlink resolving inside
# the sandbox home or the repo overlay, and every source file landed. The
# two compositor-owned user files are deployed as real files by the desktop
# module instead: raw stow must leave them entirely alone (keep this skip
# list in sync with arch_desktop_deployed_relpaths).
while IFS= read -r src; do
  rel=${src#"${OVERLAY}/"}
  target="${TEST_ARCH_HOME}/${rel}"
  if [[ ${rel} == ./.config/caelestia/hypr-user.lua || ${rel} == ./.config/caelestia/hypr-vars.lua ]]; then
    [[ ! -e ${target} && ! -L ${target} ]] \
      || test_arch_die "stow touched user file ${rel} (must deploy as a real file, never stow)"
    continue
  fi
  [[ -L ${target} ]] || test_arch_die "deployed ${rel} is not a symlink"
  resolved="$(realpath -m -- "${target}")"
  [[ ${resolved} == "${TEST_ARCH_SANDBOX}"/* || ${resolved} == "${TEST_ARCH_REPO_ROOT}"/* ]] \
    || test_arch_die "link ${rel} escapes to ${resolved}"
done < <(cd -- "${OVERLAY}" && find . -mindepth 1 -type f | sort)

# The decided collision file deploys from the overlay, not shared home/.
[[ $(realpath -m -- "${TEST_ARCH_HOME}/.config/ghostty/config") == "${OVERLAY}/.config/ghostty/config" ]] \
  || test_arch_die 'sandbox ghostty config does not resolve to the overlay'

# Live home untouched: the narrow snapshot is byte-identical.
LIVE_AFTER="${TEST_ARCH_SANDBOX}/live-after.txt"
: >"${LIVE_AFTER}"
for rel in .config/ghostty/config \
  .config/gtk-3.0/settings.ini .config/gtk-4.0/settings.ini \
  .config/environment.d/10-desktop-theme.conf .local/bin/hypr-keybinds \
  .config/caelestia/hypr-vars.lua .config/caelestia/hypr-user.lua; do
  if [[ -e ${TEST_ARCH_LIVE_HOME}/${rel} || -L ${TEST_ARCH_LIVE_HOME}/${rel} ]]; then
    stat -c '%Y %n' "${TEST_ARCH_LIVE_HOME}/${rel}" >>"${LIVE_AFTER}"
    readlink "${TEST_ARCH_LIVE_HOME}/${rel}" >>"${LIVE_AFTER}" 2>/dev/null || true
  else
    printf 'absent %s\n' "${rel}" >>"${LIVE_AFTER}"
  fi
done
cmp -s -- "${LIVE_SNAPSHOT}" "${LIVE_AFTER}" \
  || test_arch_die 'live HOME managed paths moved during sandbox stow'

test_arch_assert_no_live_paths 'overlay stow'
printf 'Overlay stow is immutable-source, idempotent, and home-isolated.\n'
