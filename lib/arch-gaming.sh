#!/usr/bin/env bash
# lib/arch-gaming.sh — opt-in gaming stack: Steam, GameMode, overlays, Proton tools.
#
# Ports the archive's packages/gaming.txt plus the gaming trio from its
# packages/aur.txt (protonplus, vkbasalt, lib32-vkbasalt). Opt-in, never
# default: arch_gaming_setup asks once (default No) and skips quietly on No
# or without a terminal, so a full `./dot arch-setup` stays safe on
# non-gaming machines; `--only gaming` from a terminal is the deliberate
# install path. An installed stack repairs without asking (install --needed).
# arch_gaming_verify treats absent as valid (not selected) and partial as
# drift. Nothing here belongs in packages/arch.bundle: the bundle is the
# unconditional recipe, and gaming is a choice.
#
# Requires multilib for the lib32-* entries. The system step owns
# pacman.conf, so setup ensures it through arch_system_setup_pacman_options
# (idempotent), falling back to a loud pointer when the system module is
# unavailable. GameMode group membership follows the package (the Mullvad
# pattern): silent without gamemode, repaired with it.

set -euo pipefail

# Steam, GameMode, MangoHud/GOverlay, Gamescope, NT-sync, 32-bit Vulkan
# loader, Proton tweaks — the archive's gaming.txt verbatim.
readonly ARCH_GAMING_REPO_PKGS=(
  steam
  gamemode
  lib32-gamemode
  goverlay
  lib32-mangohud
  gamescope
  ntsync-autoload
  lib32-vulkan-icd-loader
  protontricks
)

# Compat-tool manager plus the Vulkan post-processing GOverlay drives.
readonly ARCH_GAMING_AUR_PKGS=(
  protonplus
  vkbasalt
  lib32-vkbasalt
)

# Anchor package: its presence means the stack was selected before.
arch_gaming_installed() {
  pacman -Q steam >/dev/null 2>&1
}

# Ask on the terminal (default No). ARCH_GAMING_TTY overrides the terminal
# path so tests can answer from a fixture file; without a usable terminal
# the answer is No, never a hang. The prompt goes to stderr so it never
# disturbs the answer stream.
arch_gaming_ask() {
  local tty=${ARCH_GAMING_TTY:-/dev/tty} answer
  [[ -r ${tty} ]] || return 1
  printf 'Install the gaming stack (Steam, GameMode, MangoHud, Gamescope, Proton tools)? [y/N] ' >&2
  read -r answer <"${tty}" || return 1
  [[ ${answer} == [Yy] || ${answer} == [Yy][Ee][Ss] ]]
}

# GameMode needs the desktop user in the gamemode group for its performance
# knobs. Package-gated: silent without gamemode, repaired with it (re-login
# still applies group membership, hence the warning, not an error).
arch_gaming_ensure_gamemode_group() {
  pacman -Q gamemode >/dev/null 2>&1 || return 0
  local user
  user="$(id -un)"
  if id -nG "${user}" 2>/dev/null | tr ' ' '\n' | grep -Fxq gamemode; then
    return 0
  fi
  sudo usermod -aG gamemode "${user}"
  log_warn "Added ${user} to the gamemode group; log out and back in for GameMode's performance knobs."
}

# Install the stack when selected, repair it when present. Safe to re-run:
# the prompt appears only while steam is absent, everything else converges.
arch_gaming_setup() {
  if ! arch_gaming_installed; then
    arch_gaming_ask \
      || { log_info 'arch-gaming: gaming stack not selected; skipping.'; return 0; }
  fi
  # The lib32-* entries resolve only with multilib. The system module owns
  # that edit; ensure it here so `--only gaming` works standalone.
  if declare -F arch_system_setup_pacman_options >/dev/null 2>&1; then
    arch_system_setup_pacman_options
  elif ! pacman-conf --repo-list 2>/dev/null | grep -Fxq multilib; then
    die 'arch-gaming: multilib is disabled. Run ./dot arch-setup --only system first.'
  fi
  log_step "Installing ${#ARCH_GAMING_REPO_PKGS[@]} gaming package(s)"
  # -Syu, not -S: Arch forbids installing into a partially upgraded system.
  sudo pacman -Syu --needed --noconfirm -- "${ARCH_GAMING_REPO_PKGS[@]}"
  require_command yay
  log_warn 'AUR PKGBUILDs are user-produced. Review the changes shown by yay before approving.'
  yay -S --aur --needed -- "${ARCH_GAMING_AUR_PKGS[@]}"
  arch_gaming_ensure_gamemode_group
  log_ok 'Gaming stack installed.'
}

# Check the gaming stack without changing anything. Absent is a valid choice
# (not selected); a selected stack reports each missing package distinctly.
arch_gaming_verify() {
  local failed=0 pkg
  if ! arch_gaming_installed; then
    log_info 'arch-gaming: gaming stack not selected.'
    return 0
  fi
  for pkg in "${ARCH_GAMING_REPO_PKGS[@]}" "${ARCH_GAMING_AUR_PKGS[@]}"; do
    pacman -Q -- "${pkg}" >/dev/null 2>&1 \
      || { log_error "Gaming package missing: ${pkg}. Run ./dot arch-setup --only gaming."; failed=1; }
  done
  if pacman -Q gamemode >/dev/null 2>&1; then
    id -nG "$(id -un)" 2>/dev/null | tr ' ' '\n' | grep -Fxq gamemode \
      || { log_error "User not in the gamemode group. Run ./dot arch-setup --only gaming, then re-login."; failed=1; }
  fi
  return "${failed}"
}
