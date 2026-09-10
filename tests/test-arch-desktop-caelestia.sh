#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# Caelestia integration against fixtures: a fabricated upstream dots repo
# (git + jq are real), hand-deployed real-file tree, and stubbed Hyprland.
# First-time convergence, repeat stability, fail-loud drift and gate-shut
# paths, and no write-through into the overlay source or fixture origin.
# patch(1) is absent on this host and no extra packages are allowed, so
# patch-mediated dynamics are noted and skipped; everything else runs.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

command -v git >/dev/null 2>&1 || { printf 'SEAM PENDING: git not installed\n'; exit 3; }
command -v jq >/dev/null 2>&1 || { printf 'SEAM PENDING: jq not installed\n'; exit 3; }

test_arch_make_sandbox
test_arch_stub_command sudo
# Presence-only patch stub: require_command checks pass, but any real
# invocation is loud (exit 99). Marker-skip paths must never call it.
test_arch_stub_command patch

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-desktop.sh"
test_arch_arm_cleanup

# Scripted externals: pacman answers Hyprland's version; Hyprland verify
# honors TEST_HYPR_VERIFY; caelestia must never run on a complete tree.
cat >"${TEST_ARCH_BIN}/pacman" <<EOF
#!/usr/bin/env bash
printf 'pacman %s\n' "\$*" >>"$(test_arch_calls_log)"
case "\$*" in
  '-Q hyprland') printf 'hyprland 0.55.1\n'; exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod 755 -- "${TEST_ARCH_BIN}/pacman"
cat >"${TEST_ARCH_BIN}/vercmp" <<EOF
#!/usr/bin/env bash
printf 'vercmp %s\n' "\$*" >>"$(test_arch_calls_log)"
printf '0\n'
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/vercmp"
cat >"${TEST_ARCH_BIN}/Hyprland" <<EOF
#!/usr/bin/env bash
printf 'Hyprland %s\n' "\$*" >>"$(test_arch_calls_log)"
exit "\${TEST_HYPR_VERIFY:-0}"
EOF
chmod 755 -- "${TEST_ARCH_BIN}/Hyprland"
test_arch_stub_command caelestia

# Real GNU patch lives outside any stub dir; the presence-only stub above
# must not count. Patch-mediated dynamics run only with the real binary.
HAVE_PATCH=0
[[ -x /usr/bin/patch || -x /bin/patch ]] && HAVE_PATCH=1

# --- Fixture upstream: dots repo with a hypr tree (no execs.lua, so no
# --- patch binary is needed for tree comparison). ---
DOTS="${TEST_ARCH_HOME}/.local/state/caelestia/dots"
DEPLOYED_HYPR="${TEST_ARCH_HOME}/.config/hypr"
mkdir -p -- "${DOTS}/hypr/hyprland" "${DEPLOYED_HYPR}/hyprland" "${TEST_ARCH_HOME}/.config/uwsm"
cat >"${DOTS}/hypr/hyprland.lua" <<'EOF'
-- fixture entry
require("hyprland.execs")
EOF
printf -- '-- fixture theme\n' >"${DOTS}/hypr/theme.lua"
printf -- '-- fixture deployed execs stand-in\n' >"${DOTS}/hypr/hyprland/other.lua"
git -C "${DOTS}" init -q
git -C "${DOTS}" -c user.email=t@t -c user.name=t add -A
git -C "${DOTS}" -c user.email=t@t -c user.name=t commit -qm fixture
REV="$(git -C "${DOTS}" rev-parse HEAD)"
printf '{"applied_rev": "%s", "enabled_components": ["hypr", "uwsm"]}\n' "${REV}" \
  >"${TEST_ARCH_HOME}/.local/state/caelestia/dots-state.json"
cp -- "${DOTS}/hypr/hyprland.lua" "${DOTS}/hypr/theme.lua" "${DEPLOYED_HYPR}/"
cp -- "${DOTS}/hypr/hyprland/other.lua" "${DEPLOYED_HYPR}/hyprland/"
printf 'env-a\n' >"${TEST_ARCH_HOME}/.config/uwsm/env"
printf 'env-b\n' >"${TEST_ARCH_HOME}/.config/uwsm/env-hyprland"

# --- First-time convergence: complete tree validates. ---
arch_desktop_caelestia_tree_complete
printf 'first-time tree validates.\n'

# --- Repeat stability: unchanged on re-check. ---
arch_desktop_caelestia_tree_complete

# --- Drift fails loud: removed file, wrong rev, missing component. ---
rm -- "${DEPLOYED_HYPR}/theme.lua"
set +e
( arch_desktop_caelestia_tree_complete >/dev/null 2>&1 )
drift_status=$?
set -e
((drift_status != 0)) || test_arch_die 'removed tree file still validates'
cp -- "${DOTS}/hypr/theme.lua" "${DEPLOYED_HYPR}/"
printf '{"applied_rev": "deadbeef", "enabled_components": ["hypr", "uwsm"]}\n' \
  >"${TEST_ARCH_HOME}/.local/state/caelestia/dots-state.json"
set +e
( arch_desktop_caelestia_tree_complete >/dev/null 2>&1 )
rev_status=$?
set -e
((rev_status != 0)) || test_arch_die 'stale applied_rev still validates'
printf '{"applied_rev": "%s", "enabled_components": ["hypr"]}\n' "${REV}" \
  >"${TEST_ARCH_HOME}/.local/state/caelestia/dots-state.json"
set +e
( arch_desktop_caelestia_tree_complete >/dev/null 2>&1 )
comp_status=$?
set -e
((comp_status != 0)) || test_arch_die 'tree without uwsm still validates'
printf '{"applied_rev": "%s", "enabled_components": ["hypr", "uwsm"]}\n' "${REV}" \
  >"${TEST_ARCH_HOME}/.local/state/caelestia/dots-state.json"
arch_desktop_caelestia_tree_complete

# --- Symlink under the deployed tree fails validation. ---
ln -s -- "${DEPLOYED_HYPR}/theme.lua" "${DEPLOYED_HYPR}/hyprland/linked.lua"
set +e
( arch_desktop_caelestia_tree_complete >/dev/null 2>&1 )
link_status=$?
set -e
((link_status != 0)) || test_arch_die 'symlinked tree file still validates'
rm -- "${DEPLOYED_HYPR}/hyprland/linked.lua"

# --- Greeter gate, verify variant: hand-patched execs.lua carries the
# --- require/start/autostart patterns as real files (installer output). ---
cat >"${DEPLOYED_HYPR}/hyprland/execs.lua" <<'EOF'
-- fixture generated execs, night-light guarded like installer+patch output
require("hyprland.execs")
hl.on("hyprland.start", function()
    hl.exec_cmd("caelestia shell -d")
end)
if vars.automaticNightLight ~= false then
    hl.exec_cmd("sleep 1 && gammastep")
end
EOF
export TEST_HYPR_VERIFY=0
arch_desktop_verify_caelestia >/dev/null
printf 'verify passes on the integrated tree.\n'

# --- Gate failures die loud: rejecting Hyprland, missing entry, stray link. ---
export TEST_HYPR_VERIFY=1
set +e
( arch_desktop_verify_caelestia >/dev/null 2>&1 )
hypr_status=$?
set -e
((hypr_status != 0)) || test_arch_die 'rejecting Hyprland passed the gate'
export TEST_HYPR_VERIFY=0
mv -- "${DEPLOYED_HYPR}/hyprland.lua" "${TEST_ARCH_SANDBOX}/entry-away.lua"
set +e
( arch_desktop_verify_caelestia >/dev/null 2>&1 )
entry_status=$?
set -e
((entry_status != 0)) || test_arch_die 'missing entry passed the gate'
mv -- "${TEST_ARCH_SANDBOX}/entry-away.lua" "${DEPLOYED_HYPR}/hyprland.lua"
ln -s -- "${DEPLOYED_HYPR}/theme.lua" "${DEPLOYED_HYPR}/stray.lua"
set +e
( arch_desktop_verify_caelestia >/dev/null 2>&1 )
stray_status=$?
set -e
((stray_status != 0)) || test_arch_die 'stray symlink passed the gate'
rm -- "${DEPLOYED_HYPR}/stray.lua"
arch_desktop_verify_caelestia >/dev/null

# --- Night-light patch: marker skip needs no patch binary execution. ---
arch_desktop_apply_night_light_patch >/dev/null
test_arch_assert_not_called patch 'marker skip never invokes patch'
printf 'marker-present execs skips patching.\n'
mv -- "${DEPLOYED_HYPR}/hyprland/execs.lua" "${TEST_ARCH_SANDBOX}/execs-away.lua"
set +e
( arch_desktop_apply_night_light_patch >/dev/null 2>&1 )
nopatch_target_status=$?
set -e
((nopatch_target_status != 0)) || test_arch_die 'missing execs.lua patched silently'
mv -- "${TEST_ARCH_SANDBOX}/execs-away.lua" "${DEPLOYED_HYPR}/hyprland/execs.lua"
if ((HAVE_PATCH == 0)); then
  printf 'NOTE: patch(1) absent — apply-to-unpatched and drift-death dynamics deferred to the Arch target.\n'
else
  printf -- '-- unpatched upstream shape\nrequire("hyprland.execs")\n' >"${DEPLOYED_HYPR}/hyprland/execs.lua"
  set +e
  ( arch_desktop_apply_night_light_patch >/dev/null 2>&1 )
  applypatch_status=$?
  set -e
  ((applypatch_status != 0)) && test_arch_die 'clean patch application failed'
fi

# --- Equibop: absent theme skips quietly; present theme merges via jq. ---
arch_desktop_enable_equibop_theme >/dev/null
mkdir -p -- "${TEST_ARCH_HOME}/.config/equibop/themes" "${TEST_ARCH_HOME}/.config/equibop/settings"
printf '/* fixture */\n' >"${TEST_ARCH_HOME}/.config/equibop/themes/caelestia.theme.css"
printf '{"enabledThemes": ["other.css"]}\n' >"${TEST_ARCH_HOME}/.config/equibop/settings/settings.json"
arch_desktop_enable_equibop_theme >/dev/null
jq -e '.enabledThemes | index("caelestia.theme.css") != null' \
  "${TEST_ARCH_HOME}/.config/equibop/settings/settings.json" >/dev/null \
  || test_arch_die 'equibop theme was not merged'

# --- No wallpaper cloning: the routine is gone; user files are never touched. ---
if declare -F arch_desktop_ensure_wallpapers >/dev/null 2>&1; then
  test_arch_die 'wallpaper clone routine still exists (must be removed, not disabled)'
fi
if grep -rn 'WALLPAPER' "${TEST_ARCH_REPO_ROOT}/lib/arch-desktop.sh" 2>/dev/null; then
  test_arch_die 'wallpaper constants still present in lib/arch-desktop.sh'
fi

# --- No write-through: overlay source and fixture origin unchanged. ---
find "${TEST_ARCH_REPO_ROOT}/home-arch" -type f -exec sha256sum -- {} + | sort -k2 \
  >"${TEST_ARCH_SANDBOX}/overlay-checksums.txt"
[[ -s ${TEST_ARCH_SANDBOX}/overlay-checksums.txt ]] || test_arch_die 'overlay source unreadable'
git -C "${DOTS}" status --porcelain >"${TEST_ARCH_SANDBOX}/dots-status.txt"
[[ ! -s ${TEST_ARCH_SANDBOX}/dots-status.txt ]] || test_arch_die "fixture origin dirtied: $(cat -- "${TEST_ARCH_SANDBOX}/dots-status.txt")"

test_arch_assert_not_called sudo 'caelestia fixtures never elevate'
test_arch_assert_not_called caelestia 'complete tree never runs the installer'
test_arch_assert_no_live_paths 'caelestia fixtures'
printf 'Caelestia fixtures converge, fail loud, and write through nothing.\n'
