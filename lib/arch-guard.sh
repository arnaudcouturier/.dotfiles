#!/usr/bin/env bash
# lib/arch-guard.sh — Arch gating and safe system-file helpers for provisioning.
#
# Every Arch provisioning entry point sources this module first and calls
# `require_arch_system` before any sudo, network, or system mutation. The
# deploy helpers below are the only sanctioned way to write outside $HOME:
# compare-before-copy with a one-time backup plus symlink refusal. Stock
# `stow_dotfiles` keeps its no-backup contract; that rule covers $HOME only.

set -euo pipefail

# Refuse provisioning on anything but Arch, before sudo or network use.
# Arch gating happens here so no caller can reorder it past elevation.
require_arch_system() {
  detect_distro
  [[ ${DISTRO} == arch ]] || die "Arch provisioning is Arch-only; this machine is '${DISTRO}'. Nothing was changed."
}

# Absolute path of this repo's Arch system templates (the /etc and /boot
# sources of truth that arch-setup deploys). Callers pass a relative name.
arch_system_template_path() {
  printf '%s/system/arch/%s\n' "${DOTFILES_DIR}" "$1"
}

# True when a systemd unit is known to systemd (shipped by an installed
# package). Used to enable optional timers only when their package survived.
arch_unit_exists() {
  systemctl cat -- "$1" >/dev/null 2>&1
}

# Deploy one template to an absolute system path. Skips byte-identical
# targets, refuses symlinked parents or targets, keeps one
# `.dotfiles-backup` of the first replaced file, installs mode 0644.
# Call only after begin_elevation; the template read itself needs no root.
arch_deploy_system_template() {
  local template=$1 target=$2 backup
  [[ ${target} == /* ]] || die "System deploy target must be absolute: ${target}"
  [[ -r ${template} ]] || die "Missing Arch system template: ${template}"
  if [[ -L ${target} || -L $(dirname -- "${target}") ]]; then
    die "Refusing to deploy through a symlink: ${target}"
  fi
  if [[ -f ${target} ]] && cmp -s -- "${template}" "${target}"; then
    log_ok "$(basename -- "${target}") already matches the template."
    return 0
  fi
  sudo install -d -m0755 -- "$(dirname -- "${target}")"
  if [[ -e ${target} ]]; then
    backup="${target}.dotfiles-backup"
    if [[ ! -e ${backup} ]]; then
      sudo cp --archive -- "${target}" "${backup}"
      log_warn "Preserved the previous $(basename -- "${target}") as ${backup}."
    fi
  fi
  sudo install --mode=0644 -- "${template}" "${target}"
  log_ok "Deployed $(basename -- "${target}") from ${template#"${DOTFILES_DIR}/"}."
}

# Enable and start one systemd system unit now. Core units die with a repair
# hint; optional units (timers for deselectable packages) only warn when the
# unit file is absent, so a minimal bundle stays valid.
arch_enable_system_unit() {
  local unit=$1 optional=${2:-required}
  if ! arch_unit_exists "${unit}"; then
    if [[ ${optional} == optional ]]; then
      log_info "Skipping ${unit}: its package is not installed."
      return 0
    fi
    die "Unable to enable ${unit}: no such unit. Run ./dot arch-setup after the bundle installs."
  fi
  sudo systemctl enable --now -- "${unit}" \
    || die "Unable to enable ${unit}."
  log_ok "Enabled ${unit}."
}
