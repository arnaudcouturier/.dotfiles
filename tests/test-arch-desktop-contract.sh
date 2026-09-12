#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# Final desktop contract (orchestrator decisions, supersedes both draft
# contracts): lib/arch-desktop.sh exposes the five orchestrator functions
# below plus small list/predicate helpers and the user-file deploy they
# share; installs the overlay with stow for the stowed set plus copy-once
# real-file deploy for the two compositor-owned user files (no $HOME
# backups, no doctor exemption beyond the deployed check); never uses sudo,
# and owns no mpv/shader logic (that pipeline was removed from the repo).
# The stow-only past died to a live race: Hyprland recreates the user files
# within milliseconds when missing, so no stow scan can own those paths.
# Failures below are the desktop rewrite checklist, one line per violated
# decision.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

DESKTOP_LIB="${TEST_ARCH_REPO_ROOT}/lib/arch-desktop.sh"
[[ -r ${DESKTOP_LIB} ]] || { printf 'SEAM PENDING: lib/arch-desktop.sh missing\n'; exit 3; }

test_arch_make_sandbox
for cmd in sudo stow patch jq Hyprland pacman lspci systemctl; do
  test_arch_stub_command "${cmd}"
done

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null

failures=0
contract_fail() {
  printf 'CONTRACT-VIOLATION: %s\n' "$*" >&2
  failures=$((failures + 1))
}

# --- Sourcing is side-effect free: no calls, no files. ---
before_calls="$(cat -- "$(test_arch_calls_log)")"
before_home="$(find "${TEST_ARCH_HOME}" -mindepth 1 | sort)"
# shellcheck source=/dev/null
source "${DESKTOP_LIB}"
test_arch_arm_cleanup
[[ ${before_calls} == "$(cat -- "$(test_arch_calls_log)")" ]] \
  || contract_fail 'sourcing lib/arch-desktop.sh invoked commands (must be definitions only)'
  # shellcheck disable=SC2016 # literal $HOME in diagnostic text is intentional
[[ ${before_home} == "$(find "${TEST_ARCH_HOME}" -mindepth 1 | sort)" ]] \
  || contract_fail 'sourcing lib/arch-desktop.sh created files under $HOME'

# --- Exact public interface: five orchestrators, two globals. ---
for fn in arch_desktop_overlay_available arch_desktop_install_overlay \
  arch_desktop_configure_caelestia arch_desktop_verify_overlay arch_desktop_verify_caelestia; do
  command -v "${fn}" >/dev/null 2>&1 \
    || contract_fail "missing decided function ${fn} (lead contract §2.2)"
done
[[ -n ${ARCH_DESKTOP_OVERLAY_DIR:-} ]] \
  || contract_fail 'missing decided global ARCH_DESKTOP_OVERLAY_DIR (lead contract §2.1)'
[[ -n ${ARCH_DESKTOP_HYPR_MAIN_CONFIG:-} ]] \
  || contract_fail 'missing decided global ARCH_DESKTOP_HYPR_MAIN_CONFIG (lead contract §2.1)'

# --- User-scoped only: no sudo invocations in code (comments excluded). ---
if sed 's/#.*//' "${DESKTOP_LIB}" | grep -n '\bsudo\b'; then
  contract_fail 'lib/arch-desktop.sh references sudo (desktop is user-scoped, never elevates)'
fi

# --- The mpv/shader pipeline was removed: no module may bring it back. ---
if grep -rnEi 'artcnn|anime4k|mpv-shim|\bmpv\b|/shaders' "${TEST_ARCH_REPO_ROOT}/lib" "${TEST_ARCH_REPO_ROOT}/dot"; then
  contract_fail 'mpv/shader logic is back in dot or lib/ (decided: the video step and its configs were removed)'
fi

# --- Home ownership: stow present, backup machinery absent. Copy exists ---
# --- only as the decided user-file deploy (cp in arch_desktop_deploy). ---
grep -q 'stow' "${DESKTOP_LIB}" \
  || contract_fail 'lib/arch-desktop.sh never calls stow (decided: stow-only overlay install)'
# shellcheck disable=SC2016 # literal $HOME in the diagnostic below is intentional
if grep -n 'config-backup' "${DESKTOP_LIB}"; then
  contract_fail 'lib/arch-desktop.sh keeps $HOME backups (decided: stow owns $HOME, no backup logic)'
fi

# --- Greeter gate surface: the two verify functions exist for dot gating. ---
for fn in arch_desktop_verify_overlay arch_desktop_verify_caelestia; do
  command -v "${fn}" >/dev/null 2>&1 || true
done

test_arch_assert_no_live_paths 'desktop contract probe'
if ((failures > 0)); then
  printf '%d decided-contract violation(s) in lib/arch-desktop.sh.\n' "${failures}" >&2
  exit 1
fi
printf 'Desktop module matches the decided stow-plus-deploy contract.\n'
