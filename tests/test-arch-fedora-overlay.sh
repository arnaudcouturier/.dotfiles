#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# Fedora overlay: pre-move link chains stay valid and converge onto
# home-fedora/; fresh and repeat stows are stable with checksums intact;
# the Arch tree never deploys on Fedora and vice versa. Real stow against
# sandbox homes only; sudo fail-closed.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox
test_arch_stub_command sudo
command -v stow >/dev/null 2>&1 || { printf 'SEAM PENDING: GNU stow not installed\n'; exit 3; }

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
test_arch_arm_cleanup

FEDORA="${TEST_ARCH_REPO_ROOT}/home-fedora"
[[ -d ${FEDORA} ]] || { printf 'SEAM PENDING: home-fedora/ overlay missing\n'; exit 3; }
export DISTRO

# --- Source tree holds real files only (the refusal seam is live). ---
while IFS= read -r -d '' src; do
  [[ ! -L ${src} ]] || test_arch_die "home-fedora/ ships a symlink: ${src}"
  [[ -f ${src} ]] || test_arch_die "home-fedora/ ships a non-file: ${src}"
done < <(find "${FEDORA}" -mindepth 1 ! -type d -print0)

# --- Refusal: a symlinked source entry dies naming the offender. ---
BAD="${TEST_ARCH_SANDBOX}/bad-tree"
mkdir -p -- "${BAD}/.config/ghostty"
printf '# bad\n' >"${BAD}/.config/ghostty/config"
ln -s -- "${BAD}/.config/ghostty/config" "${BAD}/.config/ghostty/alias"
DISTRO=fedora
set +e
( stow_fedora_overlay "${BAD}" >/dev/null 2>&1 )
refuse_status=$?
set -e
((refuse_status != 0)) || test_arch_die 'symlinked source tree installed silently'

# --- Legacy: pre-move links (stow-relative and absolute chains through the
# --- repo alias) converge onto the Fedora source with content intact. ---
LEGACY="${TEST_ARCH_SANDBOX}/legacy-home"
mkdir -p -- "${LEGACY}/.config/ghostty" "${LEGACY}/.config/hypr"
export HOME="${LEGACY}"
legacy_ghostty_rel="$(realpath --relative-to="${LEGACY}/.config/ghostty" "${TEST_ARCH_REPO_ROOT}/home/.config/ghostty/config")"
ln -s -- "${legacy_ghostty_rel}" "${LEGACY}/.config/ghostty/config"
ln -s -- "${TEST_ARCH_REPO_ROOT}/home/.config/hypr/input.lua" "${LEGACY}/.config/hypr/input.lua"
stow_dotfiles >/dev/null
stow_fedora_overlay >/dev/null
test_arch_assert_eq "${FEDORA}/.config/ghostty/config" \
  "$(realpath -m -- "${LEGACY}/.config/ghostty/config")" 'legacy ghostty chain converges onto home-fedora/'
test_arch_assert_eq "${FEDORA}/.config/hypr/input.lua" \
  "$(realpath -m -- "${LEGACY}/.config/hypr/input.lua")" 'legacy input.lua chain converges onto home-fedora/'
cmp -s -- "${FEDORA}/.config/ghostty/config" "${LEGACY}/.config/ghostty/config" \
  || test_arch_die 'legacy ghostty content changed in transit'
cmp -s -- "${FEDORA}/.config/hypr/input.lua" "${LEGACY}/.config/hypr/input.lua" \
  || test_arch_die 'legacy input.lua content changed in transit'

# --- Current: fresh shared plus overlay stow lands both real copies. ---
FRESH="${TEST_ARCH_SANDBOX}/fresh-home"
mkdir -p -- "${FRESH}"
export HOME="${FRESH}"
stow_dotfiles >/dev/null
[[ ! -e ${FRESH}/.config/ghostty/config && ! -L ${FRESH}/.config/ghostty/config ]] \
  || test_arch_die 'shared stow deployed the ghostty forwarding alias'
[[ ! -e ${FRESH}/.config/hypr/input.lua && ! -L ${FRESH}/.config/hypr/input.lua ]] \
  || test_arch_die 'shared stow deployed the input.lua forwarding alias'
stow_fedora_overlay >/dev/null
test_arch_assert_eq "${FEDORA}/.config/ghostty/config" \
  "$(realpath -m -- "${FRESH}/.config/ghostty/config")" 'fresh ghostty resolves to home-fedora/'
test_arch_assert_eq "${FEDORA}/.config/hypr/input.lua" \
  "$(realpath -m -- "${FRESH}/.config/hypr/input.lua")" 'fresh input.lua resolves to home-fedora/'

# --- Repeat: rerunning both stows changes nothing, checksums hold. ---
find "${FRESH}" -mindepth 1 | sort >"${TEST_ARCH_SANDBOX}/fresh-first.txt"
sha256sum -- "${FRESH}/.config/ghostty/config" "${FRESH}/.config/hypr/input.lua" \
  >"${TEST_ARCH_SANDBOX}/fresh-sums-first.txt"
stow_dotfiles >/dev/null
stow_fedora_overlay >/dev/null
find "${FRESH}" -mindepth 1 | sort >"${TEST_ARCH_SANDBOX}/fresh-second.txt"
sha256sum -- "${FRESH}/.config/ghostty/config" "${FRESH}/.config/hypr/input.lua" \
  >"${TEST_ARCH_SANDBOX}/fresh-sums-second.txt"
cmp -s -- "${TEST_ARCH_SANDBOX}/fresh-first.txt" "${TEST_ARCH_SANDBOX}/fresh-second.txt" \
  || test_arch_die 'repeat stow changed the deployed tree'
cmp -s -- "${TEST_ARCH_SANDBOX}/fresh-sums-first.txt" "${TEST_ARCH_SANDBOX}/fresh-sums-second.txt" \
  || test_arch_die 'repeat stow changed deployed content'

# --- Cross-distro: the Arch tree never deploys on Fedora and vice versa. ---
stow_arch_overlay >/dev/null
[[ ! -e ${FRESH}/.config/mpv/mpv.conf ]] \
  || test_arch_die 'Arch overlay deployed on Fedora'
test_arch_assert_eq "${FEDORA}/.config/ghostty/config" \
  "$(realpath -m -- "${FRESH}/.config/ghostty/config")" 'Arch overlay cannot displace Fedora ghostty'
ARCH_HOME="${TEST_ARCH_SANDBOX}/arch-home"
mkdir -p -- "${ARCH_HOME}"
export HOME="${ARCH_HOME}"
DISTRO=arch
stow_dotfiles >/dev/null
stow_fedora_overlay >/dev/null
[[ ! -e ${ARCH_HOME}/.config/hypr/input.lua && ! -L ${ARCH_HOME}/.config/hypr/input.lua ]] \
  || test_arch_die 'Fedora input.lua leaked onto Arch'
stow_arch_overlay >/dev/null
test_arch_assert_eq "${TEST_ARCH_REPO_ROOT}/home-arch/.config/ghostty/config" \
  "$(realpath -m -- "${ARCH_HOME}/.config/ghostty/config")" 'ghostty stays Arch after Fedora no-op'
stow_dotfiles >/dev/null
test_arch_assert_eq "${TEST_ARCH_REPO_ROOT}/home-arch/.config/ghostty/config" \
  "$(realpath -m -- "${ARCH_HOME}/.config/ghostty/config")" 'repeat shared stow keeps Arch ghostty'

# --- Real-directory collision dies loudly instead of deleting. ---
export HOME="${FRESH}"
DISTRO=fedora
rm -- "${FRESH}/.config/ghostty/config"
mkdir -p -- "${FRESH}/.config/ghostty/config"
set +e
( stow_fedora_overlay >/dev/null 2>&1 )
realdir_status=$?
set -e
((realdir_status != 0)) || test_arch_die 'real-directory collision installed over'
rmdir -- "${FRESH}/.config/ghostty/config"

export HOME="${TEST_ARCH_HOME}"
test_arch_assert_not_called sudo 'fedora overlay never elevates'
test_arch_assert_no_live_paths 'fedora overlay'
printf 'Fedora overlay converges legacy chains, repeats stably, and stays distro-selected.\n'
