#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# arch_gpu_detect_vendors / arch_gpu_setup_drivers (lib/arch-gpu.sh):
# WORKSTATION_GPU override matrix, lspci fixture detection (including
# hybrid and audio-only), and per-branch install plans. pacman, yay, and
# sudo are logging stubs; the live package database is never consulted.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-gpu.sh"

test_arch_make_sandbox

# Scripted pacman: -Q succeeds only for packages in TEST_PACMAN_INSTALLED.
cat >"${TEST_ARCH_BIN}/pacman" <<EOF
#!/usr/bin/env bash
printf 'pacman %s\n' "\$*" >>"$(test_arch_calls_log)"
[[ \$1 == -Q ]] || exit 0
shift
[[ \$1 == -- ]] && shift
for pkg in "\$@"; do
  case " \${TEST_PACMAN_INSTALLED:-} " in
    *" \${pkg} "*) ;;
    *) exit 1 ;;
  esac
done
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/pacman"

# Logging sudo/yay/mkinitcpio probes: yay runs (expected on legacy paths),
# mkinitcpio is only probed via command -v; sudo records without executing.
test_arch_stub_command mkinitcpio
# sudo must succeed so planning reaches the install calls.
cat >"${TEST_ARCH_BIN}/sudo" <<EOF
#!/usr/bin/env bash
printf 'sudo %s\n' "\$*" >>"$(test_arch_calls_log)"
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/sudo"
# yay succeeds: legacy paths are expected to reach the AUR review/install.
cat >"${TEST_ARCH_BIN}/yay" <<EOF
#!/usr/bin/env bash
printf 'yay %s\n' "\$*" >>"$(test_arch_calls_log)"
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/yay"

# --- WORKSTATION_GPU override matrix (no lspci involved). ---
test_arch_assert_eq 'amd' "$(WORKSTATION_GPU=amd arch_gpu_detect_vendors)" 'override amd'
test_arch_assert_eq '' "$(WORKSTATION_GPU=none arch_gpu_detect_vendors)" 'override none detects nothing'
set +e
( WORKSTATION_GPU=bogus arch_gpu_detect_vendors >/dev/null 2>&1 )
override_status=$?
set -e
((override_status != 0)) || test_arch_die 'bogus WORKSTATION_GPU accepted'

# Dual-format lspci stub: -nn named output for detection, -n numeric
# output for display-ID extraction (class 03, vendor:device in $3).
set_lspci() {
  local nn_file=$1 n_file=$2 log
  log="$(test_arch_calls_log)"
  cat >"${TEST_ARCH_BIN}/lspci" <<EOF
#!/usr/bin/env bash
printf 'lspci %s\n' "\$*" >>"${log}"
if [[ " \$* " == *' -nn '* ]]; then
  cat -- "${nn_file}"
else
  cat -- "${n_file}"
fi
EOF
  chmod 755 -- "${TEST_ARCH_BIN}/lspci"
}

# --- lspci fixtures: hybrid, single, and audio-only (no display). ---
cat >"${TEST_ARCH_SANDBOX}/lspci-hybrid.txt" <<'EOF'
00:02.0 VGA compatible controller [0300]: Intel Corporation HD Graphics 630 [8086:5912]
01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP106M [10de:1e84]
01:00.1 Audio device [0403]: NVIDIA Corporation GP106 High Definition Audio Controller [10de:10f1]
EOF
cat >"${TEST_ARCH_SANDBOX}/lspci-intel.txt" <<'EOF'
00:02.0 VGA compatible controller [0300]: Intel Corporation HD Graphics 630 [8086:5912]
EOF
cat >"${TEST_ARCH_SANDBOX}/lspci-audio-only.txt" <<'EOF'
01:00.1 Audio device [0403]: NVIDIA Corporation GP106 High Definition Audio Controller [10de:10f1]
EOF
# Numeric (-n) twins for display-ID extraction: slot, class, vendor:device.
cat >"${TEST_ARCH_SANDBOX}/lspci-hybrid-n.txt" <<'EOF'
00:02.0 0300: 8086:5912
01:00.0 0300: 10de:1e84
01:00.1 0403: 10de:10f1
EOF
cat >"${TEST_ARCH_SANDBOX}/lspci-intel-n.txt" <<'EOF'
00:02.0 0300: 8086:5912
EOF
cat >"${TEST_ARCH_SANDBOX}/lspci-audio-only-n.txt" <<'EOF'
01:00.1 0403: 10de:10f1
EOF
cat >"${TEST_ARCH_SANDBOX}/lspci-legacy-n.txt" <<'EOF'
01:00.0 0300: 10de:139a
EOF
cat >"${TEST_ARCH_SANDBOX}/lspci-pascal-n.txt" <<'EOF'
01:00.0 0300: 10de:1b80
EOF
cat >"${TEST_ARCH_SANDBOX}/lspci-kepler-n.txt" <<'EOF'
01:00.0 0300: 10de:1180
EOF
set_lspci "${TEST_ARCH_SANDBOX}/lspci-hybrid.txt" "${TEST_ARCH_SANDBOX}/lspci-hybrid-n.txt"
mapfile -t hybrid < <(arch_gpu_detect_vendors)
test_arch_assert_eq 2 "${#hybrid[@]}" 'hybrid laptop detects two vendors'
set_lspci "${TEST_ARCH_SANDBOX}/lspci-intel.txt" "${TEST_ARCH_SANDBOX}/lspci-intel-n.txt"
test_arch_assert_eq 'intel' "$(arch_gpu_detect_vendors)" 'single Intel iGPU detected'
set_lspci "${TEST_ARCH_SANDBOX}/lspci-audio-only.txt" "${TEST_ARCH_SANDBOX}/lspci-audio-only-n.txt"
test_arch_assert_eq '' "$(arch_gpu_detect_vendors)" 'audio function alone detects no GPU'

# Host microcode expectation, derived independently from /proc/cpuinfo.
if grep -q AuthenticAMD /proc/cpuinfo; then EXPECTED_UCODE=amd-ucode; else EXPECTED_UCODE=intel-ucode; fi

# --- Intel setup: Mesa stack plus host microcode, never the AUR. ---
unset WORKSTATION_GPU
export WORKSTATION_GPU=intel TEST_PACMAN_INSTALLED=''
: >"$(test_arch_calls_log)"
arch_gpu_setup_drivers >/dev/null
test_arch_assert_contains "$(test_arch_calls_log)" "sudo pacman -Syu --needed --noconfirm -- ${EXPECTED_UCODE} mesa lib32-mesa vulkan-intel" \
  'Intel stack planned with host microcode'
test_arch_assert_not_called yay 'Intel setup never reaches the AUR'

# --- NVIDIA Turing on linux: open modules plus headers. ---
export WORKSTATION_GPU=nvidia TEST_PACMAN_INSTALLED='linux'
set_lspci "${TEST_ARCH_SANDBOX}/lspci-hybrid.txt" "${TEST_ARCH_SANDBOX}/lspci-hybrid-n.txt"
: >"$(test_arch_calls_log)"
arch_gpu_setup_drivers >/dev/null
test_arch_assert_contains "$(test_arch_calls_log)" 'nvidia-open' 'Turing takes the open modules'
# Prebuilt open modules need no headers; only DKMS builds do.
if grep -q 'linux-headers' "$(test_arch_calls_log)"; then
  test_arch_die 'prebuilt open modules planned unneeded headers'
fi
test_arch_assert_contains "$(test_arch_calls_log)" 'libva-nvidia-driver' 'NVDEC front end planned'
if grep -q 'nvidia-580xx' "$(test_arch_calls_log)"; then
  test_arch_die 'Turing planned the legacy proprietary branch'
fi
test_arch_assert_not_called yay 'open modules never reach the AUR'

# --- linux-zen takes the DKMS variant with matching headers. ---
export TEST_PACMAN_INSTALLED='linux-zen'
: >"$(test_arch_calls_log)"
arch_gpu_setup_drivers >/dev/null
test_arch_assert_contains "$(test_arch_calls_log)" 'nvidia-open-dkms' 'zen takes the DKMS modules'
test_arch_assert_contains "$(test_arch_calls_log)" 'linux-zen-headers' 'DKMS build plans matching headers'

# --- Legacy Maxwell/Pascal ID: proprietary AUR branch with a review warning. ---
cat >"${TEST_ARCH_SANDBOX}/lspci-legacy.txt" <<'EOF'
01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GM107M [GeForce GTX 860M] [10de:139A]
EOF
set_lspci "${TEST_ARCH_SANDBOX}/lspci-legacy.txt" "${TEST_ARCH_SANDBOX}/lspci-legacy-n.txt"
: >"$(test_arch_calls_log)"
legacy_out="$(arch_gpu_setup_drivers 2>&1)"
printf '%s\n' "${legacy_out}" >"${TEST_ARCH_SANDBOX}/legacy.txt"
test_arch_assert_contains "$(test_arch_calls_log)" 'yay -S --aur --needed -- nvidia-580xx-dkms' \
  'legacy Maxwell ID takes the proprietary AUR branch'
test_arch_assert_contains "${TEST_ARCH_SANDBOX}/legacy.txt" 'user-produced' 'AUR review warning shown'

# --- H1: Pascal (pre-Turing, e.g. GTX 1080) is legacy too, never open. ---
cat >"${TEST_ARCH_SANDBOX}/lspci-pascal.txt" <<'EOF'
01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP104 [GeForce GTX 1080] [10de:1B80]
EOF
set_lspci "${TEST_ARCH_SANDBOX}/lspci-pascal.txt" "${TEST_ARCH_SANDBOX}/lspci-pascal-n.txt"
: >"$(test_arch_calls_log)"
arch_gpu_setup_drivers >/dev/null
test_arch_assert_contains "$(test_arch_calls_log)" 'nvidia-580xx-dkms' \
  'Pascal ID takes the proprietary AUR branch'
if grep -- 'sudo pacman' "$(test_arch_calls_log)" | grep -qw 'nvidia-open'; then
  test_arch_die 'Pascal planned nvidia-open, which supports Turing+ only (H1)'
fi

# --- H1: Kepler and older have no packaged branch and must die naming IDs. ---
cat >"${TEST_ARCH_SANDBOX}/lspci-kepler.txt" <<'EOF'
01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GK104 [GeForce GTX 680] [10de:1180]
EOF
set_lspci "${TEST_ARCH_SANDBOX}/lspci-kepler.txt" "${TEST_ARCH_SANDBOX}/lspci-kepler-n.txt"
: >"$(test_arch_calls_log)"
set +e
kepler_out="$(arch_gpu_setup_drivers 2>&1)"
kepler_status=$?
set -e
((kepler_status != 0)) || test_arch_die 'Kepler ID provisioned silently (H1: no packaged driver exists)'
printf '%s\n' "${kepler_out}" >"${TEST_ARCH_SANDBOX}/kepler.txt"
test_arch_assert_contains "${TEST_ARCH_SANDBOX}/kepler.txt" '1180' 'unsupported refusal names the PCI ID'
test_arch_assert_not_called sudo 'unsupported GPU installs nothing'

# --- NVIDIA without a supported kernel: refuse before installing anything. ---
export TEST_PACMAN_INSTALLED=''
: >"$(test_arch_calls_log)"
set +e
( arch_gpu_setup_drivers >/dev/null 2>&1 )
kernel_status=$?
set -e
((kernel_status != 0)) || test_arch_die 'kernel-less NVIDIA setup proceeded'
test_arch_assert_not_called sudo 'kernel-less setup installs nothing'

# --- H2: bogus WORKSTATION_GPU dies through setup, not microcode-only. ---
export WORKSTATION_GPU=bogus TEST_PACMAN_INSTALLED=''
: >"$(test_arch_calls_log)"
set +e
( arch_gpu_setup_drivers >/dev/null 2>&1 )
setup_bogus_status=$?
set -e
((setup_bogus_status != 0)) || test_arch_die 'H2: bogus WORKSTATION_GPU provisioned silently through setup'
test_arch_assert_not_called sudo 'H2: bogus GPU installs nothing'

# --- H2: bogus WORKSTATION_GPU dies through verify, not a silent pass. ---
set +e
( arch_gpu_verify >/dev/null 2>&1 )
verify_bogus_status=$?
set -e
((verify_bogus_status != 0)) || test_arch_die 'H2: bogus WORKSTATION_GPU verified silently'
unset WORKSTATION_GPU

# --- No GPU: microcode only, never Mesa. ---
export WORKSTATION_GPU=none TEST_PACMAN_INSTALLED=''
: >"$(test_arch_calls_log)"
arch_gpu_setup_drivers >/dev/null
if grep -q 'mesa' "$(test_arch_calls_log)"; then
  test_arch_die 'GPU-less setup planned graphics packages'
fi
test_arch_assert_contains "$(test_arch_calls_log)" "${EXPECTED_UCODE}" 'GPU-less setup still plans microcode'

test_arch_assert_no_live_paths 'gpu planning'
printf 'GPU detection and driver plans stay conditional per vendor.\n'
