#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# Tailscale's Linux systray ships in home-arch/: the upstream systemd user
# unit, started at login by an autostart entry that starts that unit, plus a
# visible launcher entry that starts the same unit (systemd keeps one
# instance, so the launcher and the login start cannot double the tray).
# The tray runs unprivileged, so arch_system_setup_tailscale makes the
# invoking user tailscaled's operator; without it the tray refuses to
# manage the daemon. No sudo, systemctl, or package manager executes:
# every external answers from a stub.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox

# Logging sudo: records the operator command without executing anything.
cat >"${TEST_ARCH_BIN}/sudo" <<EOF
#!/usr/bin/env bash
printf 'sudo %s\n' "\$*" >>"$(test_arch_calls_log)"
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/sudo"

# pacman stub: only the tailscale query is modeled (present iff
# TEST_TAILSCALE_PKG=1); everything else is absent.
cat >"${TEST_ARCH_BIN}/pacman" <<EOF
#!/usr/bin/env bash
printf 'pacman %s\n' "\$*" >>"$(test_arch_calls_log)"
if [[ "\$1" == -Q && "\$2" == tailscale ]]; then
  [[ "\${TEST_TAILSCALE_PKG:-0}" == 1 ]] && exit 0 || exit 1
fi
exit 1
EOF
chmod 755 -- "${TEST_ARCH_BIN}/pacman"

# systemctl stub: unit existence per env; enable succeeds (idempotent).
cat >"${TEST_ARCH_BIN}/systemctl" <<EOF
#!/usr/bin/env bash
printf 'systemctl %s\n' "\$*" >>"$(test_arch_calls_log)"
case "\$1" in
  cat) [[ "\${TEST_UNIT_PRESENT:-0}" == 1 ]] && exit 0 || exit 1 ;;
  enable) exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod 755 -- "${TEST_ARCH_BIN}/systemctl"

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-guard.sh"
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-system.sh"
test_arch_arm_cleanup

OVERLAY="${TEST_ARCH_REPO_ROOT}/home-arch"
SYSTEM_LIB="${TEST_ARCH_REPO_ROOT}/lib/arch-system.sh"
UNIT="${OVERLAY}/.config/systemd/user/tailscale-systray.service"
AUTOSTART="${OVERLAY}/.config/autostart/tailscale-systray.desktop"
ENTRY="${OVERLAY}/.local/share/applications/tailscale-systray.desktop"
ICON="${OVERLAY}/.local/share/icons/hicolor/scalable/apps/tailscale.svg"
WORK="${TEST_ARCH_SANDBOX}/work"
mkdir -p -- "${WORK}"
reset_calls() { : >"$(test_arch_calls_log)"; }
operator_cmd="sudo tailscale set --operator=$(id -un)"

# --- Autostart: upstream unit, started at login through the autostart entry. ---
[[ -f ${UNIT} ]] || test_arch_die 'the upstream Tailscale systray unit is missing'
grep -Fq 'ExecStart=/usr/bin/tailscale systray' "${UNIT}" \
  || test_arch_die 'the unit must run the unprivileged systray binary'
[[ -f ${AUTOSTART} ]] || test_arch_die 'the systray autostart entry is missing'
grep -Fq 'Exec=/usr/bin/systemctl --user start tailscale-systray.service' "${AUTOSTART}" \
  || test_arch_die 'the autostart entry must start the unit, not a second tray process'
grep -Fq 'NoDisplay=true' "${AUTOSTART}" \
  || test_arch_die 'only the launcher entry is user-visible; the login starter stays hidden'
if find "${OVERLAY}" -type l | grep -q .; then
  test_arch_die 'the overlay must ship regular files only (the desktop deploy refuses link sources)'
fi

# --- Launcher: visible, starts the unit, and its icon resolves. ---
[[ -f ${ENTRY} ]] || test_arch_die 'the Tailscale launcher entry is missing'
grep -Fq 'Exec=/usr/bin/systemctl --user start tailscale-systray.service' "${ENTRY}" \
  || test_arch_die 'the launcher entry must start the unit (systemd keeps one instance)'
grep -Fq 'Name=Tailscale' "${ENTRY}" \
  || test_arch_die 'the launcher entry must be findable as Tailscale'
if grep -Eq '^(NoDisplay|Hidden)=true' "${ENTRY}"; then
  test_arch_die 'the launcher entry must stay visible (upstream hides only its autostart file)'
fi
grep -Fq 'Icon=tailscale' "${ENTRY}" \
  || test_arch_die 'the launcher entry must use the vendored tailscale icon'
[[ -s ${ICON} ]] || test_arch_die 'the vendored tailscale icon is missing'

# --- Wiring: the operator step runs from the services setup. ---
grep -Fq 'arch_system_setup_tailscale' "${SYSTEM_LIB}" \
  || test_arch_die 'the operator step must be wired into the services setup'

# --- Operator: installed + unit present sets the invoking user. ---
export TEST_TAILSCALE_PKG=1 TEST_UNIT_PRESENT=1
reset_calls
arch_system_setup_tailscale >/dev/null
test_arch_assert_contains "$(test_arch_calls_log)" "${operator_cmd}" \
  'setup must set the invoking user as operator'

# --- Idempotent: a healthy re-run sets the same operator again, cleanly. ---
arch_system_setup_tailscale >/dev/null
test_arch_assert_eq 2 "$(grep -c -- "${operator_cmd}" "$(test_arch_calls_log)")" \
  're-run must repeat the idempotent operator set without failing'

# --- Negative: installed + missing unit is a broken install, fails loud. ---
export TEST_UNIT_PRESENT=0
reset_calls
set +e
( arch_system_setup_tailscale >"${WORK}/setup.out" 2>&1 )
setup_status=$?
set -e
((setup_status != 0)) || test_arch_die 'missing unit with installed package must fail'
test_arch_assert_contains "${WORK}/setup.out" 'tailscaled.service' \
  'broken-install error must name the unit'
if grep -q 'tailscale set' "$(test_arch_calls_log)"; then
  test_arch_die 'broken install must fail before attempting the operator set'
fi

# --- Silent noop: deselected package touches nothing and says nothing. ---
export TEST_TAILSCALE_PKG=0 TEST_UNIT_PRESENT=0
reset_calls
tailscale_out="$(arch_system_setup_tailscale 2>&1)"
[[ -z ${tailscale_out} ]] || test_arch_die "deselected package must stay silent, got: ${tailscale_out}"
test_arch_assert_not_called sudo 'deselected package never elevates'

test_arch_assert_no_live_paths 'tailscale systray wiring'
printf 'Tailscale systray stays unit-based, launcher-visible, and operator-owned.\n'
