#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# Fedora gaming: opt-in, official packages only, Arch machinery mirrored.
# Setup asks once while steam is absent (default No, never blocks without a
# terminal) and repairs silently once selected; verify treats absent as valid
# and partial as drift. Installs prove their exact commands through logging
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

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/fedora-gaming.sh"
test_arch_arm_cleanup

GAMING_LIB="${TEST_ARCH_REPO_ROOT}/lib/fedora-gaming.sh"
WORK="${TEST_ARCH_SANDBOX}/work"
mkdir -p -- "${WORK}"
reset_calls() { : >"$(test_arch_calls_log)"; }
ALL_PKGS='steam gamemode goverlay gamescope mangohud protontricks'

# --- Static: the official package set is pinned in the module. ---
for pkg in ${ALL_PKGS}; do
  grep -Fq -- "${pkg}" "${GAMING_LIB}" \
    || test_arch_die "gaming module must carry ${pkg}"
done
grep -Fq 'fedora_gaming_setup' "${GAMING_LIB}" || test_arch_die 'setup entry missing'
grep -Fq 'fedora_gaming_verify' "${GAMING_LIB}" || test_arch_die 'verify entry missing'
# Official-sources rule: nothing in the module's code may configure a
# third-party repo; comments naming the exclusion are fine.
if sed 's/#.*//' "${GAMING_LIB}" | grep -Eqi 'copr|terrapkg'; then
  test_arch_die 'gaming module must not reference third-party repositories'
fi

# --- Static: dot wires the Fedora verbs and steps. ---
grep -Fq 'FEDORA_SETUP_STEPS=(gaming)' "${TEST_ARCH_REPO_ROOT}/dot" \
  || test_arch_die 'dot must declare the Fedora step list'
grep -Fq 'fedora_load_module fedora-gaming.sh' "${TEST_ARCH_REPO_ROOT}/dot" \
  || test_arch_die 'dot must load the fedora-gaming module'
grep -Fq 'gaming) fedora_gaming_setup ;;' "${TEST_ARCH_REPO_ROOT}/dot" \
  || test_arch_die 'fedora-setup must dispatch the gaming step'
grep -Fq 'gaming) fedora_gaming_verify || failed=1 ;;' "${TEST_ARCH_REPO_ROOT}/dot" \
  || test_arch_die 'fedora-check must verify the gaming step'
grep -Fq 'fedora-setup) detect_distro; cmd_fedora_setup "$@" ;;' "${TEST_ARCH_REPO_ROOT}/dot" \
  || test_arch_die 'main must dispatch fedora-setup'
grep -Fq 'fedora-check) detect_distro; cmd_fedora_check "$@" ;;' "${TEST_ARCH_REPO_ROOT}/dot" \
  || test_arch_die 'main must dispatch fedora-check'

# --- Refusal: the Fedora step machinery dies on Arch, unchanged. ---
set +e
refusal="$(DISTRO=arch bash -c 'cd -- "${0}"; set -- help; source ./dot >/dev/null; cmd_fedora_setup' "${TEST_ARCH_REPO_ROOT}" 2>&1)"
refusal_status=$?
set -e
((refusal_status != 0)) || test_arch_die 'fedora-setup proceeded on Arch'
test_arch_assert_contains <(printf '%s\n' "${refusal}") 'Fedora-only' 'refusal names the Fedora-only gate'

# --- Declined: absent + "n" skips with info, installs nothing. ---
export TEST_INSTALLED='' DISTRO=fedora
printf 'n\n' >"${WORK}/answer-n"
export FEDORA_GAMING_TTY="${WORK}/answer-n"
reset_calls
gaming_out="$(fedora_gaming_setup 2>&1)"
[[ ${gaming_out} == *'not selected'* ]] || test_arch_die "declined setup must say it skips, got: ${gaming_out}"
test_arch_assert_not_called sudo 'declined setup never elevates'
if grep -q '^dnf ' "$(test_arch_calls_log)"; then
  test_arch_die 'declined setup must not install anything'
fi

# --- No terminal: absent + unusable TTY also skips without hanging. ---
export FEDORA_GAMING_TTY="${WORK}/does-not-exist"
reset_calls
fedora_gaming_setup >/dev/null 2>&1
if grep -q '^dnf ' "$(test_arch_calls_log)"; then
  test_arch_die 'terminal-less setup must not install anything'
fi

# --- Accepted: absent + "y" enables RPM Fusion then installs exactly the ---
# --- official stack.                                                      ---
printf 'y\n' >"${WORK}/answer-y"
export FEDORA_GAMING_TTY="${WORK}/answer-y"
reset_calls
fedora_gaming_setup >/dev/null 2>&1
test_arch_assert_contains "$(test_arch_calls_log)" 'rpmfusion-free-release' \
  'setup must enable RPM Fusion before the stack'
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo dnf install -y -- steam' \
  'setup must install the stack in one official transaction'
for pkg in gamemode goverlay gamescope mangohud protontricks; do
  test_arch_assert_contains "$(test_arch_calls_log)" "${pkg}" "install must include ${pkg}"
done

# --- Selected before: present stack repairs without any prompt. ---
export TEST_INSTALLED="${ALL_PKGS} rpmfusion-free-release rpmfusion-nonfree-release" FEDORA_GAMING_TTY="${WORK}/does-not-exist"
reset_calls
repair_out="$(fedora_gaming_setup 2>&1)"
# log_ok speaks on stdout; the calls log only proves what the stubs saw.
test_arch_assert_contains <(printf '%s\n' "${repair_out}") 'RPM Fusion repositories already configured.' \
  'repair must skip re-adding RPM Fusion'
if grep -q 'mirrors.rpmfusion.org' "$(test_arch_calls_log)"; then
  test_arch_die 'repair must not re-install the RPM Fusion release packages'
fi
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo dnf install -y -- steam' \
  'installed stack must repair without asking'

# --- Verify: absent is valid and quiet. ---
export TEST_INSTALLED=''
fedora_gaming_verify >"${WORK}/verify-absent.out" 2>&1 || test_arch_die 'absent stack must verify clean'
if grep -qi 'missing' "${WORK}/verify-absent.out"; then
  test_arch_die 'absent stack must report nothing missing'
fi

# --- Verify: full stack passes quietly. ---
export TEST_INSTALLED="${ALL_PKGS}"
fedora_gaming_verify >"${WORK}/verify-full.out" 2>&1 || test_arch_die 'complete stack must verify clean'
if grep -qi 'missing' "${WORK}/verify-full.out"; then
  test_arch_die 'complete stack must report nothing missing'
fi

# --- Verify: partial stack names each missing package. ---
export TEST_INSTALLED='steam gamemode'
set +e
fedora_gaming_verify >"${WORK}/verify-partial.out" 2>&1
verify_status=$?
set -e
((verify_status != 0)) || test_arch_die 'partial stack must fail verification'
test_arch_assert_contains "${WORK}/verify-partial.out" 'Gaming package missing: gamescope' \
  'verify must name the missing package'

test_arch_assert_no_live_paths 'fedora gaming stack'
printf 'Fedora gaming stack is opt-in, official-only, repairs idempotently, and verifies distinctly.\n'
