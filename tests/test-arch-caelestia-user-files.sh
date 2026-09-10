#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# Compositor-owned user files (.config/caelestia/hypr-user.lua and
# hypr-vars.lua): deploy as real files, never stowed. The live Hyprland
# compositor recreates these within milliseconds when missing, so no stow
# scan can own the path; upstream also defines both as user-edited.
# Covers the desktop module's deploy (fresh copy, placeholder conversion,
# legacy-symlink conversion, user content preserved, loud deaths),
# dot's overlay stow (preserves real user files while landing the stowed
# set), and the overlay verify (accepts configured real files, rejects
# symlinks, missing files, and placeholders). Real stow; sudo fail-closed.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox
test_arch_stub_command sudo

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-desktop.sh"
test_arch_arm_cleanup

export HOME="${TEST_ARCH_HOME}"
export DISTRO=arch

OVERLAY="${TEST_ARCH_REPO_ROOT}/home-arch"
USER_A='.config/caelestia/hypr-user.lua'
USER_B='.config/caelestia/hypr-vars.lua'

find "${OVERLAY}" -type f -exec sha256sum -- {} + | sort -k2 \
  >"${TEST_ARCH_SANDBOX}/overlay-source-before.txt"

# --- Deploy: fresh copy lands byte-identical as real files. ---
arch_desktop_deploy_user_files >/dev/null
for rel in "${USER_A}" "${USER_B}"; do
  [[ -f ${TEST_ARCH_HOME}/${rel} && ! -L ${TEST_ARCH_HOME}/${rel} ]] \
    || test_arch_die "fresh deploy of ${rel} is not a real file"
  cmp -s -- "${OVERLAY}/${rel}" "${TEST_ARCH_HOME}/${rel}" \
    || test_arch_die "fresh-deployed ${rel} differs from the template"
done

# --- Deploy: idempotent second run changes nothing. ---
sha256sum -- "${TEST_ARCH_HOME}/${USER_A}" "${TEST_ARCH_HOME}/${USER_B}" \
  >"${TEST_ARCH_SANDBOX}/deployed-before.txt"
arch_desktop_deploy_user_files >/dev/null
sha256sum -- "${TEST_ARCH_HOME}/${USER_A}" "${TEST_ARCH_HOME}/${USER_B}" \
  >"${TEST_ARCH_SANDBOX}/deployed-after.txt"
cmp -s -- "${TEST_ARCH_SANDBOX}/deployed-before.txt" "${TEST_ARCH_SANDBOX}/deployed-after.txt" \
  || test_arch_die 'user-file redeploy was not idempotent'

# --- Deploy: both compositor placeholder shapes convert to templates. ---
: >"${TEST_ARCH_HOME}/${USER_A}"
printf 'return {}\n' >"${TEST_ARCH_HOME}/${USER_B}"
arch_desktop_deploy_user_files >/dev/null
cmp -s -- "${OVERLAY}/${USER_A}" "${TEST_ARCH_HOME}/${USER_A}" \
  || test_arch_die 'empty placeholder hypr-user.lua was not replaced'
cmp -s -- "${OVERLAY}/${USER_B}" "${TEST_ARCH_HOME}/${USER_B}" \
  || test_arch_die 'return-{} placeholder hypr-vars.lua was not replaced'

# --- Deploy: user content is preserved verbatim. ---
printf -- '-- active monitor block\n' >>"${TEST_ARCH_HOME}/${USER_A}"
printf 'return { foo = 1 }\n' >"${TEST_ARCH_HOME}/${USER_B}"
arch_desktop_deploy_user_files >/dev/null
test_arch_assert_contains "${TEST_ARCH_HOME}/${USER_A}" \
  'active monitor block' 'deploy wiped user content from hypr-user.lua'
test_arch_assert_eq 'return { foo = 1 }' \
  "$(cat -- "${TEST_ARCH_HOME}/${USER_B}")" 'deploy rewrote non-placeholder user content'

# --- Deploy: legacy symlinks to the templates convert to real files. ---
ln -sfn -- "${OVERLAY}/${USER_A}" "${TEST_ARCH_HOME}/${USER_A}"
ln -sfn -- "${OVERLAY}/${USER_B}" "${TEST_ARCH_HOME}/${USER_B}"
arch_desktop_deploy_user_files >/dev/null
for rel in "${USER_A}" "${USER_B}"; do
  [[ -f ${TEST_ARCH_HOME}/${rel} && ! -L ${TEST_ARCH_HOME}/${rel} ]] \
    || test_arch_die "legacy symlink ${rel} was not converted to a real file"
  cmp -s -- "${OVERLAY}/${rel}" "${TEST_ARCH_HOME}/${rel}" \
    || test_arch_die "converted ${rel} differs from the template"
done

# --- Deploy: foreign symlinks die loudly instead of deploying over. ---
printf 'x\n' >"${TEST_ARCH_SANDBOX}/elsewhere.lua"
ln -sfn -- "${TEST_ARCH_SANDBOX}/elsewhere.lua" "${TEST_ARCH_HOME}/${USER_A}"
set +e
( arch_desktop_deploy_user_files >/dev/null 2>&1 )
foreign_status=$?
set -e
((foreign_status != 0)) || test_arch_die 'deploy installed over a foreign symlink'
[[ -L ${TEST_ARCH_HOME}/${USER_A} ]] \
  || test_arch_die 'failed deploy removed the foreign symlink'
rm -f -- "${TEST_ARCH_HOME}/${USER_A}"
arch_desktop_deploy_user_files >/dev/null

# --- Deploy: a directory at the target dies loudly. ---
rm -f -- "${TEST_ARCH_HOME}/${USER_B}"
mkdir -p -- "${TEST_ARCH_HOME}/${USER_B}"
set +e
( arch_desktop_deploy_user_files >/dev/null 2>&1 )
dir_status=$?
set -e
((dir_status != 0)) || test_arch_die 'deploy installed over a real directory'
rmdir -- "${TEST_ARCH_HOME}/${USER_B}"
arch_desktop_deploy_user_files >/dev/null

# --- Verify: full overlay install passes, then each user-file failure. ---
arch_desktop_install_overlay >/dev/null
arch_desktop_verify_overlay >/dev/null
: >"${TEST_ARCH_HOME}/${USER_A}"
set +e
placeholder_out="$(arch_desktop_verify_overlay 2>&1)"
placeholder_status=$?
set -e
((placeholder_status != 0)) || test_arch_die 'verify passed on a placeholder user file'
[[ ${placeholder_out} == *placeholder* ]] \
  || test_arch_die 'verify did not name the placeholder offender'
arch_desktop_deploy_user_files >/dev/null
ln -sfn -- "${OVERLAY}/${USER_B}" "${TEST_ARCH_HOME}/${USER_B}"
set +e
arch_desktop_verify_overlay >/dev/null 2>&1
legacy_status=$?
set -e
((legacy_status != 0)) || test_arch_die 'verify passed on a legacy symlinked user file'
arch_desktop_deploy_user_files >/dev/null
rm -f -- "${TEST_ARCH_HOME}/${USER_A}"
set +e
arch_desktop_verify_overlay >/dev/null 2>&1
missing_status=$?
set -e
((missing_status != 0)) || test_arch_die 'verify passed on a missing user file'
arch_desktop_deploy_user_files >/dev/null
arch_desktop_verify_overlay >/dev/null

# --- dot overlay stow: preserves real user files, lands the stowed set. ---
HOME4="${TEST_ARCH_SANDBOX}/home4"
mkdir -p -- "${HOME4}/.config/caelestia"
export HOME="${HOME4}"
printf -- '-- active monitor block\n' >"${HOME4}/${USER_A}"
: >"${HOME4}/${USER_B}"
stow_arch_overlay >/dev/null
test_arch_assert_contains "${HOME4}/${USER_A}" \
  'active monitor block' 'dot stow wiped user content from hypr-user.lua'
cmp -s -- "${OVERLAY}/${USER_B}" "${HOME4}/${USER_B}" \
  || test_arch_die 'dot stow did not convert the placeholder hypr-vars.lua'
test_arch_assert_eq "${OVERLAY}/.config/ghostty/config" \
  "$(realpath -m -- "${HOME4}/.config/ghostty/config")" 'dot stow lands the stowed set beside user files'
export HOME="${TEST_ARCH_HOME}"

# --- No source write-through from any path above. ---
find "${OVERLAY}" -type f -exec sha256sum -- {} + | sort -k2 \
  >"${TEST_ARCH_SANDBOX}/overlay-source-after.txt"
cmp -s -- "${TEST_ARCH_SANDBOX}/overlay-source-before.txt" "${TEST_ARCH_SANDBOX}/overlay-source-after.txt" \
  || test_arch_die 'user-file paths wrote through into the overlay source'

test_arch_assert_not_called sudo 'user-file deploy never elevates'
test_arch_assert_no_live_paths 'caelestia user files'
printf 'Caelestia user files deploy as real files, survive re-runs, and verify.\n'
