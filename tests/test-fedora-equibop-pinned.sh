#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# Fedora Equibop pin: the bundle installs the Equicord vendor RPM while Terra
# ships a higher-tagged rebuild (1.fc44 over the vendor's bare 1), so every
# `dnf upgrade` used to swap the working vendor build for Terra's — whose
# update-alternatives %postun deletes /usr/bin/equibop and leaves both
# launcher entries dead. The desktop module therefore excludes the name from
# Terra on every setup run, and verify fails loudly while the exclusion is
# absent. Installs prove their exact commands through logging stubs (nothing
# executes).
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

# rpm stub: -q answers from TEST_INSTALLED (space-separated names).
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
source "${TEST_ARCH_REPO_ROOT}/lib/fedora-desktop.sh"
test_arch_arm_cleanup

DESKTOP_LIB="${TEST_ARCH_REPO_ROOT}/lib/fedora-desktop.sh"
BUNDLE="${TEST_ARCH_REPO_ROOT}/packages/fedora.bundle"
WORK="${TEST_ARCH_SANDBOX}/work"
mkdir -p -- "${WORK}"
reset_calls() { : >"$(test_arch_calls_log)"; }
DESKTOP_PKGS='umbriel-nightly noctalia ghostty bibata-cursor-theme xwayland-satellite xdg-desktop-portal-gtk gnome-keyring gnome-keyring-pam'

# Stowed Umbriel entrypoint fixture: the repo's real file, as stow deploys it.
mkdir -p -- "${HOME}/.config/umbriel"
cp -- "${TEST_ARCH_REPO_ROOT}/home-fedora/.config/umbriel/config.toml" "${HOME}/.config/umbriel/config.toml"

# --- Static: exactly one Equibop entry, and it stays the pinned vendor RPM.
# A `repo "equibop"` would resolve from Terra (the shadowing rebuild) on a
# Terra-enabled machine and fail on a fresh one (Terra lands in fedora-setup,
# after the bundle installs), so the vendor pin plus the exclusion is the
# only stable combination.
test_arch_assert_eq 1 "$(grep -c -i 'equibop' "${BUNDLE}")" 'fedora.bundle must carry exactly one equibop entry'
grep -Eq '^rpm "equibop" "https://github.com/Equicord/Equibop/' "${BUNDLE}" \
  || test_arch_die 'fedora.bundle must pin equibop to the Equicord vendor RPM'
grep -Eq '^repo "equibop"' "${BUNDLE}" \
  && test_arch_die 'a repo equibop entry would resolve from the shadowing Terra rebuild'

# --- Static: the desktop module owns the Terra exclusion. ---
grep -Fq 'fedora_desktop_exclude_pinned_from_terra' "${DESKTOP_LIB}" \
  || test_arch_die 'desktop module must carry the Terra exclusion step'
grep -Fq 'terra.excludepkgs=equibop' "${DESKTOP_LIB}" \
  || test_arch_die 'desktop module must exclude equibop from Terra'
grep -Fq 'FEDORA_TERRA_REPO_FILE' "${DESKTOP_LIB}" \
  || test_arch_die 'desktop verify must read the Terra repo file through a test seam'

# --- Fresh setup: absent Terra bootstraps, then the exclusion converges. ---
export DISTRO=fedora TEST_INSTALLED=''
reset_calls
fedora_desktop_setup >/dev/null 2>&1
test_arch_assert_contains "$(test_arch_calls_log)" 'repofrompath' \
  'fresh setup must bootstrap the Terra release package'
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo dnf config-manager setopt terra.excludepkgs=equibop' \
  'fresh setup must exclude equibop from Terra'

# --- Repair setup: present Terra skips the bootstrap but still converges
# the exclusion. (The old early-return skipped everything past the release
# check, so machines that enabled Terra before the exclusion existed never
# repaired — the class of machine that reported dead launchers.)
export TEST_INSTALLED="terra-release ${DESKTOP_PKGS}"
reset_calls
repair_out="$(fedora_desktop_setup 2>&1)"
test_arch_assert_contains <(printf '%s\n' "${repair_out}") 'Terra repository already configured.' \
  'repair must skip re-adding Terra'
if grep -q 'repofrompath' "$(test_arch_calls_log)"; then
  test_arch_die 'repair must not re-bootstrap the Terra release package'
fi
test_arch_assert_contains "$(test_arch_calls_log)" 'sudo dnf config-manager setopt terra.excludepkgs=equibop' \
  'repair must still converge the Terra exclusion'

# --- Verify: full stack plus the exclusion passes quietly. ---
printf '[terra]\nname=Terra 44\nenabled=1\nexcludepkgs=equibop\n' >"${WORK}/terra-excluded.repo"
export FEDORA_TERRA_REPO_FILE="${WORK}/terra-excluded.repo"
fedora_desktop_verify >"${WORK}/verify-excluded.out" 2>&1 \
  || test_arch_die 'complete desktop with the Terra exclusion must verify clean'

# --- Verify: an open Terra fails distinctly. ---
printf '[terra]\nname=Terra 44\nenabled=1\n' >"${WORK}/terra-open.repo"
export FEDORA_TERRA_REPO_FILE="${WORK}/terra-open.repo"
set +e
fedora_desktop_verify >"${WORK}/verify-open.out" 2>&1
open_status=$?
set -e
((open_status != 0)) || test_arch_die 'an open Terra must fail verification'
test_arch_assert_contains "${WORK}/verify-open.out" 'Terra still serves equibop' \
  'verify must name the shadowing Terra entry'

# --- Verify: an exclusion in the wrong section does not protect upgrades. ---
printf '[terra]\nname=Terra 44\nenabled=1\n\n[terra-source]\nname=Terra source\nenabled=0\nexcludepkgs=equibop\n' \
  >"${WORK}/terra-wrong-section.repo"
export FEDORA_TERRA_REPO_FILE="${WORK}/terra-wrong-section.repo"
set +e
fedora_desktop_verify >"${WORK}/verify-section.out" 2>&1
section_status=$?
set -e
((section_status != 0)) || test_arch_die 'an exclusion outside [terra] must fail verification'
test_arch_assert_contains "${WORK}/verify-section.out" 'Terra still serves equibop' \
  'verify must scope the exclusion to the [terra] section'

test_arch_assert_no_live_paths 'fedora equibop pin'
printf 'Fedora keeps the pinned Equibop vendor RPM by excluding the name from Terra, and verify names an open Terra.\n'
