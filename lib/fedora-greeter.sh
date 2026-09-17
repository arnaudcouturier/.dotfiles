#!/usr/bin/env bash
# lib/fedora-greeter.sh — greetd plus the Noctalia Greeter login screen.
#
# The greeter stack is greetd (Fedora) plus noctalia-greeter (Terra), with
# GDM and GNOME kept installed as the recovery desktop, never enabled
# alongside greetd. Replacing the active display manager is the one change
# here that can remove graphical login, so it needs the explicit
# --replace-display-manager contract; without it an incumbent display
# manager is reported, never disabled. With no incumbent at all (a minimal
# install like this host), setup enables greetd directly.
#
# Fedora's greetd package already ships keyring unlock lines and reaches
# pam_systemd through system-auth, so no PAM rewrite is needed here. Device
# access for the greeter session comes from logind, not static video/input
# groups. Greeter appearance sync stays disabled per the vanilla scope:
# upstream's live sync needs pkexec, which this repo forbids.

set -euo pipefail

# Verified 2026-09-17 on Fedora 44: greetd in fedora, noctalia-greeter 1.5.0
# in Terra 44, GDM/GNOME session in fedora/updates as the retained recovery
# desktop, accountsservice for greeter avatars.
readonly FEDORA_GREETER_PKGS=(
  greetd
  noctalia-greeter
  gdm
  gnome-shell
  gnome-session-wayland-session
  accountsservice
)

# Deploy one template to an absolute system path. Skips byte-identical
# targets, refuses symlinked parents or targets, keeps one
# `.dotfiles-backup` of the first replaced file, installs mode 0644. The
# /etc/greetd backup is the narrow Fedora exception to the no-backup rule:
# home files never back up; this boot/login config does, once.
fedora_greeter_deploy_template() {
  local template=$1 target=$2 backup
  [[ ${target} == /* ]] || die "System deploy target must be absolute: ${target}"
  [[ -r ${template} ]] || die "Missing Fedora system template: ${template}"
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

# Give the greeter account its packaged identity: user `greeter` rooted at
# /var/lib/noctalia-greeter (the paths the package's own setup script
# prints), plus its 0750 state dir. The Fedora greetd `greetd` user is a
# different account for the default agreety config; it stays untouched.
fedora_greeter_prepare_account() {
  local greeter_user=${FEDORA_GREETER_USER:-greeter}
  local greeter_home=${FEDORA_GREETER_HOME:-/var/lib/noctalia-greeter}
  if ! id -u "${greeter_user}" >/dev/null 2>&1; then
    sudo useradd -r -s /usr/bin/nologin -d "${greeter_home}" "${greeter_user}"
    log_ok 'Created the greeter user.'
  else
    local home_now
    home_now="$(getent passwd "${greeter_user}" | cut -d: -f6)"
    if [[ ${home_now} != "${greeter_home}" ]]; then
      sudo usermod -d "${greeter_home}" "${greeter_user}"
      log_warn "Moved greeter home to ${greeter_home}."
    fi
  fi
  sudo install -d -m0750 -o "${greeter_user}" -g "${greeter_user}" -- "${greeter_home}"
}

# Reconcile display-manager.service after the package install, then enable
# greetd. The check before the install cannot be the last word: dnf presets
# can enable gdm (installed here only as the recovery desktop) mid-run, so
# the pre-install answer is stale by enable time. `pre_dm` is the alias
# target recorded before the install; empty means this host had no display
# manager when the run started. Paths ride env overrides so tests can point
# them at a sandbox; production always uses the defaults.
fedora_greeter_reconcile_dm() {
  local pre_dm=${1:-} replace_display_manager=${2:-0}
  local dm_link=${FEDORA_GREETER_DM_LINK:-/etc/systemd/system/display-manager.service}
  local current_dm=''
  if [[ -L ${dm_link} ]]; then
    current_dm="$(basename "$(readlink "${dm_link}")")"
  fi
  if [[ ${current_dm} == greetd.service || -z ${current_dm} ]]; then
    sudo systemctl enable greetd.service
    return 0
  fi
  if [[ ${current_dm} == "${pre_dm}" ]]; then
    if [[ ${replace_display_manager} == 1 ]]; then
      log_warn "Replacing the active display manager (${current_dm}) with greetd under the explicit contract."
      sudo systemctl disable "${current_dm}" >/dev/null 2>&1 || sudo rm -f "${dm_link}"
      sudo systemctl enable greetd.service
      return 0
    fi
    die "The active display manager is ${current_dm}; refusing to touch it. Re-run with ./dot fedora-setup --replace-display-manager to switch, or disable ${current_dm} by hand first."
  fi
  # The alias changed mid-run. When this run started DM-less and the new
  # holder is gdm, that is this transaction's own preset artifact (gdm
  # arrived only as the recovery desktop): stand it down without demanding
  # the flag, since there was no incumbent to protect.
  if [[ -z ${pre_dm} && ${current_dm} == gdm.service ]]; then
    log_warn 'Standing down the freshly preset-enabled gdm (installed as the recovery desktop only); greetd serves login.'
    sudo systemctl disable gdm.service >/dev/null 2>&1 || sudo rm -f "${dm_link}"
    sudo systemctl enable greetd.service
    return 0
  fi
  if [[ ${replace_display_manager} == 1 ]]; then
    log_warn "Replacing the active display manager (${current_dm}) with greetd under the explicit contract."
    sudo systemctl disable "${current_dm}" >/dev/null 2>&1 || sudo rm -f "${dm_link}"
    sudo systemctl enable greetd.service
    return 0
  fi
  die "display-manager.service changed to ${current_dm} during setup; refusing to touch it. Re-run with ./dot fedora-setup --replace-display-manager to switch, or disable ${current_dm} by hand first."
}

# Deploy greetd config and enable the service. Pass replace_display_manager=1
# only under the explicit CLI contract; otherwise an incumbent display
# manager is reported, never disabled. Paths ride env overrides so tests can
# point them at a sandbox; production always uses the defaults.
fedora_greeter_setup() {
  local replace_display_manager=${1:-0}
  [[ ${DISTRO:-} == fedora ]] || die 'The greeter step is Fedora-only.'
  fedora_desktop_verify >/dev/null 2>&1 \
    || die 'Desktop step is incomplete. Run ./dot fedora-setup --only desktop first.'
  local template=${FEDORA_GREETER_TEMPLATE:-${DOTFILES_DIR}/system/fedora/greetd/config.toml}
  local config=${FEDORA_GREETER_CONFIG:-/etc/greetd/config.toml}
  local dm_link=${FEDORA_GREETER_DM_LINK:-/etc/systemd/system/display-manager.service}
  # Refuse before touching anything: enabling greetd beside an incumbent
  # display manager risks an incidental Alias takeover of
  # display-manager.service, which can remove graphical login. The explicit
  # --replace-display-manager contract is the only path past an incumbent.
  # Record the alias target before the install: the dnf transaction below
  # can preset-enable gdm (installed only as the recovery desktop), so the
  # reconcile after the install decides against this value, not a stale one.
  local pre_dm=''
  if [[ -L ${dm_link} ]]; then
    pre_dm="$(basename "$(readlink "${dm_link}")")"
  fi
  if [[ -n ${pre_dm} && ${pre_dm} != greetd.service && ${replace_display_manager} != 1 ]]; then
    die "The active display manager is ${pre_dm}; refusing to touch it. Re-run with ./dot fedora-setup --replace-display-manager to switch, or disable ${pre_dm} by hand first."
  fi
  fedora_desktop_ensure_terra
  log_step "Installing ${#FEDORA_GREETER_PKGS[@]} greeter package(s)"
  sudo dnf install -y -- "${FEDORA_GREETER_PKGS[@]}"
  fedora_greeter_prepare_account
  fedora_greeter_deploy_template "${template}" "${config}"
  # SC2015 is the intended shape here, not a mistaken if/then/else: the
  # failure branch runs exactly when the wanted state does not hold.
  # shellcheck disable=SC2015
  [[ ! -L ${config} ]] && grep -Fq -- 'noctalia-greeter-session' "${config}" \
    || die 'The deployed greetd config is linked or does not start noctalia-greeter-session.'
  fedora_greeter_reconcile_dm "${pre_dm}" "${replace_display_manager}"
  if [[ $(systemctl get-default) != graphical.target ]]; then
    sudo systemctl set-default graphical.target
    log_ok 'Default boot target is graphical.target.'
  fi
  log_ok 'greetd serves Noctalia Greeter after the next reboot. Pick Umbriel in its session list; GDM stays installed for recovery.'
}

# Check the greeter stack without changing anything. Reports drift; never
# writes. Enablement is deliberately unchecked: pre-cutover hosts validate
# files first, then switch with the explicit flag.
fedora_greeter_verify() {
  [[ ${DISTRO:-} == fedora ]] || return 1
  local failed=0 pkg
  for pkg in "${FEDORA_GREETER_PKGS[@]}"; do
    rpm -q -- "${pkg}" >/dev/null 2>&1 \
      || { log_error "Greeter package missing: ${pkg}. Run ./dot fedora-setup --only greeter."; failed=1; }
  done
  command -v noctalia-greeter-session >/dev/null 2>&1 \
    || { log_error 'noctalia-greeter-session is missing. Run ./dot fedora-setup --only greeter.'; failed=1; }
  local config=${FEDORA_GREETER_CONFIG:-/etc/greetd/config.toml}
  if [[ -L ${config} ]]; then
    log_error 'greetd config is a symlink; setup refuses linked targets.'
    failed=1
  elif [[ ! -f ${config} ]]; then
    log_error "greetd config missing: ${config}. Run ./dot fedora-setup --only greeter."
    failed=1
  else
    grep -Fq -- 'noctalia-greeter-session' "${config}" 2>/dev/null \
      || { log_error 'greetd does not start noctalia-greeter-session.'; failed=1; }
  fi
  local greeter_user=${FEDORA_GREETER_USER:-greeter}
  id -u "${greeter_user}" >/dev/null 2>&1 \
    || { log_error "Greeter user missing: ${greeter_user}. Run ./dot fedora-setup --only greeter."; failed=1; }
  return "${failed}"
}
