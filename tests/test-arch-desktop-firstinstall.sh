#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# D1/D2 first-install regression with a faithful pristine upstream deploy.
# Uses the vendored upstream hypr excerpt (tests/fixtures/caelestia, see
# PROVENANCE.md) plus a stub installer that deploys it pristine (never
# patched), then runs the REAL arch_desktop_configure_caelestia:
# stub installer that deploys it pristine (never patched), then runs the
# REAL arch_desktop_configure_caelestia under a pty: pre-D1-fix it dies at
# the post-installer gate ('installer finished without a complete tree');
# fixed, it patches, converges, and never loops. Installer argv must pin
# --aur-helper yay (D2) and never enable excluded apps.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

FIXTURE_HYPR="${TEST_ARCH_REPO_ROOT}/tests/fixtures/caelestia/hypr"
# In-repo fixtures: missing means a corrupt checkout, never a skip.
[[ -f ${FIXTURE_HYPR}/hyprland.lua && -f ${FIXTURE_HYPR}/hyprland/execs.lua ]] \
  || test_arch_die 'missing vendored upstream fixtures under tests/fixtures/caelestia'
command -v git >/dev/null 2>&1 || { printf 'SEAM PENDING: git not installed\n'; exit 3; }
command -v jq >/dev/null 2>&1 || { printf 'SEAM PENDING: jq not installed\n'; exit 3; }
command -v python3 >/dev/null 2>&1 || { printf 'SEAM PENDING: python3 not installed\n'; exit 3; }

test_arch_make_sandbox
export XDG_CONFIG_HOME="${TEST_ARCH_HOME}/.config" XDG_STATE_HOME="${TEST_ARCH_HOME}/.local/state"
test_arch_stub_command sudo

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-desktop.sh"
test_arch_arm_cleanup

# --- Scripted externals (pacman/vercmp/Hyprland log; wallpapers warn-skip). ---
cat >"${TEST_ARCH_BIN}/pacman" <<EOF
#!/usr/bin/env bash
printf 'pacman %s\n' "\$*" >>"$(test_arch_calls_log)"
case "\$*" in
  '-Q hyprland') printf 'hyprland 0.55.0-1\n'; exit 0 ;;
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
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/Hyprland"
mkdir -p -- "${TEST_ARCH_HOME}/Pictures/Wallpapers/keep"
printf 'mine\n' >"${TEST_ARCH_HOME}/Pictures/Wallpapers/keep/mine.txt"

# --- Strict patch emulation (python stdlib): exact hunk bytes and offsets
# --- only, else fail. Pins the literal; GNU patch runs on the Arch target.
cat >"${TEST_ARCH_BIN}/patch" <<'PYEOF'
#!/usr/bin/env python3
import sys
log_path = "__LOG__"
with open(log_path, "a") as log:
    log.write("patch " + " ".join(sys.argv[1:]) + "\n")
target = sys.argv[-1]
if "--fuzz=0" not in sys.argv:
    sys.exit(1)
diff = sys.stdin.read().splitlines()
assert diff[2] == "@@ -21,3 +21,5 @@", diff[2]
minus = [l[1:] for l in diff[3:] if l.startswith("-")]
plus = [l[1:] for l in diff[3:] if l.startswith("+")]
assert minus == ["    -- Location provider and night light",
                 '    hl.exec_cmd("/usr/lib/geoclue-2.0/demos/agent")',
                 '    hl.exec_cmd("sleep 1 && gammastep")'], minus
assert plus == ["    if vars.automaticNightLight ~= false then",
                "        -- Location provider and night light",
                '        hl.exec_cmd("/usr/lib/geoclue-2.0/demos/agent")',
                '        hl.exec_cmd("sleep 1 && gammastep")',
                "    end"], plus
with open(target) as handle:
    lines = handle.read().splitlines()
if any("automaticNightLight ~= false" in line for line in lines):
    sys.exit(0)
start = 21 - 1
assert lines[start:start + 3] == minus, lines[start:start + 3]
lines[start:start + 3] = plus
with open(target, "w") as handle:
    handle.write("\n".join(lines) + "\n")
PYEOF
sed -i "s|__LOG__|$(test_arch_calls_log)|" "${TEST_ARCH_BIN}/patch"
chmod 755 -- "${TEST_ARCH_BIN}/patch"

# --- Faithful pristine installer stub: deploys upstream byte-identical,
# --- fresh git state, uwsm env files. Never patches (that is configure's). ---
cat >"${TEST_ARCH_BIN}/caelestia" <<EOF
#!/usr/bin/env bash
printf 'caelestia %s\n' "\$*" >>"$(test_arch_calls_log)"
if [[ "\$*" == *"install --help"* ]]; then
  printf '%s\n' "--noconfirm --disable-components --enable-components --aur-helper"
  exit 0
fi
rm -rf -- "\${HOME}/.config/hypr" "\${XDG_STATE_HOME}/caelestia"
mkdir -p -- "\${HOME}/.config/hypr" "\${XDG_STATE_HOME}/caelestia/dots" "\${XDG_CONFIG_HOME}/uwsm"
cp -r "${FIXTURE_HYPR}/." "\${HOME}/.config/hypr/"
cp -r "${FIXTURE_HYPR}" "\${XDG_STATE_HOME}/caelestia/dots/hypr"
git -C "\${XDG_STATE_HOME}/caelestia/dots" init -q
git -C "\${XDG_STATE_HOME}/caelestia/dots" add -A
git -C "\${XDG_STATE_HOME}/caelestia/dots" -c user.email=t@t -c user.name=t commit -qm fixture
rev="\$(git -C "\${XDG_STATE_HOME}/caelestia/dots" rev-parse HEAD)"
printf '{"applied_rev": "%s", "enabled_components": ["hypr", "uwsm", "nvim"]}\n' "\${rev}" \
  >"\${XDG_STATE_HOME}/caelestia/dots-state.json"
touch -- "\${XDG_CONFIG_HOME}/uwsm/env" "\${XDG_CONFIG_HOME}/uwsm/env-hyprland"
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/caelestia"

# --- Overlay in place first (dot's order: install, then configure). ---
arch_desktop_install_overlay >/dev/null
find "${TEST_ARCH_REPO_ROOT}/home-arch" -type f -exec sha256sum -- {} + | sort -k2 \
  >"${TEST_ARCH_SANDBOX}/overlay-source-before.txt"

# --- D1: first install runs fully non-interactive (no tty gate anymore). ---
set +e
first_out="$(arch_desktop_configure_caelestia 2>&1)"
first_status=$?
set -e
printf '%s\n' "${first_out}" >"${TEST_ARCH_SANDBOX}/first-configure.txt"
((first_status == 0)) || test_arch_die "D1: first install fails: $(grep -a -m1 -o -E '(tree incomplete after install and patch|installer finished without a complete tree|installer failed)' "${TEST_ARCH_SANDBOX}/first-configure.txt" || tail -n2 "${TEST_ARCH_SANDBOX}/first-configure.txt")"

# --- Installer ran exactly once and deployed pristine; configure patched. ---
test_arch_assert_eq 1 "$(grep -c '^caelestia install --noconfirm' "$(test_arch_calls_log)")" 'installer ran once'
test_arch_assert_contains "${TEST_ARCH_HOME}/.config/hypr/hyprland/execs.lua" \
  'automaticNightLight ~= false' 'deployed execs.lua patched by configure'

# --- D2: installer argv pins the helper and the component contract. ---
test_arch_assert_contains "$(test_arch_calls_log)" '--aur-helper yay' 'D2: AUR helper pinned to yay'
test_arch_assert_contains "$(test_arch_calls_log)" '--disable-components firefox,fish,starship,fastfetch,foot,micro,btop' 'D3: second terminal/editor and detach hazards disabled'
test_arch_assert_contains "$(test_arch_calls_log)" '--enable-components uwsm,nvim' 'only contracted components enabled'
test_arch_assert_contains "$(test_arch_calls_log)" '--noconfirm' 'non-interactive invocation'
for excluded in spotify vscode vscodium discord; do
  if grep -- '^caelestia install ' "$(test_arch_calls_log)" | grep -qw -- "${excluded}"; then
    test_arch_die "installer enables excluded app: ${excluded}"
  fi
done

# --- Convergence: second configure runs no installer and changes nothing. ---
installs_before="$(grep -c '^caelestia install --noconfirm' "$(test_arch_calls_log)")"
find "${TEST_ARCH_HOME}/.config/hypr" -type f -exec sha256sum -- {} + | sort -k2 \
  >"${TEST_ARCH_SANDBOX}/tree-first.txt"
set +e
arch_desktop_configure_caelestia >/dev/null 2>&1
second_status=$?
set -e
((second_status == 0)) || test_arch_die 'repeat configure failed (reinstall loop)'
test_arch_assert_eq "${installs_before}" "$(grep -c '^caelestia install --noconfirm' "$(test_arch_calls_log)")" 'repeat configure runs no installer'
find "${TEST_ARCH_HOME}/.config/hypr" -type f -exec sha256sum -- {} + | sort -k2 \
  >"${TEST_ARCH_SANDBOX}/tree-second.txt"
cmp -s -- "${TEST_ARCH_SANDBOX}/tree-first.txt" "${TEST_ARCH_SANDBOX}/tree-second.txt" \
  || test_arch_die 'repeat configure changed the tree (reinstall loop)'

# --- Gate open after first install, and overlay still complete. ---
arch_desktop_verify_overlay >/dev/null
arch_desktop_verify_caelestia >/dev/null

# --- No source write-through anywhere. ---
find "${TEST_ARCH_REPO_ROOT}/home-arch" -type f -exec sha256sum -- {} + | sort -k2 \
  >"${TEST_ARCH_SANDBOX}/overlay-source-after.txt"
cmp -s -- "${TEST_ARCH_SANDBOX}/overlay-source-before.txt" "${TEST_ARCH_SANDBOX}/overlay-source-after.txt" \
  || test_arch_die 'configure wrote through into the overlay source'
test_arch_assert_contains "${TEST_ARCH_HOME}/Pictures/Wallpapers/keep/mine.txt" 'mine' 'foreign wallpaper dir untouched'

test_arch_assert_not_called sudo 'first install never elevates'
test_arch_assert_no_live_paths 'first install'
printf 'First install configures, converges, pins argv, and writes through nothing.\n'
