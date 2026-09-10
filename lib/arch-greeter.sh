#!/usr/bin/env bash
# lib/arch-greeter.sh — greetd plus the sysc-greet niri session.
#
# sysc-greet draws inside niri, so the greeter stack is greetd plus niri plus
# kitty plus the AUR sysc-greet package. Replacing the active display manager
# is the one change here that can remove graphical login, so it needs the
# explicit --replace-display-manager contract; by default this module enables
# greetd and leaves any incumbent alone.

set -euo pipefail

readonly ARCH_GREETER_HOME=/var/lib/greeter
readonly ARCH_NIRI_GREETER_CONFIG=/etc/greetd/niri-greeter-config.kdl
readonly ARCH_KITTY_GREETER_CONFIG=/etc/greetd/kitty.conf
readonly ARCH_GREETD_PAM=/etc/pam.d/greetd

# Reconcile the compositor config with the installed sysc-greet path. The AUR
# package and upstream disagree on /usr/bin vs /usr/local/bin while the
# shipped niri config hardcodes one; a mismatch boots to a blank screen.
arch_greeter_reconcile_binary_path() {
  require_command niri
  require_command kitty
  command -v sysc-greet >/dev/null 2>&1 \
    || die 'sysc-greet is not installed. It is aur "sysc-greet" in arch.bundle: run ./dot arch-setup after the bundle installs.'
  local installed referenced backup
  installed="$(command -v sysc-greet)"
  for referenced_file in "${ARCH_NIRI_GREETER_CONFIG}" "${ARCH_KITTY_GREETER_CONFIG}"; do
    [[ -f ${referenced_file} ]] \
      || die "${referenced_file} is missing. Reinstall sysc-greet with: yay -S --aur sysc-greet"
  done
  referenced="$(grep -oE '(/usr(/local)?/bin/)sysc-greet' "${ARCH_NIRI_GREETER_CONFIG}" | head -n1 || true)"
  [[ -n ${referenced} ]] || die "${ARCH_NIRI_GREETER_CONFIG} does not invoke sysc-greet by absolute path; review it."
  if [[ ${referenced} != "${installed}" ]]; then
    backup="${ARCH_NIRI_GREETER_CONFIG}.dotfiles-backup"
    [[ -e ${backup} ]] || sudo cp --archive -- "${ARCH_NIRI_GREETER_CONFIG}" "${backup}"
    sudo sed -i "s|${referenced}|${installed}|g" "${ARCH_NIRI_GREETER_CONFIG}"
    grep -Fq "${installed}" "${ARCH_NIRI_GREETER_CONFIG}" \
      || die "Failed to correct sysc-greet path in ${ARCH_NIRI_GREETER_CONFIG}. Restore ${backup}."
    log_ok "Corrected the greeter sysc-greet path to ${installed}."
  fi
}

# Give the greeter account its expected home and input/video groups. The AUR
# scriptlet normally does this; verify rather than assume it did.
arch_greeter_prepare_account() {
  if ! id greeter >/dev/null 2>&1; then
    sudo useradd -M -d "${ARCH_GREETER_HOME}" -G video,render,input -s /usr/bin/nologin greeter
    log_ok 'Created the greeter user.'
  else
    local home_now
    home_now="$(getent passwd greeter | cut -d: -f6)"
    [[ ${home_now} == "${ARCH_GREETER_HOME}" ]] \
      || { sudo usermod -d "${ARCH_GREETER_HOME}" greeter; log_warn "Moved greeter home to ${ARCH_GREETER_HOME}."; }
    local group
    for group in video render input; do
      id -nG greeter | tr ' ' '\n' | grep -Fxq "${group}" \
        || { sudo usermod -aG "${group}" greeter; log_warn "Added greeter to ${group}."; }
    done
  fi
  sudo install -d -m0755 -o greeter -g greeter -- \
    "${ARCH_GREETER_HOME}" "${ARCH_GREETER_HOME}/Pictures/wallpapers" \
    "${ARCH_GREETER_HOME}/.cache" "${ARCH_GREETER_HOME}/.config" \
    "${ARCH_GREETER_HOME}/.local/state" /var/cache/sysc-greet
}

# Unlock the login keyring with the greeter-typed password. Both PAM lines
# are optional, so a missing module can never block authentication itself.
arch_greeter_wire_keyring_unlock() {
  local module=/usr/lib/security/pam_gnome_keyring.so
  [[ -f ${module} ]] || { log_warn "${module} is missing; skipping keyring auto-unlock."; return 0; }
  [[ -f ${ARCH_GREETD_PAM} ]] || { log_warn "${ARCH_GREETD_PAM} is missing; skipping keyring auto-unlock."; return 0; }
  [[ ! -L ${ARCH_GREETD_PAM} ]] || die "Refusing to edit a linked PAM file: ${ARCH_GREETD_PAM}"
  grep -Eq '^[[:space:]]*(auth|session)[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so' "${ARCH_GREETD_PAM}" \
    && { log_ok 'greetd already unlocks the login keyring through PAM.'; return 0; }
  local backup="${ARCH_GREETD_PAM}.dotfiles-backup"
  [[ -e ${backup} ]] || { sudo cp --archive -- "${ARCH_GREETD_PAM}" "${backup}"; log_warn "Preserved ${ARCH_GREETD_PAM} as ${backup}."; }
  printf '%s\n' 'auth       optional     pam_gnome_keyring.so' 'session    optional     pam_gnome_keyring.so auto_start' \
    | sudo tee -a "${ARCH_GREETD_PAM}" >/dev/null
  grep -Eq '^[[:space:]]*session[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so[[:space:]]+auto_start' "${ARCH_GREETD_PAM}" \
    || die "Failed to add keyring lines to ${ARCH_GREETD_PAM}. Restore ${backup}."
  log_ok 'greetd unlocks the login keyring through PAM.'
}

# Deploy greetd config and enable the service. Pass replace_display_manager=1
# only under the explicit CLI contract; otherwise an incumbent display
# manager is reported, never disabled.
arch_greeter_setup() {
  local replace_display_manager=${1:-0}
  # Refuse before touching anything: enabling greetd beside an incumbent
  # display manager risks an incidental Alias takeover of
  # display-manager.service, which can remove graphical login. The explicit
  # --replace-display-manager contract is the only path past an incumbent.
  local dm_link=/etc/systemd/system/display-manager.service current_dm=''
  if [[ -L ${dm_link} ]]; then
    current_dm="$(basename "$(readlink "${dm_link}")")"
  fi
  if [[ -n ${current_dm} && ${current_dm} != greetd.service && ${replace_display_manager} != 1 ]]; then
    die "The active display manager is ${current_dm}; refusing to touch it. Re-run with ./dot arch-setup --replace-display-manager to switch, or disable ${current_dm} by hand first."
  fi
  arch_greeter_reconcile_binary_path
  arch_greeter_prepare_account
  [[ ! -L /etc/greetd ]] || die 'Refusing to deploy through a linked /etc/greetd.'
  sudo install -d -m0755 -- /etc/greetd
  local backup=/etc/greetd/config.toml.dotfiles-backup
  if [[ -f /etc/greetd/config.toml && ! -e ${backup} ]] \
    && ! cmp -s -- "$(arch_system_template_path 'greetd/config.toml')" /etc/greetd/config.toml; then
    sudo cp --archive -- /etc/greetd/config.toml "${backup}"
    log_warn "Preserved the previous greetd config as ${backup}."
  fi
  sudo cp --remove-destination --preserve=mode,timestamps -- "$(arch_system_template_path 'greetd/config.toml')" /etc/greetd/config.toml
  sudo chmod 0644 /etc/greetd/config.toml
  # SC2015 is the intended shape here, not a mistaken if/then/else: the
  # failure branch runs exactly when the wanted state does not hold.
  # shellcheck disable=SC2015
  [[ ! -L /etc/greetd/config.toml ]] && grep -Fq -- "niri -c ${ARCH_NIRI_GREETER_CONFIG}" /etc/greetd/config.toml \
    || die 'The deployed greetd config is linked or does not start the niri greeter session.'
  [[ -f /etc/polkit-1/rules.d/85-greeter.rules ]] \
    || log_warn '85-greeter.rules is missing; shutdown/reboot from login stays denied.'
  arch_greeter_wire_keyring_unlock
  local dm_already_checked=${current_dm}
  if [[ -n ${dm_already_checked} && ${dm_already_checked} != greetd.service ]]; then
    log_warn "Replacing the active display manager (${dm_already_checked}) with greetd under the explicit contract."
    sudo systemctl disable "${dm_already_checked}" >/dev/null 2>&1 || sudo rm -f "${dm_link}"
  fi
  sudo systemctl enable greetd.service
  log_ok 'greetd serves sysc-greet after the next reboot. Pick Hyprland in its session list.'
}

# Check the greeter stack without changing anything. Reports drift; never writes.
arch_greeter_verify() {
  local failed=0
  command -v sysc-greet >/dev/null 2>&1 || { log_error 'sysc-greet is missing.'; return 1; }
  local installed
  installed="$(command -v sysc-greet)"
  grep -Fq "${installed}" "${ARCH_NIRI_GREETER_CONFIG}" 2>/dev/null \
    || { log_error 'The niri greeter config does not run the installed sysc-greet.'; failed=1; }
  [[ -f ${ARCH_KITTY_GREETER_CONFIG} ]] || { log_error 'Greeter kitty config is missing.'; failed=1; }
  [[ $(getent passwd greeter 2>/dev/null | cut -d: -f6) == "${ARCH_GREETER_HOME}" ]] \
    || { log_error 'Greeter home is not /var/lib/greeter.'; failed=1; }
  local group
  for group in video render input; do
    id -nG greeter 2>/dev/null | tr ' ' '\n' | grep -Fxq "${group}" \
      || { log_error "Greeter is missing group ${group}."; failed=1; }
  done
  # Same intended A && B || record-fail shape as the deploy check above.
  # shellcheck disable=SC2015
  [[ ! -L /etc/greetd/config.toml ]] && grep -Fq -- "niri -c ${ARCH_NIRI_GREETER_CONFIG}" /etc/greetd/config.toml 2>/dev/null \
    || { log_error 'greetd does not start the niri greeter session.'; failed=1; }
  # Mirrors setup's skip: without the module or PAM file there is nothing to
  # wire, so warn instead of failing; with them present, missing lines are
  # real drift and fail loudly.
  if [[ ! -f /usr/lib/security/pam_gnome_keyring.so || ! -f ${ARCH_GREETD_PAM} ]]; then
    log_warn 'Keyring prerequisites are absent; setup correctly skipped PAM wiring.'
  else
    grep -Eq '^[[:space:]]*session[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so[[:space:]]+auto_start' "${ARCH_GREETD_PAM}" 2>/dev/null \
      || { log_error 'greetd PAM does not unlock the login keyring.'; failed=1; }
  fi
  return "${failed}"
}
