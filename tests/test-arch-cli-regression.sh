#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# dot Arch CLI regression on this Fedora host: arch-setup/arch-check refuse
# before any elevation, network, or mutation; removed flags stay removed;
# step selection and the Arch-only shared exclusion behave per contract.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox
# sleep stays failed-closed: begin_elevation's refresher loop then exits
# immediately instead of lingering a background sleeper per test run.
for cmd in sudo pacman dnf yay curl stow flatpak rpm systemctl efibootmgr mount mkinitcpio sleep; do
  test_arch_stub_command "${cmd}"
done

DOT="${TEST_ARCH_REPO_ROOT}/dot"

# --- arch-setup refuses on Fedora before require_user/begin_elevation. ---
set +e
setup_out="$("${DOT}" arch-setup --only gpu 2>&1)"
setup_status=$?
set -e
((setup_status != 0)) || test_arch_die 'arch-setup proceeded on Fedora'
printf '%s\n' "${setup_out}" >"${TEST_ARCH_SANDBOX}/setup-refusal.txt"
test_arch_assert_contains "${TEST_ARCH_SANDBOX}/setup-refusal.txt" 'Arch-only' 'setup refusal names the gate'

# --- arch-check refuses the same way, changing nothing. ---
set +e
check_out="$("${DOT}" arch-check --only gpu 2>&1)"
check_status=$?
set -e
((check_status != 0)) || test_arch_die 'arch-check proceeded on Fedora'
printf '%s\n' "${check_out}" >"${TEST_ARCH_SANDBOX}/check-refusal.txt"
test_arch_assert_contains "${TEST_ARCH_SANDBOX}/check-refusal.txt" 'Arch-only' 'check refusal names the gate'

# --- Neither refusal reached elevation, packages, network, or mounts. ---
for cmd in sudo pacman dnf yay curl systemctl efibootmgr mount; do
  test_arch_assert_not_called "${cmd}" "arch refusal never reaches ${cmd}"
done

# --- Removed flags stay removed: --allow-without-desktop is unknown. ---
set +e
removed_out="$("${DOT}" arch-setup --allow-without-desktop 2>&1)"
removed_status=$?
set -e
((removed_status != 0)) || test_arch_die '--allow-without-desktop was accepted'
printf '%s\n' "${removed_out}" >"${TEST_ARCH_SANDBOX}/removed.txt"
test_arch_assert_contains "${TEST_ARCH_SANDBOX}/removed.txt" 'Unknown option' 'removed flag dies as unknown'

# --- Empty --only value dies at the CLI layer. ---
set +e
"${DOT}" arch-check --only '' >/dev/null 2>&1
empty_cli_status=$?
set -e
((empty_cli_status != 0)) || test_arch_die 'empty --only value was accepted'

# --- Pure unit surface: step selection and the supersede predicate. ---
set -- help
# shellcheck source=/dev/null
source "${DOT}" >/dev/null
test_arch_arm_cleanup
export DISTRO BUNDLE_FILE

test_arch_assert_eq $'system\ngpu\nsnapshots\ndesktop\ngreeter\nvideo\nlimine' \
  "$(arch_selected_steps all)" 'canonical step order'
test_arch_assert_eq $'system\nvideo' \
  "$(arch_selected_steps 'video,system')" 'selection returns canonical order'
set +e
( arch_selected_steps 'bogus' >/dev/null 2>&1 )
unknown_status=$?
set -e
((unknown_status != 0)) || test_arch_die 'unknown step accepted'

# --- H2: invalid --only must die through the real check command, never ---
# --- silently run zero steps (mapfile masks subshell death under set -e). ---
# DISTRO/BUNDLE_FILE are preset exactly as detect_distro would leave them
# on Arch (main dispatch always runs detection first in production).
DISTRO=arch
BUNDLE_FILE="${DOTFILES_DIR}/packages/arch.bundle"
set +e
check_bogus_out="$(cmd_arch_check --only bogus 2>&1)"
check_bogus_status=$?
set -e
((check_bogus_status != 0)) || test_arch_die 'H2: arch-check --only bogus succeeded with zero steps'
printf '%s\n' "${check_bogus_out}" >"${TEST_ARCH_SANDBOX}/check-bogus.txt"
test_arch_assert_contains "${TEST_ARCH_SANDBOX}/check-bogus.txt" 'Unknown arch step' 'H2: bogus step named'

# --- H2: same masking site in the setup command (full stubbed run). ---
test_arch_stub_command herdr
cat >"${TEST_ARCH_BIN}/yay" <<EOF
#!/usr/bin/env bash
printf 'yay %s\n' "\$*" >>"$(test_arch_calls_log)"
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/yay"
cat >"${TEST_ARCH_BIN}/sudo" <<EOF
#!/usr/bin/env bash
printf 'sudo %s\n' "\$*" >>"$(test_arch_calls_log)"
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/sudo"
# Real stow for the stow phases (sandbox HOME keeps it hermetic); the
# earlier fail-closed stub only guarded the refusal paths above.
rm -f -- "${TEST_ARCH_BIN}/stow"
HOME2="${TEST_ARCH_SANDBOX}/setup-home"
mkdir -p -- "${HOME2}"
export HOME="${HOME2}"
set +e
setup_bogus_out="$(cmd_arch_setup --only bogus 2>&1)"
setup_bogus_status=$?
set -e
end_elevation
((setup_bogus_status != 0)) || test_arch_die 'H2: arch-setup --only bogus succeeded with zero steps'
printf '%s\n' "${setup_bogus_out}" >"${TEST_ARCH_SANDBOX}/setup-bogus.txt"
test_arch_assert_contains "${TEST_ARCH_SANDBOX}/setup-bogus.txt" 'Unknown arch step' 'H2: setup bogus step named'
export HOME="${TEST_ARCH_HOME}"
DISTRO=fedora
arch_path_is_superseded '.config/ghostty/config' && test_arch_die 'Fedora supersedes shared ghostty'
arch_path_is_superseded '.config/hypr/input.lua' && test_arch_die 'Fedora supersedes shared input.lua'
DISTRO=arch
arch_path_is_superseded '.config/ghostty/config' || test_arch_die 'Arch does not supersede shared ghostty'
arch_path_is_superseded '.config/hypr/input.lua' || test_arch_die 'Arch does not supersede shared input.lua'
arch_path_is_superseded '.config/fish/config.fish' && test_arch_die 'Arch supersedes shared fish config'

# --- Greeter gate holds shut by default: fresh shell, empty tree, no pass. ---
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-desktop.sh"
test_arch_arm_cleanup
set +e
shut_out="$(HOME="${TEST_ARCH_HOME}" bash -c 'cd -- "${0}"; set -- help; source ./dot >/dev/null; arch_require_desktop_verified' "${TEST_ARCH_REPO_ROOT}" 2>&1)"
shut_status=$?
set -e
((shut_status != 0)) || test_arch_die 'desktop gate passed without a deployed tree'
printf '%s\n' "${shut_out}" >"${TEST_ARCH_SANDBOX}/gate-shut.txt"
test_arch_assert_contains "${TEST_ARCH_SANDBOX}/gate-shut.txt" 'incomplete' 'shut gate names the incomplete overlay'

# --- Finalized bug: re-sourcing the desktop module must be safe. ---
# cmd_arch_setup sources it in the desktop step, then the greeter step
# calls arch_require_desktop_verified which sources it again; readonly
# globals must not turn the canonical full-setup flow into a fatal error.
set +e
resrc_out="$(arch_require_desktop_verified 2>&1)"
resrc_status=$?
set -e
((resrc_status != 0)) || test_arch_die 'desktop gate passed without a deployed tree on re-source'
printf '%s\n' "${resrc_out}" >"${TEST_ARCH_SANDBOX}/gate-resrc.txt"
test_arch_assert_contains "${TEST_ARCH_SANDBOX}/gate-resrc.txt" 'incomplete' 're-sourced gate still names the incomplete overlay'

test_arch_assert_no_live_paths 'arch CLI regression'
printf 'Arch CLI refuses Fedora early; selection, exclusion, and gate hold.\n'
