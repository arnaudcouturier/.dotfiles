#!/usr/bin/env bash
# lib/arch-limine.sh — Tokyo Night Limine theming, a Windows dual-boot entry,
# plus a safe firmware entry.
#
# Themes every limine.conf the firmware might read (which one wins depends on
# how firmware reports the boot volume) with a guarded marker block, ensures
# one Windows chainload entry when this ESP carries Microsoft's loader, then
# ensures exactly one named Limine firmware entry exists. Entries are only
# ever added, never removed or reordered; the archinstall entry is kept.

set -euo pipefail

readonly ARCH_LIMINE_BEGIN_MARKER='# >>> dotfiles appearance >>>'
readonly ARCH_LIMINE_END_MARKER='# <<< dotfiles appearance >>>'

# Remount bookkeeping: ESPs are often read-only between boot updates, so the
# setup widens each touched mount and this EXIT trap always narrows it back.
ARCH_LIMINE_REMOUNTED=()

arch_limine_restore_mounts() {
  local target
  for target in ${ARCH_LIMINE_REMOUNTED[@]+"${ARCH_LIMINE_REMOUNTED[@]}"}; do
    sudo mount --options remount,ro --target "${target}" \
      || log_error "Failed to restore read-only mount on ${target}."
  done
  ARCH_LIMINE_REMOUNTED=()
}

# Resolve one mount field for a path through sudo: /boot is routinely
# root-only, so an unprivileged findmnt cannot even name its filesystem.
arch_limine_mount_field() {
  local field=$1 path=$2 value
  value="$(sudo findmnt --noheadings --first-only --output "${field}" --target "${path}" 2>/dev/null)" || return 1
  [[ -n ${value} ]] || return 1
  printf '%s\n' "${value}"
}

# Widen a read-only mount for the duration of the run; the EXIT trap narrows
# everything this function widened, success or failure.
arch_limine_ensure_mount_writable() {
  local target=$1 options existing
  for existing in ${ARCH_LIMINE_REMOUNTED[@]+"${ARCH_LIMINE_REMOUNTED[@]}"}; do
    [[ ${existing} == "${target}" ]] && return 0
  done
  options="$(arch_limine_mount_field OPTIONS "${target}")" \
    || die "Unable to read mount options for ${target}."
  if [[ ,${options}, == *,ro,* ]]; then
    log_step "Temporarily remounting ${target} read-write"
    sudo mount --options remount,rw --target "${target}"
    ARCH_LIMINE_REMOUNTED+=("${target}")
  fi
}

# Count boot entries (lines opening a path block) so theming can prove it
# added zero and removed zero before replacing the file.
arch_limine_count_boot_entries() {
  grep -cE '^[[:space:]]*/' -- "$1" || true
}

# Apply the palette block to one config. Boot entries are preserved
# byte-for-byte; only appearance keys change. FAT-safe: stages beside the
# target (chmod is meaningless on vfat) and renames into place.
arch_limine_apply_appearance_to_config() {
  local config=$1 appearance=$2
  [[ ! -L ${config} ]] || die "Refusing to edit a linked bootloader config: ${config}"
  local mount_target before after body staged backup
  mount_target="$(arch_limine_mount_field TARGET "${config}")" \
    || die "Unable to identify the filesystem holding ${config}."
  arch_limine_ensure_mount_writable "${mount_target}"
  log_step "Applying the Limine palette (${config})"
  body="$(mktemp "${TMPDIR:-/tmp}/arch-limine-body.XXXXXX")" \
    || die "Cannot stage Limine theming for ${config}."
  staged="$(mktemp "${TMPDIR:-/tmp}/arch-limine-staged.XXXXXX")" \
    || { rm -f -- "${body}"; die "Cannot stage Limine theming for ${config}."; }
  # Only the read needs privilege; the redirect target is a user-owned temp.
  # shellcheck disable=SC2024
  sudo sed -n '1,$p' "${config}" >"${body}.src" \
    || { rm -f -- "${body}" "${body}.src" "${staged}"; die "Could not read ${config}."; }
  before="$(arch_limine_count_boot_entries "${body}.src")"
  awk -v begin="${ARCH_LIMINE_BEGIN_MARKER}" -v end="${ARCH_LIMINE_END_MARKER}" '
    $0 == begin { managed = 1; next }
    $0 == end { managed = 0; next }
    managed { next }
    tolower($0) ~ /^[[:space:]]*(wallpaper|wallpaper_style|backdrop|interface_branding|interface_branding_colou?r|interface_help_colou?r|interface_help_colou?r_bright|term_palette|term_palette_bright|term_background|term_background_bright|term_foreground|term_foreground_bright|term_margin|term_margin_gradient)[[:space:]]*:/ { next }
    !started && $0 ~ /^[[:space:]]*$/ { next }
    { started = 1; print }
  ' <"${body}.src" >"${body}"
  {
    printf '%s\n' "${ARCH_LIMINE_BEGIN_MARKER}"
    cat -- "${appearance}"
    printf '%s\n\n' "${ARCH_LIMINE_END_MARKER}"
    cat -- "${body}"
  } >"${staged}" \
    || { rm -f -- "${body}" "${body}.src" "${staged}"; die "Could not assemble the new ${config}."; }
  after="$(arch_limine_count_boot_entries "${staged}")"
  [[ ${before} == "${after}" ]] \
    || { rm -f -- "${body}" "${body}.src" "${staged}"; die "Boot entry count changed ${before} -> ${after}; ${config} untouched."; }
  if cmp -s -- "${staged}" "${body}.src"; then
    log_ok "${config} already carries the palette."
    rm -f -- "${body}" "${body}.src" "${staged}"
    return 0
  fi
  backup="${config}.dotfiles-backup"
  sudo test -e "${backup}" || { sudo cp --no-preserve=ownership,mode -- "${config}" "${backup}"; log_warn "Preserved ${config} as ${backup}."; }
  # Stage on the ESP itself so the rename never crosses filesystems.
  sudo cp --no-preserve=mode,ownership -- "${staged}" "${config}.dotfiles-new" \
    || { rm -f -- "${body}" "${body}.src" "${staged}"; die "Could not stage ${config}."; }
  sudo mv -f -- "${config}.dotfiles-new" "${config}" \
    || { rm -f -- "${body}" "${body}.src" "${staged}"; die "Could not replace ${config}."; }
  rm -f -- "${body}" "${body}.src" "${staged}"
  log_ok "Themed ${config} without touching ${after} boot entr(y/ies)."
}

# True when this ESP carries Microsoft's loader (same-drive dual boot).
# Case-insensitive search: vfat preserves case but FAT short names match
# either way, and Windows writes the canonical casing. No disk or PARTUUID
# is hardcoded; the caller passes the config's own ESP mount.
arch_limine_windows_loader_present() {
  local esp=$1 hit
  hit="$(sudo find "${esp}/EFI" "${esp}/efi" -maxdepth 4 -iname bootmgfw.efi -print -quit 2>/dev/null || true)"
  [[ -n ${hit} ]]
}

# Ensure one Windows chainload entry exists in this config when its ESP
# carries Microsoft's loader. Drive-independent boot():/... keeps it working
# without hardcoding this machine's disk layout. Idempotent: skips when the
# config already chainloads bootmgfw.efi under any title, and skips cleanly
# on single-boot ESPs. Entries are only appended, never removed or reordered.
# FAT-safe: stages beside the target and renames into place, like theming.
arch_limine_ensure_windows_entry() {
  local config=$1
  [[ ! -L ${config} ]] || die "Refusing to edit a linked bootloader config: ${config}"
  local mount_target body staged backup before after
  mount_target="$(arch_limine_mount_field TARGET "${config}")" \
    || die "Unable to identify the filesystem holding ${config}."
  arch_limine_ensure_mount_writable "${mount_target}"
  # Any existing chainload (whatever its title) owns the slot already.
  if sudo grep -qi -- bootmgfw.efi "${config}" 2>/dev/null; then
    log_ok "${config} already chainloads Windows."
    return 0
  fi
  arch_limine_windows_loader_present "${mount_target}" \
    || { log_info "No Windows loader on ${mount_target}; skipping the Windows entry."; return 0; }
  log_step "Adding the Windows entry (${config})"
  body="$(mktemp "${TMPDIR:-/tmp}/arch-limine-windows.XXXXXX")" \
    || die "Cannot stage the Windows entry for ${config}."
  staged="${body}.staged"
  # Only the read needs privilege; the redirect target is a user-owned temp.
  # shellcheck disable=SC2024
  sudo sed -n '1,$p' "${config}" >"${body}.src" \
    || { rm -f -- "${body}" "${body}.src" "${staged}"; die "Could not read ${config}."; }
  before="$(arch_limine_count_boot_entries "${body}.src")"
  cp -- "${body}.src" "${staged}" \
    || { rm -f -- "${body}" "${body}.src" "${staged}"; die "Could not assemble the new ${config}."; }
  # A leading blank line separates the appended entry from the previous one;
  # boot(): resolves to the ESP holding this config, so no disk is named.
  printf '\n/Windows\n    protocol: efi\n    path: boot():/EFI/Microsoft/Boot/bootmgfw.efi\n' >>"${staged}" \
    || { rm -f -- "${body}" "${body}.src" "${staged}"; die "Could not assemble the new ${config}."; }
  after="$(arch_limine_count_boot_entries "${staged}")"
  [[ ${after} == $((before + 1)) ]] \
    || { rm -f -- "${body}" "${body}.src" "${staged}"; die "Boot entry count changed ${before} -> ${after}; ${config} untouched."; }
  backup="${config}.dotfiles-backup"
  sudo test -e "${backup}" || { sudo cp --no-preserve=ownership,mode -- "${config}" "${backup}"; log_warn "Preserved ${config} as ${backup}."; }
  # Stage on the ESP itself so the rename never crosses filesystems.
  sudo cp --no-preserve=mode,ownership -- "${staged}" "${config}.dotfiles-new" \
    || { rm -f -- "${body}" "${body}.src" "${staged}"; die "Could not stage ${config}."; }
  sudo mv -f -- "${config}.dotfiles-new" "${config}" \
    || { rm -f -- "${body}" "${body}.src" "${staged}"; die "Could not replace ${config}."; }
  rm -f -- "${body}" "${body}.src" "${staged}"
  log_ok "Added the Windows entry to ${config}."
}

# Confirm an EFI binary identifies as Limine. EFI/BOOT holds the generic
# fallback name, which any bootloader may own, so the name alone proves little.
arch_limine_file_is_limine() {
  sudo grep -qa -- 'Limine' "$1" 2>/dev/null
}

# Locate the Limine EFI executable across mounted vfat filesystems and the
# directories beside known configs. Prefers a binary that names Limine;
# accepts a Limine-pathed fallback with a warning, never a stranger's loader.
arch_limine_find_loader() {
  local -a roots=() names=()
  case "$(uname -m)" in
    aarch64) names=(BOOTAA64.EFI limine_aa64.efi) ;;
    *)
      case "$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null)" in
        64) names=(BOOTX64.EFI limine_x64.efi) ;;
        32) names=(BOOTIA32.EFI limine_ia32.efi) ;;
        *) die 'Unsupported UEFI firmware bitness.' ;;
      esac
      ;;
  esac
  mapfile -t roots < <({ findmnt --noheadings --output TARGET --types vfat 2>/dev/null || true; printf '%s\n' "$@"; } | awk 'NF' | sort -u)
  local root dir name candidate fallback=''
  for root in ${roots[@]+"${roots[@]}"}; do
    for dir in "${root}" "${root}/EFI/limine" "${root}/EFI/arch-limine" "${root}/EFI/Limine" "${root}/EFI/BOOT"; do
      for name in "${names[@]}"; do
        candidate="${dir}/${name}"
        sudo test -f "${candidate}" 2>/dev/null || continue
        if arch_limine_file_is_limine "${candidate}"; then
          printf '%s\n' "${candidate}"
          return 0
        fi
        if [[ -z ${fallback} && (${dir,,} == *limine* || ${name,,} == limine_*) ]]; then
          fallback=${candidate}
        fi
      done
    done
  done
  if [[ -n ${fallback} ]]; then
    log_warn "No EFI binary self-identifies as Limine; trusting Limine-pathed ${fallback}."
    printf '%s\n' "${fallback}"
    return 0
  fi
  return 1
}

# Read one efibootmgr entry's loader path across old (File(...)) and current
# (bare )/\...) renderings. Empty when the release prints an unknown shape.
arch_limine_entry_path() {
  local path
  path="$(sed -n 's/.*[Ff]ile(\([^)]*\)).*/\1/p' <<<"$1")"
  [[ -n ${path} ]] || path="$(sed -n 's|.*)/\(\\[^[:space:]]*\).*|\1|p' <<<"$1")"
  printf '%s\n' "${path}"
}

# An entry's human label without the Boot#### prefix or device path (whose own
# directories may contain limine and would false-positive a whole-line match).
arch_limine_entry_label() {
  local label
  label="$(sed -E 's/^Boot[[:xdigit:]]{4}\*?[[:space:]]+//' <<<"$1")"
  label="${label%%$'\t'*}"
  label="${label%%HD(*}"
  label="${label%%PciRoot(*}"
  label="${label%%VenHw(*}"
  label="${label%%FvVol(*}"
  printf '%s\n' "${label%"${label##*[![:space:]]}"}"
}

# True when any listed entry yields a readable loader path. Releases that
# print an unknown shape leave every path empty; matching then falls back to
# label plus partition instead of failing the run or duplicating entries.
arch_limine_paths_readable() {
  local entry
  while IFS= read -r entry; do
    if [[ -n $(arch_limine_entry_path "${entry}") ]]; then
      return 0
    fi
  done <<<"$1"
  return 1
}

# True when one entry boots this loader under a Limine label on this
# partition. paths_readable is "true"/"false": when no path parses
# anywhere, label plus partition decide rather than the path.
arch_limine_entry_matches_loader() {
  local entry=$1 want=$2 partuuid=$3 paths_readable=$4 label path
  label="$(arch_limine_entry_label "${entry}")"
  [[ ${label} == *[Ll]imine* ]] || return 1
  [[ -z ${partuuid} || ${entry,,} == *"${partuuid}"* ]] || return 1
  [[ ${paths_readable} == true ]] || return 0
  path="$(arch_limine_entry_path "${entry}")"
  [[ -n ${path} ]] || return 1
  # Single-quoted backslash is tr's literal backslash set, not an escape.
  # shellcheck disable=SC1003
  [[ $(printf '%s' "${path}" | tr -s '\\' | tr '[:upper:]' '[:lower:]') == "${want}" ]]
}

# Echo the first entry booting this loader, else nothing (caller guards rc).
arch_limine_find_matching_entry() {
  local entries=$1 want=$2 partuuid=$3 paths_readable=$4 entry
  while IFS= read -r entry; do
    [[ ${entry} =~ ^Boot[0-9A-Fa-f]{4} ]] || continue
    if arch_limine_entry_matches_loader "${entry}" "${want}" "${partuuid}" "${paths_readable}"; then
      printf '%s\n' "${entry}"
      return 0
    fi
  done <<<"${entries}"
  return 1
}

# Echo the first Limine-labelled entry anywhere (any disk, any loader), else
# nothing. A Limine install elsewhere already owns a firmware menu slot.
arch_limine_find_labelled_entry() {
  local entry label
  while IFS= read -r entry; do
    [[ ${entry} =~ ^Boot[0-9A-Fa-f]{4} ]] || continue
    label="$(arch_limine_entry_label "${entry}")"
    if [[ ${label} == *[Ll]imine* ]]; then
      printf '%s\n' "${entry}"
      return 0
    fi
  done <<<"$1"
  return 1
}

# Theme all known configs, ensure the Windows dual-boot entry where this
# machine dual-boots, then ensure a named entry boots this loader.
# Skips cleanly with no config, on BIOS boot, or when the loader sits off
# vfat. Isolated in a subshell: the ESP-remount EXIT trap must never replace
# dot's cleanup_dot (sudo-refresher kill plus temp cleanup), which lives in
# the calling process; mount restoration fires on subshell exit instead.
arch_limine_setup() {
  ( arch_limine_setup_isolated )
}

arch_limine_setup_isolated() {
  trap arch_limine_restore_mounts EXIT
  local appearance
  appearance="$(arch_system_template_path 'limine/appearance.conf')"
  [[ -r ${appearance} ]] || die "Missing Limine appearance template: ${appearance}"
  sudo pacman -Syu --needed --noconfirm -- limine efibootmgr
  require_command findmnt
  require_command lsblk
  local -a candidates=(
    /boot/limine/limine.conf /boot/limine.conf
    /boot/EFI/limine/limine.conf /boot/EFI/arch-limine/limine.conf /boot/EFI/BOOT/limine.conf
    /boot/efi/limine/limine.conf /boot/efi/limine.conf
    /boot/efi/EFI/limine/limine.conf /boot/efi/EFI/arch-limine/limine.conf /boot/efi/EFI/BOOT/limine.conf
    /efi/limine/limine.conf /efi/limine.conf
    /efi/EFI/limine/limine.conf /efi/EFI/arch-limine/limine.conf /efi/EFI/BOOT/limine.conf
  )
  local -a configs=() config_dirs=()
  local candidate
  for candidate in "${candidates[@]}"; do
    if sudo test -f "${candidate}" 2>/dev/null; then
      configs+=("${candidate}")
      config_dirs+=("${candidate%/*}")
    fi
  done
  if ((${#configs[@]} == 0)); then
    log_warn 'No limine.conf in the usual places; theming skipped.'
    return 0
  fi
  for candidate in "${configs[@]}"; do
    arch_limine_apply_appearance_to_config "${candidate}" "${appearance}"
  done
  for candidate in "${configs[@]}"; do
    arch_limine_ensure_windows_entry "${candidate}"
  done
  if [[ ! -d /sys/firmware/efi ]]; then
    log_warn 'BIOS boot detected; firmware-entry registration skipped.'
    return 0
  fi
  require_command efibootmgr
  local loader esp_target fstype loader_path source disk part_no
  loader="$(arch_limine_find_loader "${config_dirs[@]}")" \
    || die 'Limine EFI executable not found beside a config or on vfat.'
  esp_target="$(arch_limine_mount_field TARGET "${loader}")" \
    || die "Unable to identify the filesystem holding ${loader}."
  fstype="$(arch_limine_mount_field FSTYPE "${esp_target}")" || fstype=''
  if [[ ${fstype} != vfat ]]; then
    log_warn "${loader} sits on ${fstype:-unknown}, not an ESP; firmware entries untouched."
    return 0
  fi
  loader_path="${loader#"${esp_target}"}"
  [[ ${loader_path} == /* ]] || loader_path="/${loader_path}"
  loader_path="${loader_path//\//\\}"
  source="$(arch_limine_mount_field SOURCE "${esp_target}")" \
    || die "Unable to read the device behind ${esp_target}."
  source="$(readlink -f -- "${source}")"
  [[ $(lsblk --noheadings --nodeps --output TYPE "${source}" 2>/dev/null | xargs) == part ]] \
    || die "Limine ESP source is not a disk partition: ${source}"
  disk="/dev/$(lsblk --noheadings --nodeps --output PKNAME "${source}" 2>/dev/null | xargs)"
  part_no="$(lsblk --noheadings --nodeps --output PARTN "${source}" 2>/dev/null | xargs)"
  [[ -n ${disk} && ${part_no} =~ ^[0-9]+$ ]] || die "Unable to derive disk/partition for ${source}."
  local entries want match labelled paths_readable partuuid
  entries="$(sudo efibootmgr -v)" || die 'Could not read firmware boot entries.'
  partuuid="$(lsblk --noheadings --nodeps --output PARTUUID "${source}" 2>/dev/null | xargs)"
  partuuid="${partuuid,,}"
  [[ -n ${partuuid} && ${entries,,} == *"${partuuid}"* ]] || partuuid=''
  # Same literal-backslash tr set as the matcher above.
  # shellcheck disable=SC1003
  want="$(printf '%s' "${loader_path}" | tr -s '\\' | tr '[:upper:]' '[:lower:]')"
  if arch_limine_paths_readable "${entries}"; then
    paths_readable=true
  else
    paths_readable=false
    log_warn 'This efibootmgr prints device paths in an unrecognised form; matching entries by label and partition.'
  fi
  match="$(arch_limine_find_matching_entry "${entries}" "${want}" "${partuuid}" "${paths_readable}")" || match=''
  if [[ -n ${match} ]]; then
    log_ok "Firmware entry \"$(arch_limine_entry_label "${match}")\" already boots ${loader_path}."
  else
    labelled="$(arch_limine_find_labelled_entry "${entries}")" || labelled=''
    if [[ -n ${labelled} ]]; then
      # A Limine install elsewhere (another disk, another loader name)
      # already owns a menu slot; a second entry would only reorder the menu.
      log_warn "Firmware entry \"$(arch_limine_entry_label "${labelled}")\" already names Limine ($(arch_limine_entry_path "${labelled}")); keeping it instead of adding a second one for ${loader_path}."
    else
      sudo efibootmgr --create --disk "${disk}" --part "${part_no}" --label Limine --loader "${loader_path}" --unicode \
        || die "efibootmgr could not create the Limine entry on ${disk} part ${part_no}."
      entries="$(sudo efibootmgr -v)" || die 'Could not re-read the firmware boot entries.'
      match="$(arch_limine_find_matching_entry "${entries}" "${want}" "${partuuid}" "${paths_readable}")" || match=''
      [[ -n ${match} ]] \
        || die "efibootmgr succeeded, but no entry boots ${loader_path}."
      log_ok "Created the Limine firmware entry on ${disk} part ${part_no}."
    fi
  fi
  log_ok 'Limine is themed, Windows is chainloaded where present, and registered; existing entries were kept.'
}

# Check Limine theming, the Windows dual-boot entry, and registration
# without changing anything. Unreadable /boot (no cached sudo) is reported,
# not treated as failure.
arch_limine_verify() {
  local failed=0 found=0 candidate windows_loader=0 esp_probe
  local -a reader=()
  sudo -n true >/dev/null 2>&1 && reader=(sudo -n)
  # Same-drive dual boot leaves Microsoft's loader on the ESP; when it is
  # readable, every readable config must chainload it.
  for esp_probe in /boot/EFI/Microsoft/Boot/bootmgfw.efi /boot/efi/EFI/Microsoft/Boot/bootmgfw.efi /efi/EFI/Microsoft/Boot/bootmgfw.efi; do
    if "${reader[@]+"${reader[@]}"}" test -f "${esp_probe}" 2>/dev/null; then
      windows_loader=1
      break
    fi
  done
  for candidate in /boot/limine/limine.conf /boot/limine.conf \
    /boot/EFI/limine/limine.conf /boot/EFI/arch-limine/limine.conf /boot/EFI/BOOT/limine.conf \
    /boot/efi/limine/limine.conf /boot/efi/limine.conf \
    /boot/efi/EFI/limine/limine.conf /boot/efi/EFI/arch-limine/limine.conf /boot/efi/EFI/BOOT/limine.conf \
    /efi/limine/limine.conf /efi/limine.conf \
    /efi/EFI/limine/limine.conf /efi/EFI/arch-limine/limine.conf /efi/EFI/BOOT/limine.conf; do
    "${reader[@]+"${reader[@]}"}" test -f "${candidate}" 2>/dev/null || continue
    found=1
    "${reader[@]+"${reader[@]}"}" grep -Fq "${ARCH_LIMINE_BEGIN_MARKER}" "${candidate}" 2>/dev/null \
      || { log_error "${candidate} lacks the palette block."; failed=1; }
    if ((windows_loader == 1)); then
      "${reader[@]+"${reader[@]}"}" grep -qi -- bootmgfw.efi "${candidate}" 2>/dev/null \
        || { log_error "${candidate} lacks a Windows chainload entry."; failed=1; }
    fi
  done
  ((found == 1)) || log_warn 'No readable limine.conf; rerun with cached sudo on an ESP-rooted boot.'
  if efibootmgr -v 2>/dev/null | grep -Eq '^[Bb]oot[0-9A-Fa-f]{4}[*]? +.*[Ll]imine'; then
    log_ok 'A Limine firmware entry exists.'
  else
    log_warn 'No Limine firmware entry visible; run ./dot arch-setup on the Arch machine.'
  fi
  return "${failed}"
}
