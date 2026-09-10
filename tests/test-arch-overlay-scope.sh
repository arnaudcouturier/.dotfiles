#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# Decided overlay scope (static, no execution): the home/ ∩ home-arch/
# collision set is exactly the Ghostty forwarding alias (shared stow skips
# aliases on every distro; each distro stows its own real copy); the Fedora
# tree ships both aliases as real files; the shared hypr/input.lua alias has
# overlay user override carrying equivalent kb_options; the overlay sets no
# unconditional NVIDIA environment and hardcodes no PCI IDs or identities.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox

SHARED="${TEST_ARCH_REPO_ROOT}/home"
OVERLAY="${TEST_ARCH_REPO_ROOT}/home-arch"
FEDORA_TREE="${TEST_ARCH_REPO_ROOT}/home-fedora"
[[ -d ${OVERLAY} ]] || { printf 'SEAM PENDING: home-arch/ overlay missing\n'; exit 3; }
[[ -d ${FEDORA_TREE} ]] || { printf 'SEAM PENDING: home-fedora/ overlay missing\n'; exit 3; }

failures=0
scope_fail() {
  printf 'SCOPE-VIOLATION: %s\n' "$*" >&2
  failures=$((failures + 1))
}

# --- Collision set: exactly the Ghostty config, nothing else. ---
comm -12 \
  <(cd -- "${SHARED}" && find . -mindepth 1 \( -type f -o -type l \) | sort) \
  <(cd -- "${OVERLAY}" && find . -mindepth 1 \( -type f -o -type l \) | sort) \
  >"${TEST_ARCH_SANDBOX}/collisions.txt"
expected='./.config/ghostty/config'
actual="$(cat -- "${TEST_ARCH_SANDBOX}/collisions.txt")"
[[ ${actual} == "${expected}" ]] \
  || scope_fail "collision set is <${actual:-empty}>, decided exactly <${expected}> (dot exclusion must cover it)"
# The collision is real: overlay and shared Ghostty configs differ.
if cmp -s -- "${SHARED}/.config/ghostty/config" "${OVERLAY}/.config/ghostty/config"; then
  scope_fail 'overlay Ghostty config is identical to shared; exclusion would be pointless'
fi

# --- home-fedora/ ships both aliases as real files, never aliases. ---
for fedora_rel in .config/ghostty/config .config/hypr/input.lua; do
  [[ -f ${FEDORA_TREE}/${fedora_rel} && ! -L ${FEDORA_TREE}/${fedora_rel} ]] \
    || scope_fail "home-fedora/${fedora_rel} is not a real file"
done

# --- kb_options lives in the overlay user override: Caelestia owns the ---
# --- generated tree, so the overlay must not ship a conflicting file. ---
if [[ -f ${SHARED}/.config/hypr/input.lua ]]; then
  shared_kb="$(grep -o 'kb_options = "[^"]*"' "${SHARED}/.config/hypr/input.lua" | head -n1)"
  overlay_kb="$(grep -o 'kb_options = "[^"]*"' "${OVERLAY}/.config/caelestia/hypr-user.lua" | head -n1)"
  [[ -n ${overlay_kb} ]] \
    || scope_fail 'overlay hypr-user.lua lacks the kb_options equivalent of shared hypr/input.lua (decided: option lives in the loaded user override)'
  [[ ${shared_kb} == "${overlay_kb}" ]] \
    || scope_fail "overlay kb_options <${overlay_kb:-missing}> diverges from shared <${shared_kb}>"
fi
if [[ -d ${OVERLAY}/.config/hypr ]] && find "${OVERLAY}/.config/hypr" -type f -print -quit 2>/dev/null | grep -q .; then
  scope_fail 'home-arch/.config/hypr/ ships files that would conflict with the Caelestia-generated tree (decided: upstream owns it, overlay stays out)'
fi

# --- NVIDIA environment, if set at all, must be probe-gated: non-comment ---
# --- LIBVA/NVD lines require a runtime GPU probe in the same file. ---
if sed 's/--.*//; s/#.*//' "${OVERLAY}/.config/caelestia/hypr-user.lua" 2>/dev/null \
  | grep -qE 'LIBVA_DRIVER_NAME|NVD_BACKEND'; then
  grep -rE '/sys/module/nvidia|lspci' "${OVERLAY}/.config/caelestia/hypr-user.lua" >/dev/null \
    || scope_fail 'overlay sets NVIDIA video environment without a runtime GPU probe (decided: probe-gated or unset)'
fi

# --- Editor target is the kept Neovim inside ghostty, never an excluded app. ---
grep -q 'editor.*=.*"ghostty -e nvim"' "${OVERLAY}/.config/caelestia/hypr-vars.lua" \
  || scope_fail 'overlay editor is not the kept ghostty+Neovim target'
if sed 's/--.*//' "${OVERLAY}/.config/caelestia/hypr-vars.lua" | grep -qw -e code -e vscodium -e vscode; then
  scope_fail 'overlay editor references an excluded editor app'
fi
[[ ! -e ${OVERLAY}/.config/nvim ]] \
  || scope_fail 'overlay ships nvim config (decided: shared LazyVim tree owns it; installer nvim component is additive)'
[[ -d ${SHARED}/.config/nvim ]] \
  || scope_fail 'shared nvim config missing (overlay editor depends on it)'

# --- No hardcoded machine identity anywhere in the overlay. ---
if grep -rn -E '[0-9a-fA-F]{4}:[0-9a-fA-F]{4}' "${OVERLAY}" 2>/dev/null; then
  scope_fail 'overlay hardcodes PCI IDs'
fi
if grep -rn -i 'arnaudc\|arenwald' "${OVERLAY}" 2>/dev/null; then
  scope_fail 'overlay hardcodes user identity'
fi

if ((failures > 0)); then
  printf '%d overlay-scope violation(s).\n' "${failures}" >&2
  exit 1
fi
printf 'Overlay scope matches the decided exclusions and conditionals.\n'
