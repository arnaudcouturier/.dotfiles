#!/usr/bin/env bash
# lib/fedora-desktop.sh — vanilla Umbriel plus the native Noctalia shell.
#
# Installs the Noctalia-family session on Fedora: the Terra umbriel-nightly
# compositor (its dependencies pull the Umbriel portal backend and
# xwayland-satellite), the Fedora noctalia shell, ghostty for the Mod+Return
# terminal (overriding the packaged kitty default), the Terra bibata cursor
# theme named by home-fedora's environment.d, the GTK portal fallback
# for file choosers, and gnome-keyring for Secret Service. No custom themes,
# widget layouts, app rules, or Hyprland behavior ports: packaged defaults
# rule, and the two personal keybindings (Mod+K cheatsheet, Mod+Return
# ghostty) live in the stowed Umbriel entrypoint, not here.
#
# Terra is a community repository, not a vendor repo: the release package is
# bootstrapped once from the documented repofrompath URL with --nogpgcheck
# (the greeter docs' own bootstrap), and every later transaction keeps
# signature checks on.

set -euo pipefail

# Single-quoted on purpose: $releasever must reach dnf literally so dnf
# expands it to the running Fedora release (44 here); bash must not.
# shellcheck disable=SC2016
readonly FEDORA_DESKTOP_TERRA_REF='terra,https://repos.fyralabs.com/terra$releasever'

# Verified 2026-09-17 on Fedora 44: noctalia 5.1.0 in updates,
# xwayland-satellite in fedora/updates, umbriel-nightly plus its portal
# backend plus ghostty 1.3.1 in Terra 44. umbriel-nightly already Requires
# the Umbriel portal and xwayland-satellite; they are listed here so the
# requirement stays explicit if that dependency ever loosens.
readonly FEDORA_DESKTOP_PKGS=(
  umbriel-nightly
  noctalia
  ghostty
  bibata-cursor-theme
  xwayland-satellite
  xdg-desktop-portal-gtk
  gnome-keyring
  gnome-keyring-pam
)

# Bootstrap the Terra repository once via its release package, then pin the
# names the bundle installs pinned for. Idempotent: a present release
# package skips the bootstrap, and the exclusion converges every run, so a
# machine that enabled Terra before the exclusion existed still repairs.
fedora_desktop_ensure_terra() {
  if rpm -q terra-release >/dev/null 2>&1; then
    log_ok 'Terra repository already configured.'
  else
    log_step 'Enabling Terra (community) for umbriel-nightly'
    sudo dnf install -y --nogpgcheck \
      --repofrompath "${FEDORA_DESKTOP_TERRA_REF}" terra-release
  fi
  fedora_desktop_exclude_pinned_from_terra
}

# Terra rebuilds Equibop at release 1.fc44, above the Equicord vendor RPM's
# bare 1 — so every `dnf upgrade` swaps the bundle's pinned vendor build
# for Terra's, whose update-alternatives %postun then deletes
# /usr/bin/equibop and leaves both launcher entries dead (and dot's own
# URL-vs-installed EVR check reads the vendor build as older, so init never
# swaps back). Exclude the name from Terra so the pinned route sticks; the
# compositor stack still resolves there. A direct `dnf install <URL>`
# bypasses the exclusion, so pinned installs and URL bumps keep working.
fedora_desktop_exclude_pinned_from_terra() {
  log_step 'Excluding Equibop from Terra (the bundle pins the vendor RPM)'
  sudo dnf config-manager setopt terra.excludepkgs=equibop
}

# Install (or repair) the desktop stack. Safe to re-run: dnf converges.
fedora_desktop_setup() {
  [[ ${DISTRO:-} == fedora ]] || die 'The desktop step is Fedora-only.'
  fedora_desktop_ensure_terra
  log_step "Installing ${#FEDORA_DESKTOP_PKGS[@]} desktop package(s)"
  sudo dnf install -y -- "${FEDORA_DESKTOP_PKGS[@]}"
  log_ok 'Desktop stack installed. Pick Umbriel at login; Super+Enter opens ghostty, Super+K opens the cheatsheet.'
}

# Check the desktop stack without changing anything. Every missing package
# is reported distinctly; the stowed Umbriel entrypoint must exist with the
# packaged-default include, the noctalia autostart, and the two personal
# overrides (Mod+K cheatsheet, Mod+Return ghostty).
fedora_desktop_verify() {
  [[ ${DISTRO:-} == fedora ]] || return 1
  local failed=0 pkg
  for pkg in "${FEDORA_DESKTOP_PKGS[@]}"; do
    rpm -q -- "${pkg}" >/dev/null 2>&1 \
      || { log_error "Desktop package missing: ${pkg}. Run ./dot fedora-setup --only desktop."; failed=1; }
  done
  for cmd in umbriel noctalia ghostty; do
    command -v "${cmd}" >/dev/null 2>&1 \
      || { log_error "Desktop binary missing: ${cmd}. Run ./dot fedora-setup --only desktop."; failed=1; }
  done
  # The bundle pins Equibop to the Equicord vendor RPM while Terra carries
  # a higher-tagged rebuild that would shadow it: the exclusion must be
  # present or the next upgrade swaps the working build for a dead one.
  # Scoped to the [terra] section — an exclusion elsewhere (e.g. the
  # disabled -source section) does not protect upgrades. The path is a
  # test seam; production always reads the live repo configuration.
  local terra_repo="${FEDORA_TERRA_REPO_FILE:-/etc/yum.repos.d/terra.repo}"
  if ! sed -n '/^\[terra\]/,/^\[/p' "${terra_repo}" 2>/dev/null \
    | grep -Eq '^[[:space:]]*excludepkgs[[:space:]]*=([^#]*[,[:space:]])?equibop([,[:space:]]|$)'; then
    log_error "Terra still serves equibop (the pinned vendor RPM would be shadowed). Run ./dot fedora-setup --only desktop."
    failed=1
  fi
  local config="${HOME}/.config/umbriel/config.toml"
  if [[ ! -f ${config} ]]; then
    log_error "Umbriel entrypoint missing: ${config}. Run ./dot stow."
    failed=1
  else
    grep -Fq '/usr/share/umbriel/config.toml' "${config}" 2>/dev/null \
      || { log_error "Umbriel entrypoint does not include the packaged defaults. Run ./dot stow."; failed=1; }
    grep -Fq 'autostart = ["noctalia"]' "${config}" 2>/dev/null \
      || { log_error "Umbriel entrypoint does not autostart noctalia once. Run ./dot stow."; failed=1; }
    grep -Fq '"Mod+K"' "${config}" 2>/dev/null \
      || { log_error "Umbriel entrypoint lacks the Mod+K cheatsheet override. Run ./dot stow."; failed=1; }
    grep -Fq 'spawn:ghostty' "${config}" 2>/dev/null \
      || { log_error "Umbriel entrypoint lacks the Mod+Return ghostty override. Run ./dot stow."; failed=1; }
  fi
  return "${failed}"
}
