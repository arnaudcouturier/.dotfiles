#!/usr/bin/env bash
# lib/arch-snapshots.sh — btrfs-conditional pre-upgrade snapshots via snapper.
#
# Snapshots turn a bad rolling-release update into a rollback. They are a
# btrfs feature: on any other root filesystem this module succeeds without
# doing anything rather than pretending to protect. Booting into a snapshot
# needs bootloader support outside this repo; the Limine module never removes
# entries, so a snapshot-boot entry added by hand survives arch-setup.

set -euo pipefail

# Install snapper tooling and the root configuration on btrfs; skip cleanly
# elsewhere. snap-pac needs no service: it brackets pacman once root exists.
arch_snapshots_setup() {
  require_command findmnt
  local fstype
  fstype="$(findmnt --noheadings --output FSTYPE --target / 2>/dev/null)" || fstype=''
  [[ -n ${fstype} ]] || die 'Unable to determine the filesystem mounted at /.'
  if [[ ${fstype} != btrfs ]]; then
    log_warn "Root is ${fstype}, not btrfs; pre-upgrade snapshots are unavailable."
    log_ok "Snapshot step skipped on ${fstype}."
    return 0
  fi
  sudo pacman -Syu --needed --noconfirm -- btrfs-progs snapper snap-pac
  if sudo snapper -c root get-config >/dev/null 2>&1; then
    log_ok "The snapper 'root' configuration already exists."
  else
    if [[ -e /.snapshots ]]; then
      die "/.snapshots exists without a snapper 'root' configuration. Inspect it, then run: sudo snapper -c root create-config / (move /.snapshots aside first if snapper refuses)."
    fi
    sudo snapper -c root create-config / \
      || die 'snapper could not configure /. Confirm / is a btrfs subvolume.'
    log_ok "Created the snapper 'root' configuration."
  fi
  arch_enable_system_unit snapper-timeline.timer
  arch_enable_system_unit snapper-cleanup.timer
  log_warn 'Snapshots are taken, but booting one needs a bootloader entry this repo does not configure.'
  log_ok 'Pre-upgrade snapshots are active: snap-pac brackets every pacman transaction.'
}

# Check snapshot readiness without changing anything. Non-btrfs is a warning,
# never a failure; a cached-sudo miss is reported, not papered over.
arch_snapshots_verify() {
  local fstype
  fstype="$(findmnt --noheadings --output FSTYPE --target / 2>/dev/null || true)"
  if [[ ${fstype} != btrfs ]]; then
    log_warn "Root is ${fstype:-unknown}, not btrfs; snapshots stay unavailable here."
    return 0
  fi
  local failed=0
  if sudo -n snapper -c root get-config >/dev/null 2>&1; then
    log_ok "snapper 'root' configuration exists."
  else
    log_warn "Could not confirm the snapper 'root' configuration without a sudo prompt; verify with: sudo snapper -c root get-config"
  fi
  local timer
  for timer in snapper-timeline.timer snapper-cleanup.timer; do
    systemctl is-enabled --quiet "${timer}" 2>/dev/null \
      || { log_error "Timer not enabled: ${timer}."; failed=1; }
  done
  return "${failed}"
}
