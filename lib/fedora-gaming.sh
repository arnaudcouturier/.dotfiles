#!/usr/bin/env bash
# lib/fedora-gaming.sh — opt-in Fedora gaming stack, official packages only.
#
# Fedora mirror of lib/arch-gaming.sh: same opt-in contract (asks once, default
# No, silent skip without a terminal; repairs without asking once selected;
# verify treats absent as valid and partial as drift). Nothing here belongs in
# packages/fedora.bundle: the bundle is the unconditional recipe.
#
# Packages come only from Fedora's own repos and RPM Fusion (vendor-backed,
# the same source ensure_nvidia uses):
#   steam, gamemode, goverlay, gamescope, mangohud, protontricks
# Deliberately excluded (no official Fedora/RPM Fusion package; the existing
# routes are third-party COPRs or unofficial repacks — the repo refuses those):
#   vkbasalt, protonplus, ntsync-autoload (Arch AUR concept; Fedora 43+ ships
#   ntsync support in the kernel directly).
# Fedora needs no multilib repo edit: x86_64 dnf resolves i686 deps itself.
# GameMode on Fedora needs no group membership (that is an Arch packaging
# detail); gamemoded runs as the user session.

set -euo pipefail

# Fedora repos plus RPM Fusion nonfree; installed in one transaction.
readonly FEDORA_GAMING_PKGS=(
  steam
  gamemode
  goverlay
  gamescope
  mangohud
  protontricks
)

# Anchor package: its presence means the stack was selected before.
fedora_gaming_installed() {
  rpm -q -- "${FEDORA_GAMING_PKGS[0]}" >/dev/null 2>&1
}

# Ask on the terminal (default No). FEDORA_GAMING_TTY overrides the terminal
# path so tests can answer from a fixture file; without a usable terminal
# the answer is No, never a hang. The prompt goes to stderr.
fedora_gaming_ask() {
  local tty=${FEDORA_GAMING_TTY:-/dev/tty} answer
  [[ -r ${tty} ]] || return 1
  printf 'Install the gaming stack (Steam, GameMode, MangoHud, Gamescope, Proton tools)? [y/N] ' >&2
  read -r answer <"${tty}" || return 1
  [[ ${answer} == [Yy] || ${answer} == [Yy][Ee][Ss] ]]
}

# RPM Fusion free + nonfree release packages, the same vendor route and URL
# pattern ensure_nvidia uses. Idempotent: dnf installs the release package
# once and re-running reports it is already present.
fedora_gaming_ensure_rpmfusion() {
  if rpm -q rpmfusion-free-release >/dev/null 2>&1 \
    && rpm -q rpmfusion-nonfree-release >/dev/null 2>&1; then
    log_ok 'RPM Fusion repositories already configured.'
    return 0
  fi
  log_step 'Enabling RPM Fusion (free and nonfree) for Steam'
  sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
}

# Install the stack when selected, repair it when present. Safe to re-run:
# the prompt appears only while steam is absent, everything else converges.
fedora_gaming_setup() {
  [[ ${DISTRO:-} == fedora ]] || die 'The gaming stack step is Fedora-only.'
  if ! fedora_gaming_installed; then
    fedora_gaming_ask \
      || { log_info 'fedora-gaming: gaming stack not selected; skipping.'; return 0; }
  fi
  fedora_gaming_ensure_rpmfusion
  log_step "Installing ${#FEDORA_GAMING_PKGS[@]} gaming package(s)"
  sudo dnf install -y -- "${FEDORA_GAMING_PKGS[@]}"
  log_ok 'Gaming stack installed.'
}

# Check the gaming stack without changing anything. Absent is a valid choice
# (not selected); a selected stack reports each missing package distinctly.
fedora_gaming_verify() {
  [[ ${DISTRO:-} == fedora ]] || return 1
  local failed=0 pkg
  if ! fedora_gaming_installed; then
    log_info 'fedora-gaming: gaming stack not selected.'
    return 0
  fi
  for pkg in "${FEDORA_GAMING_PKGS[@]}"; do
    rpm -q -- "${pkg}" >/dev/null 2>&1 \
      || { log_error "Gaming package missing: ${pkg}. Run ./dot fedora-setup --only gaming."; failed=1; }
  done
  return "${failed}"
}
