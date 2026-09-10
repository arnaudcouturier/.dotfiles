#!/usr/bin/env bash
# lib/arch-gpu.sh — conditional Arch graphics drivers and CPU microcode.
#
# Detects every display GPU (hybrid machines get every matching stack) plus
# CPU microcode, then installs through pacman and yay. WORKSTATION_GPU
# overrides detection for testing (amd, intel, nvidia, none). Desktop
# environment variables for video decoding belong to the home overlay, never
# here, so non-NVIDIA machines never inherit NVIDIA settings.

set -euo pipefail

# List one detected GPU vendor per line (amd, intel, nvidia). Honors
# WORKSTATION_GPU when set; otherwise reads display PCI devices via lspci.
arch_gpu_detect_vendors() {
  if [[ -n ${WORKSTATION_GPU:-} ]]; then
    case "${WORKSTATION_GPU}" in
      amd | intel | nvidia) printf '%s\n' "${WORKSTATION_GPU}" ;;
      none) return 0 ;;
      *) die "Invalid WORKSTATION_GPU '${WORKSTATION_GPU}'. Use amd, intel, nvidia, or none." ;;
    esac
    return 0
  fi
  require_command lspci
  local devices
  devices="$(lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' || true)"
  [[ -n ${devices} ]] || return 0
  grep -Eqi 'Advanced Micro Devices|AMD/ATI|\[1002:' <<<"${devices}" && printf 'amd\n'
  grep -Eqi '\bIntel\b|\[8086:' <<<"${devices}" && printf 'intel\n'
  grep -Eqi 'NVIDIA|\[10de:' <<<"${devices}" && printf 'nvidia\n'
  return 0
}

# NVIDIA display IDs needing the proprietary 580xx module, vendored beside
# this module (deterministic vendor data with a freshness rule in its header).
ARCH_NVIDIA_LEGACY_PCIIDS_FILE=''
ARCH_NVIDIA_LEGACY_PCIIDS_FILE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/arch-nvidia-legacy-pciids.txt"
readonly ARCH_NVIDIA_LEGACY_PCIIDS_FILE

# List NVIDIA display-controller PCI IDs (numeric lspci: class 03, vendor
# 10de), lowercase and unique. Audio functions never match the class filter.
arch_nvidia_display_pci_ids() {
  require_command lspci
  lspci -n 2>/dev/null \
    | awk '$2 ~ /^03/ && tolower($3) ~ /^10de:/ { print tolower($3) }' \
    | sort -u
}

# Classify NVIDIA display IDs: proprietary when any ID needs the closed 580xx
# module, unsupported when an ID predates that branch (open modules need
# Turing+, device 0x1e00+), open otherwise. Proprietary wins ties, matching
# the archive semantics this adapts.
arch_nvidia_module_flavor_for_ids() {
  (($# > 0)) || return 1
  [[ -r ${ARCH_NVIDIA_LEGACY_PCIIDS_FILE} ]] \
    || die "Missing NVIDIA PCI-ID data: ${ARCH_NVIDIA_LEGACY_PCIIDS_FILE}"
  local id device
  for id in "$@"; do
    if grep -Fxiq -- "${id}" "${ARCH_NVIDIA_LEGACY_PCIIDS_FILE}"; then
      printf '%s\n' proprietary
      return 0
    fi
    device=${id#*:}
    if [[ ${device} =~ ^[[:xdigit:]]{4}$ ]] && ((16#${device} < 0x1e00)); then
      printf '%s\n' unsupported
      return 0
    fi
  done
  printf '%s\n' open
}

# Install microcode plus every detected vendor stack. NVIDIA flavor
# (open/DKMS vs 580xx AUR vs unsupported) classifies every display ID before
# any package write, so legacy and ancient cards fail loudly instead of
# receiving Turing-only modules. Regenerates initramfs when mkinitcpio exists.
arch_gpu_setup_drivers() {
  local -a vendors=() pkgs=() aur_pkgs=() kernels=()
  # Capture, then check: mapfile over a process substitution would mask a
  # dying detector under set -e and provision microcode-only in silence.
  local vendors_text vendors_rc=0
  vendors_text="$(arch_gpu_detect_vendors)" || vendors_rc=$?
  ((vendors_rc == 0)) || die 'GPU detection failed; refusing to guess driver stacks.'
  local detected_vendor
  while IFS= read -r detected_vendor; do
    [[ -n ${detected_vendor} ]] || continue
    vendors+=("${detected_vendor}")
  done <<<"${vendors_text}"
  local cpu_vendor
  cpu_vendor="$(awk -F: '/^[[:space:]]*vendor_id[[:space:]]*:/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' /proc/cpuinfo)"
  case "${cpu_vendor}" in
    AuthenticAMD) pkgs+=(amd-ucode) ;;
    GenuineIntel) pkgs+=(intel-ucode) ;;
    *) log_warn "Unknown CPU vendor '${cpu_vendor:-missing}'; install microcode manually." ;;
  esac
  local vendor kernel
  for vendor in ${vendors[@]+"${vendors[@]}"}; do
    case "${vendor}" in
      amd) pkgs+=(mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon) ;;
      intel) pkgs+=(mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver) ;;
      nvidia)
        local use_dkms=false supported=false
        for kernel in linux linux-lts linux-zen linux-hardened; do
          if pacman -Q "${kernel}" >/dev/null 2>&1; then
            kernels+=("${kernel}")
            supported=true
            [[ ${kernel} == linux-zen || ${kernel} == linux-hardened ]] && use_dkms=true
          fi
        done
        [[ ${supported} == true ]] \
          || die 'No supported Arch kernel found. Install linux, linux-lts, linux-zen, or linux-hardened first.'
        # Classify every display ID before any package write: unsupported
        # (pre-Maxwell, older than the 580xx branch) dies here with the IDs,
        # never after pacman already ran.
        local -a nvidia_id_list=()
        local nvidia_ids nvidia_id nvidia_flavor nvidia_rc=0
        nvidia_ids="$(arch_nvidia_display_pci_ids)"
        while IFS= read -r nvidia_id; do
          [[ -n ${nvidia_id} ]] || continue
          nvidia_id_list+=("${nvidia_id}")
        done <<<"${nvidia_ids}"
        ((${#nvidia_id_list[@]} > 0)) \
          || die 'NVIDIA was detected but no display PCI ID could be read.'
        nvidia_flavor="$(arch_nvidia_module_flavor_for_ids "${nvidia_id_list[@]}")" || nvidia_rc=$?
        ((nvidia_rc == 0)) && [[ -n ${nvidia_flavor} ]] \
          || die 'Could not classify the NVIDIA display IDs; refusing to guess driver stacks.'
        case "${nvidia_flavor}" in
          unsupported)
            die "NVIDIA PCI IDs need a legacy branch older than 580xx: $(paste -sd, <<<"$(printf '%s\n' "${nvidia_id_list[@]}")"). No packaged driver covers them; select one manually."
            ;;
          proprietary)
            require_command yay
            log_warn 'AUR packages are user-produced. Review the PKGBUILDs shown by yay before approving.'
            aur_pkgs+=(nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils)
            for kernel in "${kernels[@]}"; do pkgs+=("${kernel}-headers"); done
            ;;
          open)
            if [[ ${use_dkms} == true ]]; then
              pkgs+=(nvidia-open-dkms)
              for kernel in "${kernels[@]}"; do pkgs+=("${kernel}-headers"); done
            else
              for kernel in "${kernels[@]}"; do
                case "${kernel}" in
                  linux) pkgs+=(nvidia-open) ;;
                  linux-lts) pkgs+=(nvidia-open-lts) ;;
                esac
              done
            fi
            ;;
        esac
        pkgs+=(libva-nvidia-driver)
        ;;
    esac
  done
  if ((${#vendors[@]} > 0)); then
    pkgs+=(mesa-utils vulkan-tools libva-utils)
    log_info "Installing driver stacks for: ${vendors[*]}."
  else
    log_warn 'No GPU detected; installing CPU microcode only.'
  fi
  if ((${#pkgs[@]} > 0)); then
    # -Syu, not -S: Arch forbids installing into a partially upgraded system.
    sudo pacman -Syu --needed --noconfirm -- "${pkgs[@]}"
  fi
  if ((${#aur_pkgs[@]} > 0)); then
    require_command yay
    log_warn 'AUR packages are user-produced. Review the PKGBUILDs shown by yay before approving.'
    yay -S --aur --needed -- "${aur_pkgs[@]}"
  fi
  command -v mkinitcpio >/dev/null 2>&1 && sudo mkinitcpio -P || true
  log_ok 'Arch graphics drivers and microcode are installed. Reboot before judging driver health.'
}

# Check installed graphics packages without changing anything. Machine-local
# health (nvidia-smi, BAR sizes, modeset) stays a manual step, not a probe.
arch_gpu_verify() {
  local failed=0
  local -a vendors=()
  # Same capture-then-check as setup: a masked detector must fail the check,
  # never read as GPU-less.
  local vendors_text vendors_rc=0 detected_vendor
  vendors_text="$(arch_gpu_detect_vendors)" || vendors_rc=$?
  ((vendors_rc == 0)) || { log_error 'GPU detection failed.'; return 1; }
  while IFS= read -r detected_vendor; do
    [[ -n ${detected_vendor} ]] || continue
    vendors+=("${detected_vendor}")
  done <<<"${vendors_text}"
  # Microcode ships with the driver step; a missing package is drift to fix.
  local cpu_vendor
  cpu_vendor="$(awk -F: '/^[[:space:]]*vendor_id[[:space:]]*:/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' /proc/cpuinfo)"
  case "${cpu_vendor}" in
    AuthenticAMD)
      pacman -Q -- amd-ucode >/dev/null 2>&1 || { log_error 'Missing amd-ucode. Run ./dot arch-setup.'; failed=1; }
      ;;
    GenuineIntel)
      pacman -Q -- intel-ucode >/dev/null 2>&1 || { log_error 'Missing intel-ucode. Run ./dot arch-setup.'; failed=1; }
      ;;
  esac
  local pkg
  for pkg in mesa-utils vulkan-tools libva-utils; do
    ((${#vendors[@]} == 0)) && break
    pacman -Q -- "${pkg}" >/dev/null 2>&1 || { log_error "Missing ${pkg}. Run ./dot arch-setup."; failed=1; }
  done
  local vendor
  for vendor in ${vendors[@]+"${vendors[@]}"}; do
    case "${vendor}" in
      amd)
        for pkg in mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon; do
          pacman -Q -- "${pkg}" >/dev/null 2>&1 || { log_error "Missing ${pkg}."; failed=1; }
        done
        ;;
      intel)
        for pkg in mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver; do
          pacman -Q -- "${pkg}" >/dev/null 2>&1 || { log_error "Missing ${pkg}."; failed=1; }
        done
        ;;
      nvidia)
        pacman -Q nvidia-open nvidia-open-lts nvidia-open-dkms nvidia-580xx-dkms 2>/dev/null | grep -q . \
          || { log_error 'No NVIDIA kernel module package found.'; failed=1; }
        pacman -Q -- libva-nvidia-driver >/dev/null 2>&1 || { log_error 'Missing libva-nvidia-driver.'; failed=1; }
        ;;
    esac
  done
  return "${failed}"
}
