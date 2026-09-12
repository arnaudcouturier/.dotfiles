#!/usr/bin/env bash
# lib/arch-system.sh — Arch base tuning: pacman options, swap policy, services.
#
# Covers the portable half of the archive's 00-base and 30-services modules:
# repository options, compressed swap, VM tunables, and service enables. The
# AUR helper stays yay (no paru switch); GPU, snapshots, greeter, and Limine
# each live in their own arch module behind the same setup/verify seam.

set -euo pipefail

# Uncomment multilib plus readable, parallel pacman options. Keeps one backup
# of the first edit and revalidates, so a bad edit is restorable and never
# silent. The optional path is a test seam (tests exercise edits on temp
# files); production always uses the default. It bypasses nothing: callers
# refuse non-Arch and elevate before reaching here.
arch_system_setup_pacman_options() {
  local config=${1:-/etc/pacman.conf}
  local backup="${config}.dotfiles-backup" changed=false
  local live=false
  if [[ ${config} == /etc/pacman.conf ]]; then
    live=true
  fi
  if [[ ${live} == true ]]; then
    require_command pacman-conf
  fi
  local multilib_on=false
  if [[ ${live} == true ]]; then
    if pacman-conf --repo-list 2>/dev/null | grep -Fxq multilib; then
      multilib_on=true
    fi
  elif grep -Eq '^\[multilib\]$' "${config}"; then
    multilib_on=true
  fi
  if [[ ${multilib_on} == false ]]; then
    grep -Eq '^#\[multilib\]$' "${config}" \
      || die "The standard commented [multilib] section is missing from ${config}; enable multilib manually."
    [[ -e ${backup} ]] || sudo cp --archive -- "${config}" "${backup}"
    sudo sed -i \
      -e '/^#\[multilib\]$/,/^$/ s/^#\(\[multilib\]\)$/\1/' \
      -e '/^\[multilib\]$/,/^$/ s/^#\(Include = \/etc\/pacman.d\/mirrorlist\)$/\1/' \
      "${config}"
    if [[ ${live} == true ]]; then
      pacman-conf --repo-list 2>/dev/null | grep -Fxq multilib \
        || die "Unable to enable multilib. Restore ${backup}."
    else
      grep -Eq '^\[multilib\]$' "${config}" \
        || die "Unable to enable multilib in ${config}."
    fi
    changed=true
  fi
  local option
  for option in Color VerbosePkgLists; do
    if ! grep -Eq "^${option}\\b" "${config}" && grep -Eq "^#${option}\\b" "${config}"; then
      [[ -e ${backup} ]] || sudo cp --archive -- "${config}" "${backup}"
      # shellcheck disable=SC2016
      sudo sed -i -E "s/^#(${option}\\b.*)$/\\1/" "${config}"
      changed=true
    fi
  done
  if ! grep -Eq '^ParallelDownloads[[:space:]]*=' "${config}" \
    && grep -Eq '^#ParallelDownloads[[:space:]]*=' "${config}"; then
    [[ -e ${backup} ]] || sudo cp --archive -- "${config}" "${backup}"
    sudo sed -i -E 's/^#(ParallelDownloads[[:space:]]*=.*)$/\1/' "${config}"
    changed=true
  fi
  if [[ ${changed} == true ]]; then
    if [[ ${live} == true ]]; then
      sudo pacman-conf >/dev/null \
        || die "The edited ${config} is not parseable. Restore ${backup}."
    fi
    log_ok 'Enabled multilib plus readable, parallel pacman options.'
  else
    log_ok 'pacman options already carry multilib, colour, and parallel downloads.'
  fi
}

# Deploy the compressed swap and virtual memory policy, then activate both
# without a reboot. The zram device formats on start; sysctl --load applies
# the two VM keys to the running kernel.
arch_system_setup_swap_policy() {
  arch_deploy_system_template "$(arch_system_template_path 'systemd/zram-generator.conf')" /etc/systemd/zram-generator.conf
  arch_deploy_system_template "$(arch_system_template_path 'sysctl.d/99-arch-zram.conf')" /etc/sysctl.d/99-arch-zram.conf
  sudo systemctl daemon-reload
  # restart, not start: start succeeds without touching an already-active
  # unit, so a changed template would wait for a reboot to take effect. The
  # swapoff window is momentary and fails loudly under memory pressure
  # instead of silently keeping the stale policy.
  sudo systemctl restart dev-zram0.swap
  sudo sysctl --load=/etc/sysctl.d/99-arch-zram.conf
  log_ok 'Compressed swap and virtual memory policy are active.'
}

# Enable the Mullvad VPN daemon when its package is selected. Package-gated,
# not unit-gated: an installed package with a missing unit is a broken
# install and dies here (required flag) instead of silently skipping; a
# deselected package is a silent noop. enable --now is idempotent, so
# re-running repairs a disabled daemon and no-ops a healthy one.
arch_system_setup_mullvad() {
  pacman -Q mullvad-vpn >/dev/null 2>&1 || return 0
  arch_enable_system_unit mullvad-daemon.service
}

# Make the invoking user tailscaled's operator when the package is selected.
# The systray (shipped by home-arch/ as a systemd user unit plus a launcher
# entry) runs unprivileged, and only root or the operator may manage the
# daemon; without this the tray shows "No permission to manage Tailscale".
# Package-gated like Mullvad: installed with no unit is a broken install
# (loud), deselected is a silent noop. Repeating the set is one local
# preference write, no network.
arch_system_setup_tailscale() {
  pacman -Q tailscale >/dev/null 2>&1 || return 0
  arch_unit_exists tailscaled.service \
    || die 'tailscale is installed but tailscaled.service is missing: reinstall the package, then run ./dot arch-setup.'
  sudo tailscale set --operator="$(id -un)" >/dev/null
  log_ok "Tailscale operator is $(id -un)."
}

# Enable the core desktop services plus optional timers. Core units must
# exist (their packages are in arch.bundle); deselectable timers only warn,
# so a minimal bundle is never punished for skipping firmware or SMART tooling.
arch_system_setup_services() {
  local service
  for service in NetworkManager.service bluetooth.service accounts-daemon.service power-profiles-daemon.service fstrim.timer; do
    arch_enable_system_unit "${service}"
  done
  for service in paccache.timer reflector.timer fwupd-refresh.timer smartd.service; do
    arch_enable_system_unit "${service}" optional
  done
  if systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service
    log_ok 'PipeWire user sockets are enabled.'
  else
    log_warn 'The systemd user session is unavailable; PipeWire starts at the next login.'
  fi
  # Polkit has no unit: Caelestia starts the GNOME agent by absolute path at
  # session start, and exec failures there are silent, so verify the path now.
  local agent=/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
  [[ -x ${agent} ]] || die "${agent} is missing; graphical privilege prompts would silently do nothing."
  log_ok 'The Polkit agent the desktop starts is in place.'
  # Tailscale ships in arch.bundle; Docker does not (no WinBoat), so both are
  # opportunistic: enable what is installed, skip the rest without failing.
  for service in tailscaled.service docker.service; do
    arch_unit_exists "${service}" && arch_enable_system_unit "${service}" optional || true
  done
  arch_system_setup_tailscale
  arch_system_setup_mullvad
  log_ok 'System services are enabled.'
}

# Run every Arch base tuning step. Safe to re-run: each step skips work that
# already matches and every first write keeps a restorable backup.
arch_system_setup() {
  arch_system_setup_pacman_options
  arch_system_setup_swap_policy
  arch_system_setup_services
}

# Check Arch base tuning without changing anything. Reports drift; never writes.
arch_system_verify() {
  local failed=0
  pacman-conf --repo-list 2>/dev/null | grep -Fxq multilib \
    || { log_error 'multilib is disabled. Run ./dot arch-setup.'; failed=1; }
  cmp -s -- "$(arch_system_template_path 'systemd/zram-generator.conf')" /etc/systemd/zram-generator.conf 2>/dev/null \
    || { log_error 'zram policy differs from system/arch. Run ./dot arch-setup.'; failed=1; }
  cmp -s -- "$(arch_system_template_path 'sysctl.d/99-arch-zram.conf')" /etc/sysctl.d/99-arch-zram.conf 2>/dev/null \
    || { log_error 'sysctl policy differs from system/arch. Run ./dot arch-setup.'; failed=1; }
  swapon --noheadings --show=NAME 2>/dev/null | grep -Fxq /dev/zram0 \
    || { log_error 'Compressed swap is not active on /dev/zram0.'; failed=1; }
  [[ $(sysctl -n vm.swappiness 2>/dev/null) == 100 && $(sysctl -n vm.page-cluster 2>/dev/null) == 0 ]] \
    || { log_error 'Virtual memory policy is not the zram-tuned pair (swappiness 100, page-cluster 0).'; failed=1; }
  local service
  for service in NetworkManager.service bluetooth.service accounts-daemon.service power-profiles-daemon.service fstrim.timer; do
    systemctl is-enabled --quiet "${service}" 2>/dev/null \
      || { log_error "Service not enabled: ${service}."; failed=1; }
  done
  [[ -x /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 ]] \
    || { log_error 'Polkit agent missing; graphical prompts would do nothing.'; failed=1; }
  # Mullvad follows the package, not the unit: a deselected package skips
  # silently, while a selected one reports each broken state distinctly —
  # missing unit (broken install), disabled, or inactive. Repair for all
  # three: ./dot arch-setup --only system.
  if pacman -Q mullvad-vpn >/dev/null 2>&1; then
    if arch_unit_exists mullvad-daemon.service; then
      systemctl is-enabled --quiet mullvad-daemon.service 2>/dev/null \
        || { log_error 'mullvad-daemon is installed but not enabled. Run ./dot arch-setup --only system.'; failed=1; }
      systemctl is-active --quiet mullvad-daemon.service 2>/dev/null \
        || { log_error 'mullvad-daemon is installed but not active. Run ./dot arch-setup --only system.'; failed=1; }
    else
      log_error 'mullvad-vpn is installed but mullvad-daemon.service is missing: reinstall the package, then run ./dot arch-setup --only system.'
      failed=1
    fi
  fi
  # Optional timers report drift without failing: their packages are
  # deselectable, so an absent unit is a choice, but an installed yet
  # disabled one is worth a look.
  for service in paccache.timer reflector.timer fwupd-refresh.timer smartd.service; do
    if arch_unit_exists "${service}" && ! systemctl is-enabled --quiet "${service}" 2>/dev/null; then
      log_warn "Optional unit installed but not enabled: ${service}."
    fi
  done
  return "${failed}"
}
