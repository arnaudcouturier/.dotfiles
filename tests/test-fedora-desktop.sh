#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# Fedora desktop + greeter: vanilla Umbriel/Noctalia session and the Noctalia
# Greeter login, wired into fedora-setup/fedora-check behind the explicit
# display-manager contract. Setup installs (Terra bootstrap once, then the
# stacks) and repairs idempotently; verify treats each missing package and
# each drifted config distinctly. Installs prove their exact commands through
# logging stubs (nothing executes).
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox

# Logging sudo: records privileged commands without executing anything.
cat >"${TEST_ARCH_BIN}/sudo" <<EOF
#!/usr/bin/env bash
printf 'sudo %s\n' "\$*" >>"$(test_arch_calls_log)"
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/sudo"

# rpm stub: -q answers from TEST_INSTALLED (space-separated names), echoing
# its call so the verify assertions can prove which packages were probed.
cat >"${TEST_ARCH_BIN}/rpm" <<EOF
#!/usr/bin/env bash
printf 'rpm %s\n' "\$*" >>"$(test_arch_calls_log)"
if [[ "\$1" == -q ]]; then
  pkg="\${@: -1}"
  case " \${TEST_INSTALLED:-} " in
    *" \${pkg} "*) exit 0 ;;
    *) exit 1 ;;
  esac
fi
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/rpm"

# dnf stub: installs only log (success contract in this sandbox).
cat >"${TEST_ARCH_BIN}/dnf" <<EOF
#!/usr/bin/env bash
printf 'dnf %s\n' "\$*" >>"$(test_arch_calls_log)"
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/dnf"

# systemctl stub: answers the read-only default query from the environment,
# logs everything else for the no-mutation assertions.
cat >"${TEST_ARCH_BIN}/systemctl" <<EOF
#!/usr/bin/env bash
printf 'systemctl %s\n' "\$*" >>"$(test_arch_calls_log)"
if [[ "\${1:-}" == get-default ]]; then
  printf '%s\n' "\${TEST_SYSTEMD_DEFAULT:-multi-user.target}"
  exit 0
fi
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/systemctl"

# id stub: the greeter account exists only when TEST_GREETER_EXISTS=1.
cat >"${TEST_ARCH_BIN}/id" <<EOF
#!/usr/bin/env bash
printf 'id %s\n' "\$*" >>"$(test_arch_calls_log)"
[[ "\${TEST_GREETER_EXISTS:-0}" == 1 ]]
EOF
chmod 755 -- "${TEST_ARCH_BIN}/id"

# getent stub: reports the sandboxed greeter home for the account probe.
cat >"${TEST_ARCH_BIN}/getent" <<EOF
#!/usr/bin/env bash
printf 'getent %s\n' "\$*" >>"$(test_arch_calls_log)"
if [[ "\${1:-}" == passwd && "\${2:-}" == "\${FEDORA_GREETER_USER:-greeter}" ]]; then
  printf 'greeter:x:979:979::%s:/usr/bin/nologin\n' "\${FEDORA_GREETER_HOME}"
  exit 0
fi
exit 1
EOF
chmod 755 -- "${TEST_ARCH_BIN}/getent"

# Session binaries: presence stubs for the command -v probes.
for cmd in umbriel noctalia ghostty noctalia-greeter-session; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"${TEST_ARCH_BIN}/${cmd}"
  chmod 755 -- "${TEST_ARCH_BIN}/${cmd}"
done

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/fedora-desktop.sh"
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/fedora-greeter.sh"
test_arch_arm_cleanup

DESKTOP_LIB="${TEST_ARCH_REPO_ROOT}/lib/fedora-desktop.sh"
GREETER_LIB="${TEST_ARCH_REPO_ROOT}/lib/fedora-greeter.sh"
WORK="${TEST_ARCH_SANDBOX}/work"
mkdir -p -- "${WORK}"
reset_calls() { : >"$(test_arch_calls_log)"; }
DESKTOP_PKGS='umbriel-nightly noctalia ghostty xwayland-satellite xdg-desktop-portal-gtk gnome-keyring gnome-keyring-pam'
GREETER_PKGS='greetd noctalia-greeter gdm gnome-shell gnome-session-wayland-session accountsservice'

# Sandbox greeter paths: no live /etc or /var avoids the live-path tripwire.
export FEDORA_GREETER_TEMPLATE="${TEST_ARCH_REPO_ROOT}/system/fedora/greetd/config.toml"
export FEDORA_GREETER_CONFIG="${WORK}/greetd-config.toml"
export FEDORA_GREETER_DM_LINK="${WORK}/display-manager.service"
export FEDORA_GREETER_USER='greeter'
export FEDORA_GREETER_HOME="${WORK}/greeter-home"
export TEST_SYSTEMD_DEFAULT='multi-user.target' TEST_GREETER_EXISTS=0

# Stowed Umbriel entrypoint fixture: the repo's real file, as stow deploys it.
mkdir -p -- "${HOME}/.config/umbriel"
cp -- "${TEST_ARCH_REPO_ROOT}/home-fedora/.config/umbriel/config.toml" "${HOME}/.config/umbriel/config.toml"

# --- Static: the pinned package sets and entry points. ---
for pkg in ${DESKTOP_PKGS}; do
  grep -Fq -- "${pkg}" "${DESKTOP_LIB}" \
    || test_arch_die "desktop module must carry ${pkg}"
done
for pkg in ${GREETER_PKGS}; do
  grep -Fq -- "${pkg}" "${GREETER_LIB}" \
    || test_arch_die "greeter module must carry ${pkg}"
done
grep -Fq 'fedora_desktop_setup' "${DESKTOP_LIB}" || test_arch_die 'desktop setup entry missing'
grep -Fq 'fedora_desktop_verify' "${DESKTOP_LIB}" || test_arch_die 'desktop verify entry missing'
grep -Fq 'fedora_greeter_setup' "${GREETER_LIB}" || test_arch_die 'greeter setup entry missing'
grep -Fq 'fedora_greeter_verify' "${GREETER_LIB}" || test_arch_die 'greeter verify entry missing'
grep -Fq 'noctalia-greeter-session' "${GREETER_LIB}" || test_arch_die 'greeter must start noctalia-greeter-session'
grep -Fq '.dotfiles-backup' "${GREETER_LIB}" || test_arch_die 'greeter config backup missing'
grep -Fq -- '--replace-display-manager' "${GREETER_LIB}" || test_arch_die 'greeter must name the explicit contract'
# Third-party rule: Terra (community, documented for the compositor/greeter)
# is the only non-Fedora source; COPRs stay out, and --nogpgcheck rides the
# Terra release bootstrap alone, never a package install.
if sed 's/#.*//' "${DESKTOP_LIB}" | grep -Eqi 'copr'; then
  test_arch_die 'desktop module must not reference COPR repositories'
fi
if sed 's/#.*//' "${GREETER_LIB}" | grep -Eqi 'copr'; then
  test_arch_die 'greeter module must not reference COPR repositories'
fi
test_arch_assert_eq 1 "$(sed 's/#.*//' "${DESKTOP_LIB}" | grep -Fc -- '--nogpgcheck')" \
  '--nogpgcheck must appear exactly once: the Terra release bootstrap'
grep -Fq 'terra-release' "${DESKTOP_LIB}" \
  || test_arch_die 'desktop module must bootstrap the Terra release package'
# Templates: the greeter config starts the session wrapper as greeter with
# no autologin; the Umbriel entrypoint includes packaged defaults,
# autostarts noctalia once, and carries the Mod+K plus Mod+Return ghostty
# overrides.
grep -Fq 'command = "/usr/bin/noctalia-greeter-session"' "${FEDORA_GREETER_TEMPLATE}" \
  || test_arch_die 'greeter template must start noctalia-greeter-session'
grep -Fq 'user = "greeter"' "${FEDORA_GREETER_TEMPLATE}" \
  || test_arch_die 'greeter template must run as greeter'
if grep -Eq '^[[:space:]]*initial_session' "${FEDORA_GREETER_TEMPLATE}"; then
  test_arch_die 'greeter template must not configure autologin'
fi
grep -Fq '/usr/share/umbriel/config.toml' "${HOME}/.config/umbriel/config.toml" \
  || test_arch_die 'umbriel entrypoint must include the packaged defaults'
grep -Fq 'autostart = ["noctalia"]' "${HOME}/.config/umbriel/config.toml" \
  || test_arch_die 'umbriel entrypoint must autostart noctalia once'
grep -Fq '"Mod+K"' "${HOME}/.config/umbriel/config.toml" \
  || test_arch_die 'umbriel entrypoint must carry the Mod+K override'
grep -Fq 'spawn:ghostty' "${HOME}/.config/umbriel/config.toml" \
  || test_arch_die 'umbriel entrypoint must carry the Mod+Return ghostty override'

# --- Static: dot wires the Fedora verbs and steps. ---
grep -Fq 'FEDORA_SETUP_STEPS=(gaming desktop greeter)' "${TEST_ARCH_REPO_ROOT}/dot" \
  || test_arch_die 'dot must declare the Fedora step list'
grep -Fq 'fedora_load_module fedora-desktop.sh' "${TEST_ARCH_REPO_ROOT}/dot" \
  || test_arch_die 'dot must load the fedora-desktop module'
grep -Fq 'fedora_load_module fedora-greeter.sh' "${TEST_ARCH_REPO_ROOT}/dot" \
  || test_arch_die 'dot must load the fedora-greeter module'
grep -Fq 'desktop) fedora_desktop_setup ;;' "${TEST_ARCH_REPO_ROOT}/dot" \
  || test_arch_die 'fedora-setup must dispatch the desktop step'
grep -Fq 'greeter) fedora_greeter_setup' "${TEST_ARCH_REPO_ROOT}/dot" \
  || test_arch_die 'fedora-setup must dispatch the greeter step'
grep -Fq 'desktop) fedora_desktop_verify || failed=1 ;;' "${TEST_ARCH_REPO_ROOT}/dot" \
  || test_arch_die 'fedora-check must verify the desktop step'
grep -Fq 'greeter) fedora_greeter_verify || failed=1 ;;' "${TEST_ARCH_REPO_ROOT}/dot" \
  || test_arch_die 'fedora-check must verify the greeter step'
grep -Fq -- '--replace-display-manager) replace_dm=1; shift ;;' "${TEST_ARCH_REPO_ROOT}/dot" \
  || test_arch_die 'fedora-setup must accept the display-manager flag'

# --- Refusal: the new steps die on Arch, unchanged. ---
export DISTRO=arch
set +e
arch_refusal="$(fedora_desktop_setup 2>&1)"
arch_desktop_status=$?
arch_greeter_refusal="$(fedora_greeter_setup 2>&1)"
arch_greeter_status=$?
set -e
export DISTRO=fedora
((arch_desktop_status != 0)) || test_arch_die 'desktop setup proceeded on Arch'
((arch_greeter_status != 0)) || test_arch_die 'greeter setup proceeded on Arch'
test_arch_assert_contains <(printf '%s\n' "${arch_refusal}") 'Fedora-only' 'desktop refusal names the Fedora-only gate'
test_arch_assert_contains <(printf '%s\n' "${arch_greeter_refusal}") 'Fedora-only' 'greeter refusal names the Fedora-only gate'

# --- Desktop fresh: absent Terra bootstraps, then the stack installs. ---
export TEST_INSTALLED='' DISTRO=fedora
reset_calls
fedora_desktop_setup >/dev/null 2>&1
test_arch_assert_contains "$(test_arch_calls_log)" 'terra-release' \
  'desktop setup must bootstrap Terra first'
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo dnf install -y -- umbriel-nightly' \
  'desktop setup must install the stack in one transaction'
for pkg in noctalia ghostty xwayland-satellite xdg-desktop-portal-gtk gnome-keyring; do
  test_arch_assert_contains "$(test_arch_calls_log)" "${pkg}" "desktop install must include ${pkg}"
done

# --- Desktop repair: present Terra skips the bootstrap, stack converges. ---
export TEST_INSTALLED="terra-release ${DESKTOP_PKGS}"
reset_calls
repair_out="$(fedora_desktop_setup 2>&1)"
test_arch_assert_contains <(printf '%s\n' "${repair_out}") 'Terra repository already configured.' \
  'repair must skip re-adding Terra'
if grep -q 'repofrompath' "$(test_arch_calls_log)"; then
  test_arch_die 'repair must not re-bootstrap the Terra release package'
fi
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo dnf install -y -- umbriel-nightly' \
  'present stack must repair without asking'

# --- Desktop verify: full stack plus entrypoint passes quietly. ---
fedora_desktop_verify >"${WORK}/desktop-full.out" 2>&1 || test_arch_die 'complete desktop must verify clean'
if grep -qi 'missing' "${WORK}/desktop-full.out"; then
  test_arch_die 'complete desktop must report nothing missing'
fi

# --- Desktop verify: partial stack names each missing package. ---
export TEST_INSTALLED="terra-release umbriel-nightly noctalia"
set +e
fedora_desktop_verify >"${WORK}/desktop-partial.out" 2>&1
verify_status=$?
set -e
((verify_status != 0)) || test_arch_die 'partial desktop must fail verification'
test_arch_assert_contains "${WORK}/desktop-partial.out" 'Desktop package missing: ghostty' \
  'verify must name the missing package'

# --- Desktop verify: missing entrypoint fails distinctly. ---
export TEST_INSTALLED="terra-release ${DESKTOP_PKGS}"
mv -- "${HOME}/.config/umbriel/config.toml" "${WORK}/config.toml.bak"
set +e
fedora_desktop_verify >"${WORK}/desktop-noconfig.out" 2>&1
noconfig_status=$?
set -e
((noconfig_status != 0)) || test_arch_die 'missing entrypoint must fail verification'
test_arch_assert_contains "${WORK}/desktop-noconfig.out" 'Umbriel entrypoint missing' \
  'verify must name the missing entrypoint'
mv -- "${WORK}/config.toml.bak" "${HOME}/.config/umbriel/config.toml"

# --- Greeter fresh: no incumbent enables directly, recording every write. ---
cp -- "${FEDORA_GREETER_TEMPLATE}" "${FEDORA_GREETER_CONFIG}"
rm -f -- "${FEDORA_GREETER_DM_LINK}"
export TEST_GREETER_EXISTS=0 TEST_SYSTEMD_DEFAULT='multi-user.target'
reset_calls
fedora_greeter_setup 0 >/dev/null 2>&1
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo dnf install -y -- greetd' \
  'greeter setup must install the greeter stack'
test_arch_assert_contains "$(test_arch_calls_log)" 'noctalia-greeter' \
  'greeter install must include noctalia-greeter'
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo useradd' \
  'greeter setup must create the greeter account'
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo systemctl enable greetd.service' \
  'greeter setup must enable greetd'
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo systemctl set-default graphical.target' \
  'greeter setup must raise a text-mode default to graphical'

# --- Greeter refusal: an incumbent without the flag dies before mutation. ---
ln -s -- /usr/lib/systemd/system/gdm.service "${FEDORA_GREETER_DM_LINK}"
reset_calls
set +e
incumbent_out="$(fedora_greeter_setup 0 2>&1)"
incumbent_status=$?
set -e
((incumbent_status != 0)) || test_arch_die 'greeter setup displaced an incumbent without the flag'
test_arch_assert_contains <(printf '%s\n' "${incumbent_out}") 'gdm.service' \
  'refusal must name the incumbent display manager'
test_arch_assert_not_called sudo 'refusal never elevates'

# --- Greeter cutover: the explicit flag replaces the incumbent. ---
export TEST_GREETER_EXISTS=1
reset_calls
fedora_greeter_setup 1 >/dev/null 2>&1
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo systemctl disable gdm.service' \
  'cutover must disable the incumbent under the explicit contract'
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo systemctl enable greetd.service' \
  'cutover must enable greetd'
rm -f -- "${FEDORA_GREETER_DM_LINK}"

# --- Reconcile: the dnf preset artifact stands down without the flag. ---
# Simulates this run starting DM-less while the transaction preset-enables
# gdm mid-run: the alias holder is our own recovery install, not an
# incumbent, so no flag is demanded.
rm -f -- "${FEDORA_GREETER_DM_LINK}"
ln -s -- /usr/lib/systemd/system/gdm.service "${FEDORA_GREETER_DM_LINK}"
reset_calls
fedora_greeter_reconcile_dm '' 0 >/dev/null 2>&1
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo systemctl disable gdm.service' \
  'reconcile must stand down the preset artifact'
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo systemctl enable greetd.service' \
  'reconcile must enable greetd after the artifact'

# --- Reconcile: an already-greetd alias just converges. ---
rm -f -- "${FEDORA_GREETER_DM_LINK}"
ln -s -- /usr/lib/systemd/system/greetd.service "${FEDORA_GREETER_DM_LINK}"
reset_calls
fedora_greeter_reconcile_dm 'greetd.service' 0 >/dev/null 2>&1
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo systemctl enable greetd.service' \
  'reconcile must converge an already-greetd alias'
if grep -q 'sudo systemctl disable' "$(test_arch_calls_log)"; then
  test_arch_die 'reconcile must not disable anything when greetd already holds login'
fi

# --- Reconcile: no alias at all just enables. ---
rm -f -- "${FEDORA_GREETER_DM_LINK}"
reset_calls
fedora_greeter_reconcile_dm '' 0 >/dev/null 2>&1
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo systemctl enable greetd.service' \
  'reconcile must enable greetd when nothing holds login'

# --- Reconcile: a real incumbent without the flag dies before mutation. ---
rm -f -- "${FEDORA_GREETER_DM_LINK}"
ln -s -- /usr/lib/systemd/system/gdm.service "${FEDORA_GREETER_DM_LINK}"
reset_calls
set +e
reconcile_out="$(fedora_greeter_reconcile_dm 'gdm.service' 0 2>&1)"
reconcile_status=$?
set -e
((reconcile_status != 0)) || test_arch_die 'reconcile displaced an incumbent without the flag'
test_arch_assert_contains <(printf '%s\n' "${reconcile_out}") 'gdm.service' \
  'reconcile refusal must name the incumbent'
test_arch_assert_not_called sudo 'reconcile refusal never elevates'

# --- Reconcile: a foreign mid-run change without the flag dies untouched. ---
rm -f -- "${FEDORA_GREETER_DM_LINK}"
ln -s -- /usr/lib/systemd/system/sddm.service "${FEDORA_GREETER_DM_LINK}"
reset_calls
set +e
foreign_out="$(fedora_greeter_reconcile_dm '' 0 2>&1)"
foreign_status=$?
set -e
((foreign_status != 0)) || test_arch_die 'reconcile touched a foreign mid-run change without the flag'
test_arch_assert_contains <(printf '%s\n' "${foreign_out}") 'sddm.service' \
  'reconcile must name the unexpected holder'
test_arch_assert_not_called sudo 'foreign-holder refusal never elevates'
rm -f -- "${FEDORA_GREETER_DM_LINK}"

# --- Greeter verify: full stack plus config passes quietly. ---
export TEST_INSTALLED="terra-release ${DESKTOP_PKGS} ${GREETER_PKGS}"
fedora_greeter_verify >"${WORK}/greeter-full.out" 2>&1 || test_arch_die 'complete greeter must verify clean'
if grep -qi 'missing' "${WORK}/greeter-full.out"; then
  test_arch_die 'complete greeter must report nothing missing'
fi

# --- Greeter verify: partial stack names the missing package. ---
export TEST_INSTALLED="terra-release ${DESKTOP_PKGS} greetd gdm"
set +e
fedora_greeter_verify >"${WORK}/greeter-partial.out" 2>&1
greeter_status=$?
set -e
((greeter_status != 0)) || test_arch_die 'partial greeter must fail verification'
test_arch_assert_contains "${WORK}/greeter-partial.out" 'Greeter package missing: noctalia-greeter' \
  'verify must name the missing greeter package'

test_arch_assert_no_live_paths 'fedora desktop and greeter stacks'
printf 'Fedora desktop and greeter provision vanilla Umbriel/Noctalia, refuse incumbents without the flag, and verify distinctly.\n'
