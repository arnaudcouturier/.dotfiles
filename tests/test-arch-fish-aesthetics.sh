#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# Arch fish aesthetics (additive only): overlay carries the Caelestia terminal
# look without shadowing shared home/ or touching Fedora. Covers loading
# order (conf.d before config.fish), interactive-only silence, Fedora
# unaffected, startup features preserved, night light off, no wallpaper
# routine, and a commented-only monitor example.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox
test_arch_stub_command sudo

SHARED="${TEST_ARCH_REPO_ROOT}/home"
OVERLAY="${TEST_ARCH_REPO_ROOT}/home-arch"
FEDORA_TREE="${TEST_ARCH_REPO_ROOT}/home-fedora"

# --- Additive only: collision set stays exactly the Ghostty alias. ---
comm -12 \
  <(cd -- "${SHARED}" && find . -mindepth 1 \( -type f -o -type l \) | sort) \
  <(cd -- "${OVERLAY}" && find . -mindepth 1 \( -type f -o -type l \) | sort) \
  >"${TEST_ARCH_SANDBOX}/collisions.txt"
test_arch_assert_eq './.config/ghostty/config' "$(cat -- "${TEST_ARCH_SANDBOX}/collisions.txt")" 'aesthetic files must not shadow shared home/'

# --- Shared shell functionality untouched (baseline preserved). ---
test_arch_assert_contains "${SHARED}/.config/fish/config.fish" "starship init fish | source" 'shared starship hook preserved'
test_arch_assert_contains "${SHARED}/.config/fish/config.fish" "direnv hook fish | source" 'shared direnv hook preserved'
test_arch_assert_contains "${SHARED}/.config/fish/config.fish" "zoxide init fish --cmd cd | source" 'shared zoxide hook preserved'
test_arch_assert_contains "${SHARED}/.config/fish/config.fish" "abbr gd 'git diff'" 'shared abbrs preserved'
test_arch_assert_contains "${SHARED}/.config/fish/config.fish" "abbr l 'ls -l'" 'shared l variants preserved (not upstream ls)'
test_arch_assert_contains "${SHARED}/.config/fish/completions/dot.fish" "complete -c dot" 'shared completions preserved'
test_arch_assert_contains "${SHARED}/.config/fish/conf.d/ripgrep.fish" "RIPGREP_CONFIG_PATH" 'shared ripgrep hook preserved'
test_arch_assert_contains "${SHARED}/.config/starship.toml" "command_timeout = 2000" 'shared starship timeout preserved'
test_arch_assert_contains "${SHARED}/.config/starship.toml" '[package]' 'shared starship package section preserved'
[[ -f ${SHARED}/.config/fish/functions/fish_greeting.fish ]] \
  || test_arch_die 'shared fish_greeting missing'
# Suppressed means no fastfetch invocation (the historical comment may name it).
if sed 's/#.*//' "${SHARED}/.config/fish/functions/fish_greeting.fish" | grep -Fq 'fastfetch'; then
  test_arch_die 'shared greeting must stay suppressed (no fastfetch call)'
fi

# --- Overlay aesthetic sources exist and stay additive. ---
for rel in .config/fish/conf.d/caelestia-sequences.fish .config/fish/conf.d/caelestia-greeting.fish \
  .config/fish/conf.d/caelestia-starship.fish .config/caelestia/starship-caelestia.toml \
  .config/caelestia/fastfetch-boxed.jsonc; do
  [[ -f ${OVERLAY}/${rel} ]] || test_arch_die "missing overlay aesthetic: ${rel}"
done
# No shadow of the common fish config, no upstream user-config sourcing.
[[ ! -e ${OVERLAY}/.config/fish/config.fish ]] \
  || test_arch_die 'overlay must not shadow shared fish/config.fish'
if grep -rn 'user-config.fish' "${OVERLAY}/.config/fish/" 2>/dev/null | grep -q 'source'; then
  test_arch_die 'overlay must not source upstream user-config.fish'
fi

# --- Appearance-only and interactive-only (no startup noise). ---
test_arch_assert_contains "${OVERLAY}/.config/fish/conf.d/caelestia-sequences.fish" "status is-interactive" 'sequences must be interactive-only'
test_arch_assert_contains "${OVERLAY}/.config/fish/conf.d/caelestia-starship.fish" "status is-interactive" 'starship setter must be interactive-only'
test_arch_assert_contains "${OVERLAY}/.config/fish/conf.d/caelestia-starship.fish" "STARSHIP_CONFIG" 'starship setter must set STARSHIP_CONFIG'
test_arch_assert_contains "${OVERLAY}/.config/fish/conf.d/caelestia-greeting.fish" "function fish_greeting" 'greeting must override fish_greeting on Arch'
test_arch_assert_contains "${OVERLAY}/.config/fish/conf.d/caelestia-greeting.fish" "38;5;16m" 'greeting must carry upstream colour 16'
test_arch_assert_contains "${OVERLAY}/.config/fish/conf.d/caelestia-greeting.fish" "______" 'greeting must carry upstream ASCII'
# conf.d runs BEFORE config.fish: STARSHIP_CONFIG is set before starship init.
grep -Fq 'STARSHIP_CONFIG' "${OVERLAY}/.config/fish/conf.d/caelestia-starship.fish" \
  || test_arch_die 'STARSHIP_CONFIG setter missing (order: conf.d before config.fish)'

# --- Overlay Starship preserves repo constraints on top of upstream look. ---
test_arch_assert_contains "${OVERLAY}/.config/caelestia/starship-caelestia.toml" "command_timeout = 2000" 'overlay starship keeps command_timeout'
test_arch_assert_contains "${OVERLAY}/.config/caelestia/starship-caelestia.toml" 'detect_files = ["package.json", ".node-version", ".nvmrc", ".tool-versions"]' 'overlay starship keeps Node probing guard'
test_arch_assert_contains "${OVERLAY}/.config/caelestia/starship-caelestia.toml" "[package]" 'overlay starship keeps package section'
grep -A2 '^\[package\]' "${OVERLAY}/.config/caelestia/starship-caelestia.toml" | grep -Fq 'disabled = true' \
  || test_arch_die 'overlay starship must keep package disabled'
grep -A2 '^\[buf\]' "${OVERLAY}/.config/caelestia/starship-caelestia.toml" | grep -Fq 'disabled = true' \
  || test_arch_die 'overlay starship must keep buf disabled'
test_arch_assert_contains "${OVERLAY}/.config/caelestia/starship-caelestia.toml" "success_symbol" 'overlay starship keeps upstream prompt symbols'
test_arch_assert_contains "${OVERLAY}/.config/caelestia/starship-caelestia.toml" "1ee7a98" 'overlay starship must pin upstream revision'

# --- Installer still disables broad upstream components (no re-enable). ---
test_arch_assert_contains "${TEST_ARCH_REPO_ROOT}/lib/arch-desktop.sh" '--disable-components "firefox,fish,starship,fastfetch,foot,micro,btop"' 'installer must keep fish/starship/fastfetch disabled'
test_arch_assert_contains "${TEST_ARCH_REPO_ROOT}/lib/arch-desktop.sh" '--enable-components "uwsm,nvim"' 'installer must enable only uwsm,nvim'

# --- Night light off. ---
test_arch_assert_contains "${OVERLAY}/.config/caelestia/hypr-vars.lua" "automaticNightLight = false" 'night light must default off'

# --- No wallpaper cloning (removed, not flagged off). ---
if declare -F arch_desktop_ensure_wallpapers >/dev/null 2>&1; then
  test_arch_die 'wallpaper routine still defined'
fi
# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-desktop.sh"
test_arch_arm_cleanup
if declare -F arch_desktop_ensure_wallpapers >/dev/null 2>&1; then
  test_arch_die 'wallpaper clone routine still exists (must be removed, not disabled)'
fi
if grep -rn 'WALLPAPER\|ensure_wallpapers\|dharmx/walls' "${TEST_ARCH_REPO_ROOT}/lib/arch-desktop.sh" 2>/dev/null; then
  test_arch_die 'wallpaper constants still present in lib/arch-desktop.sh'
fi
[[ -d ${SHARED}/Pictures/wallpapers ]] || test_arch_die 'shared local wallpaper assets must be retained'

# --- Monitor: supported override only, commented example, no active layout. ---
test_arch_assert_contains "${OVERLAY}/.config/caelestia/hypr-user.lua" 'Monitor settings live HERE' 'hypr-user must document monitor location'
test_arch_assert_contains "${OVERLAY}/.config/caelestia/hypr-user.lua" 'hl.monitor' 'hypr-user must show hl.monitor syntax'
# No ACTIVE (uncommented) hl.monitor call: example stays commented.
if grep -E '^[[:space:]]*hl\.monitor' "${OVERLAY}/.config/caelestia/hypr-user.lua" 2>/dev/null; then
  test_arch_die 'hypr-user.lua must not commit an active monitor layout (commented example only)'
fi
[[ ! -d ${OVERLAY}/.config/hypr ]] || test_arch_die 'overlay must stay out of upstream-owned .config/hypr/'

# --- Fedora unaffected: shared skips aliases, Fedora tree owns its copies. ---
[[ -f ${FEDORA_TREE}/.config/ghostty/config && ! -L ${FEDORA_TREE}/.config/ghostty/config ]] \
  || test_arch_die 'home-fedora ghostty must stay a real file'
[[ -f ${FEDORA_TREE}/.config/hypr/input.lua && ! -L ${FEDORA_TREE}/.config/hypr/input.lua ]] \
  || test_arch_die 'home-fedora input.lua must stay a real file'
if grep -rn 'STARSHIP_CONFIG\|caelestia' "${FEDORA_TREE}/" 2>/dev/null; then
  test_arch_die 'Fedora tree must not reference Caelestia aesthetics'
fi

# --- Noninteractive silence: overlay snippets emit nothing under fish -c. ---
if command -v fish >/dev/null 2>&1; then
  SANDBOX_HOME="${TEST_ARCH_SANDBOX}/fishhome"
  mkdir -p -- "${SANDBOX_HOME}/.config/fish/conf.d" "${SANDBOX_HOME}/.config/caelestia"
  cp -- "${OVERLAY}/.config/fish/conf.d/caelestia-sequences.fish" \
    "${OVERLAY}/.config/fish/conf.d/caelestia-starship.fish" \
    "${SANDBOX_HOME}/.config/fish/conf.d/"
  out="$(HOME="${SANDBOX_HOME}" fish -c 'echo hi' 2>&1)" || test_arch_die 'fish -c failed with overlay snippets'
  test_arch_assert_eq 'hi' "${out}" 'overlay conf.d must be silent noninteractive'
else
  printf 'NOTE: fish absent — noninteractive silence deferred to the Arch target.\n'
fi

test_arch_assert_not_called sudo 'fish aesthetics never elevate'
test_arch_assert_no_live_paths 'fish aesthetics'
printf 'Fish aesthetics stay additive, silent, Fedora-clean, and feature-preserving.\n'
