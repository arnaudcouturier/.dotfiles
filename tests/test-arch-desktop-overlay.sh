#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# Production overlay integration: the real arch_desktop_install_overlay
# against a temp HOME, plus dot's shared/overlay stow interplay per distro.
# Repeated Arch stow must never reclaim the overlay Ghostty for shared home/
# nor write into the overlay source. Real stow; sudo fail-closed.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox
test_arch_stub_command sudo

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-desktop.sh"
test_arch_arm_cleanup

# --- Availability and the approved-shadow list. ---
arch_desktop_overlay_available >/dev/null
test_arch_assert_contains <(arch_desktop_override_relpaths) '.config/ghostty/config' 'ghostty is the approved shadow'
arch_desktop_is_approved_override '.config/ghostty/config'
set +e
arch_desktop_is_approved_override '.config/mpv/mpv.conf' >/dev/null 2>&1
approved_status=$?
set -e
((approved_status != 0)) || test_arch_die 'mpv.conf counted as an approved shadow'

# --- Install over conflicts: diverged file and dangling link are replaced. ---
mkdir -p -- "${TEST_ARCH_HOME}/.config/mpv" "${TEST_ARCH_HOME}/.config/ghostty"
printf '# local divergence\n' >"${TEST_ARCH_HOME}/.config/mpv/mpv.conf"
ln -s -- "${TEST_ARCH_HOME}/does-not-exist" "${TEST_ARCH_HOME}/.config/ghostty/config"
find "${TEST_ARCH_REPO_ROOT}/home-arch" -type f -exec sha256sum -- {} + | sort -k2 \
  >"${TEST_ARCH_SANDBOX}/overlay-source-before.txt"
arch_desktop_install_overlay >/dev/null
cmp -s -- "${TEST_ARCH_REPO_ROOT}/home-arch/.config/mpv/mpv.conf" "${TEST_ARCH_HOME}/.config/mpv/mpv.conf" \
  || test_arch_die 'diverged mpv.conf was not replaced by the overlay'
test_arch_assert_eq "${TEST_ARCH_REPO_ROOT}/home-arch/.config/ghostty/config" \
  "$(realpath -m -- "${TEST_ARCH_HOME}/.config/ghostty/config")" 'ghostty resolves to the overlay'

# --- Idempotent re-run: tree stable. ---
find "${TEST_ARCH_HOME}" -mindepth 1 | sort >"${TEST_ARCH_SANDBOX}/deployed-first.txt"
arch_desktop_install_overlay >/dev/null
find "${TEST_ARCH_HOME}" -mindepth 1 | sort >"${TEST_ARCH_SANDBOX}/deployed-second.txt"
cmp -s -- "${TEST_ARCH_SANDBOX}/deployed-first.txt" "${TEST_ARCH_SANDBOX}/deployed-second.txt" \
  || test_arch_die 'overlay re-install was not idempotent'
arch_desktop_verify_overlay >/dev/null

# --- No source write-through from any install path. ---
find "${TEST_ARCH_REPO_ROOT}/home-arch" -type f -exec sha256sum -- {} + | sort -k2 \
  >"${TEST_ARCH_SANDBOX}/overlay-source-after.txt"
cmp -s -- "${TEST_ARCH_SANDBOX}/overlay-source-before.txt" "${TEST_ARCH_SANDBOX}/overlay-source-after.txt" \
  || test_arch_die 'install wrote through into the overlay source'

# --- Real-directory collision dies loudly. ---
rm -- "${TEST_ARCH_HOME}/.local/bin/hypr-keybinds"
mkdir -p -- "${TEST_ARCH_HOME}/.local/bin/hypr-keybinds"
set +e
( arch_desktop_install_overlay >/dev/null 2>&1 )
realdir_status=$?
set -e
((realdir_status != 0)) || test_arch_die 'real-directory collision installed over'
rmdir -- "${TEST_ARCH_HOME}/.local/bin/hypr-keybinds"
arch_desktop_install_overlay >/dev/null

# --- Unapproved shared shadow dies; approved shadow proceeds. ---
ln -sfn -- "${TEST_ARCH_REPO_ROOT}/home/.config/mpv/mpv.conf" "${TEST_ARCH_HOME}/.config/mpv/mpv.conf"
set +e
( arch_desktop_install_overlay >/dev/null 2>&1 )
unapproved_status=$?
set -e
((unapproved_status != 0)) || test_arch_die 'unapproved shared shadow installed silently'
# The refusal correctly leaves the offender: remove it, then reclaim.
rm -f -- "${TEST_ARCH_HOME}/.config/mpv/mpv.conf"
arch_desktop_install_overlay >/dev/null
test_arch_assert_eq "${TEST_ARCH_REPO_ROOT}/home-arch/.config/mpv/mpv.conf" \
  "$(realpath -m -- "${TEST_ARCH_HOME}/.config/mpv/mpv.conf")" 'overlay reclaims mpv.conf'

# --- dot interplay, Arch: shared stow skips forwarding aliases and never
# --- reclaims the overlay; repeated cycles stay converged. ---
HOME2="${TEST_ARCH_SANDBOX}/home2"
mkdir -p -- "${HOME2}"
export HOME="${HOME2}"
DISTRO=arch
stow_dotfiles >/dev/null
[[ ! -e ${HOME2}/.config/ghostty/config && ! -L ${HOME2}/.config/ghostty/config ]] \
  || test_arch_die 'Arch shared stow deployed forwarding-alias ghostty'
[[ ! -e ${HOME2}/.config/hypr/input.lua && ! -L ${HOME2}/.config/hypr/input.lua ]] \
  || test_arch_die 'Arch shared stow deployed forwarding-alias input.lua'
stow_arch_overlay >/dev/null
test_arch_assert_eq "${TEST_ARCH_REPO_ROOT}/home-arch/.config/ghostty/config" \
  "$(realpath -m -- "${HOME2}/.config/ghostty/config")" 'overlay ghostty wins on Arch'
stow_dotfiles >/dev/null
test_arch_assert_eq "${TEST_ARCH_REPO_ROOT}/home-arch/.config/ghostty/config" \
  "$(realpath -m -- "${HOME2}/.config/ghostty/config")" 'repeat shared stow keeps Arch ghostty'
[[ ! -e ${HOME2}/.config/hypr/input.lua && ! -L ${HOME2}/.config/hypr/input.lua ]] \
  || test_arch_die 'repeat shared stow restored forwarding-alias input.lua'

# --- dot interplay, Fedora: shared stow skips forwarding aliases, the ---
# --- Fedora overlay provides the real copies, the Arch overlay stays out. ---
HOME3="${TEST_ARCH_SANDBOX}/home3"
mkdir -p -- "${HOME3}"
export HOME="${HOME3}"
DISTRO=fedora
export DISTRO
stow_dotfiles >/dev/null
[[ ! -e ${HOME3}/.config/ghostty/config && ! -L ${HOME3}/.config/ghostty/config ]] \
  || test_arch_die 'Fedora shared stow deployed forwarding-alias ghostty'
[[ ! -e ${HOME3}/.config/hypr/input.lua && ! -L ${HOME3}/.config/hypr/input.lua ]] \
  || test_arch_die 'Fedora shared stow deployed forwarding-alias input.lua'
stow_fedora_overlay >/dev/null
test_arch_assert_eq "${TEST_ARCH_REPO_ROOT}/home-fedora/.config/ghostty/config" \
  "$(realpath -m -- "${HOME3}/.config/ghostty/config")" 'Fedora overlay provides ghostty'
test_arch_assert_eq "${TEST_ARCH_REPO_ROOT}/home-fedora/.config/hypr/input.lua" \
  "$(realpath -m -- "${HOME3}/.config/hypr/input.lua")" 'Fedora overlay provides input.lua'
stow_arch_overlay >/dev/null
[[ ! -e ${HOME3}/.config/mpv/mpv.conf ]] \
  || test_arch_die 'Arch overlay stow deployed Arch files on Fedora'
test_arch_assert_eq "${TEST_ARCH_REPO_ROOT}/home-fedora/.config/ghostty/config" \
  "$(realpath -m -- "${HOME3}/.config/ghostty/config")" 'Arch overlay cannot displace Fedora ghostty'
stow_dotfiles >/dev/null
test_arch_assert_eq "${TEST_ARCH_REPO_ROOT}/home-fedora/.config/ghostty/config" \
  "$(realpath -m -- "${HOME3}/.config/ghostty/config")" 'repeat shared stow keeps Fedora ghostty'

export HOME="${TEST_ARCH_HOME}"
test_arch_assert_not_called sudo 'overlay integration never elevates'
test_arch_assert_no_live_paths 'overlay integration'
printf 'Overlay install converges, defends its shadows, and honors per-distro selection.\n'
