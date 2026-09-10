#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# Opt-in Arch gaming stack: Steam, GameMode, MangoHud/GOverlay, Gamescope,
# NT-sync, 32-bit Vulkan loader, Proton tools (repo) plus protonplus and
# vkbasalt (AUR). Setup asks once while steam is absent (default No, never
# blocks without a terminal) and repairs silently once selected; verify
# treats absent as valid and partial as drift. GameMode group membership
# follows the package. Installs prove their exact commands through logging
# stubs (nothing executes).
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

# pacman stub: -Q answers from TEST_INSTALLED (space-separated names);
# installs only log (success by systemd/pacman contract in this sandbox).
cat >"${TEST_ARCH_BIN}/pacman" <<EOF
#!/usr/bin/env bash
printf 'pacman %s\n' "\$*" >>"$(test_arch_calls_log)"
if [[ "\$1" == -Q ]]; then
  pkg="\${@: -1}"
  case " \${TEST_INSTALLED:-} " in
    *" \${pkg} "*) exit 0 ;;
    *) exit 1 ;;
  esac
fi
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/pacman"

# pacman-conf stub: multilib reported iff TEST_MULTILIB=1.
cat >"${TEST_ARCH_BIN}/pacman-conf" <<EOF
#!/usr/bin/env bash
printf 'pacman-conf %s\n' "\$*" >>"$(test_arch_calls_log)"
[[ "\${TEST_MULTILIB:-0}" == 1 ]] && printf 'multilib\n'
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/pacman-conf"

# yay stub: AUR installs only log.
cat >"${TEST_ARCH_BIN}/yay" <<EOF
#!/usr/bin/env bash
printf 'yay %s\n' "\$*" >>"$(test_arch_calls_log)"
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/yay"

# id stub: fixed user, groups from TEST_GROUPS.
cat >"${TEST_ARCH_BIN}/id" <<EOF
#!/usr/bin/env bash
printf 'id %s\n' "\$*" >>"$(test_arch_calls_log)"
if [[ "\$1" == -un ]]; then
  printf 'testuser\n'
elif [[ "\$1" == -nG ]]; then
  printf '%s\n' "\${TEST_GROUPS:-testuser}"
fi
exit 0
EOF
chmod 755 -- "${TEST_ARCH_BIN}/id"

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-system.sh"
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-gaming.sh"
test_arch_arm_cleanup

# Hermetic multilib ensure: the real system-module function edits
# /etc/pacman.conf, so tests override it with a logging stub (the fallback
# branch without the system module is covered separately below).
arch_system_setup_pacman_options() {
  printf 'pacman-options ensured\n' >>"$(test_arch_calls_log)"
}

GAMING_LIB="${TEST_ARCH_REPO_ROOT}/lib/arch-gaming.sh"
WORK="${TEST_ARCH_SANDBOX}/work"
mkdir -p -- "${WORK}"
reset_calls() { : >"$(test_arch_calls_log)"; }
ALL_PKGS='steam gamemode lib32-gamemode goverlay lib32-mangohud gamescope ntsync-autoload lib32-vulkan-icd-loader protontricks protonplus vkbasalt lib32-vkbasalt'

# --- Static: the archive's package set is pinned in the module. ---
for pkg in ${ALL_PKGS}; do
  grep -Fq -- "${pkg}" "${GAMING_LIB}" \
    || test_arch_die "gaming module must carry ${pkg}"
done
grep -Fq 'arch_gaming_setup' "${GAMING_LIB}" || test_arch_die 'setup entry missing'
grep -Fq 'arch_gaming_verify' "${GAMING_LIB}" || test_arch_die 'verify entry missing'

# --- Static: dot wires the step between gpu and snapshots. ---
grep -Fq 'ARCH_SETUP_STEPS=(system gpu gaming snapshots desktop greeter video limine)' "${TEST_ARCH_REPO_ROOT}/dot" \
  || test_arch_die 'gaming must sit between gpu and snapshots in ARCH_SETUP_STEPS'
grep -Fq 'arch_load_module arch-gaming.sh' "${TEST_ARCH_REPO_ROOT}/dot" \
  || test_arch_die 'dot must load the gaming module'
grep -Fq 'gaming) arch_gaming_setup ;;' "${TEST_ARCH_REPO_ROOT}/dot" \
  || test_arch_die 'arch-setup must dispatch the gaming step'
grep -Fq 'gaming) arch_gaming_verify || failed=1 ;;' "${TEST_ARCH_REPO_ROOT}/dot" \
  || test_arch_die 'arch-check must verify the gaming step'
grep -Fq 'system gpu gaming snapshots desktop greeter video limine' "${TEST_ARCH_REPO_ROOT}/dot" \
  || test_arch_die 'help must list the gaming step'

# --- Declined: absent + "n" skips with info, installs nothing. ---
export TEST_INSTALLED='' TEST_GROUPS='testuser' TEST_MULTILIB=1
printf 'n\n' >"${WORK}/answer-n"
export ARCH_GAMING_TTY="${WORK}/answer-n"
reset_calls
gaming_out="$(arch_gaming_setup 2>&1)"
[[ ${gaming_out} == *'not selected'* ]] || test_arch_die "declined setup must say it skips, got: ${gaming_out}"
test_arch_assert_not_called yay 'declined setup never reaches the AUR'
if grep -q '^pacman -S' "$(test_arch_calls_log)"; then
  test_arch_die 'declined setup must not install repo packages'
fi
test_arch_assert_not_called sudo 'declined setup never elevates'

# --- No terminal: absent + unusable TTY also skips without hanging. ---
export ARCH_GAMING_TTY="${WORK}/does-not-exist"
reset_calls
arch_gaming_setup >/dev/null 2>&1
if grep -q '^pacman -S' "$(test_arch_calls_log)"; then
  test_arch_die 'terminal-less setup must not install anything'
fi
test_arch_assert_not_called yay 'terminal-less setup never reaches the AUR'

# --- Accepted: absent + "y" installs repo then AUR with exact commands. ---
printf 'y\n' >"${WORK}/answer-y"
export ARCH_GAMING_TTY="${WORK}/answer-y"
reset_calls
arch_gaming_setup >/dev/null 2>&1
test_arch_assert_contains "$(test_arch_calls_log)" 'pacman-options ensured' 'setup must ensure multilib first'
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo pacman -Syu --needed --noconfirm -- steam' \
  'setup must install the repo stack with a full upgrade'
for pkg in gamemode goverlay gamescope protontricks; do
  test_arch_assert_contains "$(test_arch_calls_log)" "${pkg}" "repo install must include ${pkg}"
done
test_arch_assert_contains "$(test_arch_calls_log)" 'yay -S --aur --needed -- protonplus' \
  'setup must install the AUR trio after the repo stack'
for pkg in vkbasalt lib32-vkbasalt; do
  test_arch_assert_contains "$(test_arch_calls_log)" "${pkg}" "AUR install must include ${pkg}"
done

# --- Selected before: present stack repairs without any prompt. ---
export TEST_INSTALLED="${ALL_PKGS}" ARCH_GAMING_TTY="${WORK}/does-not-exist"
reset_calls
arch_gaming_setup >/dev/null 2>&1
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo pacman -Syu --needed --noconfirm -- steam' \
  'installed stack must repair without asking'

# --- GameMode group: member is silent, non-member is repaired with a warning. ---
export TEST_INSTALLED="${ALL_PKGS}" TEST_GROUPS='testuser gamemode'
reset_calls
group_out="$(arch_gaming_setup 2>&1)"
if grep -q 'usermod' "$(test_arch_calls_log)"; then
  test_arch_die 'group member must not be re-added'
fi
export TEST_GROUPS='testuser'
reset_calls
group_out="$(arch_gaming_setup 2>&1)"
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo usermod -aG gamemode testuser' \
  'non-member must be added to the gamemode group'
[[ ${group_out} == *'log out and back in'* ]] || test_arch_die 'group repair must warn about re-login'

# --- Setup without the system module and multilib off dies with a pointer. ---
export TEST_INSTALLED="${ALL_PKGS}" TEST_MULTILIB=0
reset_calls
set +e
( unset -f arch_system_setup_pacman_options; arch_gaming_setup >"${WORK}/setup-nomultilib.out" 2>&1 )
setup_status=$?
set -e
((setup_status != 0)) || test_arch_die 'multilib off without the system module must fail'
test_arch_assert_contains "${WORK}/setup-nomultilib.out" '--only system' \
  'multilib failure must point at the system step'
export TEST_MULTILIB=1

# --- Verify: absent is valid and quiet. ---
export TEST_INSTALLED='' TEST_GROUPS='testuser'
arch_gaming_verify >"${WORK}/verify-absent.out" 2>&1 || test_arch_die 'absent stack must verify clean'
if grep -qi 'missing' "${WORK}/verify-absent.out"; then
  test_arch_die 'absent stack must report nothing missing'
fi

# --- Verify: full stack with membership passes quietly. ---
export TEST_INSTALLED="${ALL_PKGS}" TEST_GROUPS='testuser gamemode'
arch_gaming_verify >"${WORK}/verify-full.out" 2>&1 || test_arch_die 'complete stack must verify clean'
if grep -qi 'missing' "${WORK}/verify-full.out"; then
  test_arch_die 'complete stack must report nothing missing'
fi

# --- Verify: partial stack names each missing package. ---
export TEST_INSTALLED='steam gamemode' TEST_GROUPS='testuser gamemode'
set +e
arch_gaming_verify >"${WORK}/verify-partial.out" 2>&1
verify_status=$?
set -e
((verify_status != 0)) || test_arch_die 'partial stack must fail verification'
test_arch_assert_contains "${WORK}/verify-partial.out" 'Gaming package missing: gamescope' \
  'verify must name the missing package'

# --- Verify: installed gamemode without membership fails distinctly. ---
export TEST_INSTALLED="${ALL_PKGS}" TEST_GROUPS='testuser'
set +e
arch_gaming_verify >"${WORK}/verify-group.out" 2>&1
verify_status=$?
set -e
((verify_status != 0)) || test_arch_die 'missing group membership must fail verification'
test_arch_assert_contains "${WORK}/verify-group.out" 'gamemode group' \
  'verify must report the missing group membership'

test_arch_assert_no_live_paths 'gaming stack'
printf 'Gaming stack is opt-in, repairs idempotently, and verifies distinctly.\n'
