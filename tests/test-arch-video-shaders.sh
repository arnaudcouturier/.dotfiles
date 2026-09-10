#!/usr/bin/env bash
# shellcheck disable=SC1091 # sandbox harness computes source paths at runtime; static following is impossible by design
# lib/arch-video.sh owns the mpv shader link: package-derived directory,
# required-shader gate, symlink refusals, and the mpv parse probe. pacman
# and mpv answer from fixtures; HOME is sandboxed before sourcing because
# the module resolves its config dir from $HOME at source time.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
source "${TEST_DIR}/lib/test-arch-isolation.sh"

test_arch_make_sandbox

# shellcheck source=/dev/null
set -- help
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
# shellcheck source=/dev/null
source "${TEST_ARCH_REPO_ROOT}/lib/arch-video.sh"
test_arch_arm_cleanup

# Sanity: the module targeted the sandbox, never the live home.
[[ ${ARCH_MPV_CONFIG_DIR} == "${TEST_ARCH_SANDBOX}"/* ]] \
  || test_arch_die "video config dir escapes the sandbox: ${ARCH_MPV_CONFIG_DIR}"

SHADER_PACK="${TEST_ARCH_SANDBOX}/usr/share/shaders"
mkdir -p -- "${SHADER_PACK}"
touch -- "${SHADER_PACK}/ArtCNN_C4F16.glsl" "${SHADER_PACK}/ArtCNN_C4F32.glsl"

# Scripted pacman: -Q honors TEST_SHADER_PKG; -Ql lists the fixture pack.
cat >"${TEST_ARCH_BIN}/pacman" <<EOF
#!/usr/bin/env bash
printf 'pacman %s\n' "\$*" >>"$(test_arch_calls_log)"
case "\$*" in
  '-Q mpv-shim-default-shaders') exit "\${TEST_SHADER_PKG:-0}" ;;
  '-Ql mpv-shim-default-shaders')
    printf 'mpv-shim-default-shaders %s/ArtCNN_C4F16.glsl\n' "${SHADER_PACK}"
    printf 'mpv-shim-default-shaders %s/ArtCNN_C4F32.glsl\n' "${SHADER_PACK}"
    exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod 755 -- "${TEST_ARCH_BIN}/pacman"
test_arch_stub_command mpv
test_arch_stub_command sudo

# --- Directory derived from the package, never hardcoded. ---
test_arch_assert_eq "${SHADER_PACK}" "$(arch_video_shader_dir)" 'shader dir derived from package'

# --- Missing package dies before linking anything. ---
export TEST_SHADER_PKG=1
set +e
( arch_video_shader_dir >/dev/null 2>&1 )
missing_status=$?
set -e
((missing_status != 0)) || test_arch_die 'missing shader package resolved a directory'
export TEST_SHADER_PKG=0

# --- Renamed required shader dies listing replacements. ---
mv -- "${SHADER_PACK}/ArtCNN_C4F16.glsl" "${SHADER_PACK}/ArtCNN_C4F16-renamed.glsl"
set +e
renamed_out="$(arch_video_link_shader_pack 2>&1)"
renamed_status=$?
set -e
((renamed_status != 0)) || test_arch_die 'renamed required shader linked anyway'
printf '%s\n' "${renamed_out}" >"${TEST_ARCH_SANDBOX}/renamed.txt"
test_arch_assert_contains "${TEST_ARCH_SANDBOX}/renamed.txt" 'ArtCNN' 'rename error lists ArtCNN replacements'
mv -- "${SHADER_PACK}/ArtCNN_C4F16-renamed.glsl" "${SHADER_PACK}/ArtCNN_C4F16.glsl"

# --- Link lands and re-runs idempotently; missing optionals only warn. ---
link_out="$(arch_video_link_shader_pack 2>&1)"
printf '%s\n' "${link_out}" >"${TEST_ARCH_SANDBOX}/link.txt"
test_arch_assert_contains "${TEST_ARCH_SANDBOX}/link.txt" 'keybinds stay silent' 'absent optionals warn, not fail'
[[ -L ${ARCH_SHADER_LINK} ]] || test_arch_die 'shader link is not a symlink'
test_arch_assert_eq "${SHADER_PACK}" "$(readlink -- "${ARCH_SHADER_LINK}")" 'link points at the pack'
arch_video_link_shader_pack >/dev/null
test_arch_assert_eq "${SHADER_PACK}" "$(readlink -- "${ARCH_SHADER_LINK}")" 'relink is stable'

# --- A real directory at the link path is refused, never merged. ---
rm -- "${ARCH_SHADER_LINK}"
mkdir -p -- "${ARCH_SHADER_LINK}"
set +e
( arch_video_link_shader_pack >/dev/null 2>&1 )
realdir_status=$?
set -e
((realdir_status != 0)) || test_arch_die 'real shader dir was merged'
rmdir -- "${ARCH_SHADER_LINK}"
arch_video_link_shader_pack >/dev/null

# --- A symlinked mpv dir is refused, never followed. ---
rm -- "${ARCH_SHADER_LINK}"
mv -- "${ARCH_MPV_CONFIG_DIR}" "${TEST_ARCH_SANDBOX}/mpv-real"
ln -s -- "${TEST_ARCH_SANDBOX}/mpv-real" "${ARCH_MPV_CONFIG_DIR}"
set +e
( arch_video_link_shader_pack >/dev/null 2>&1 )
mpvlink_status=$?
set -e
((mpvlink_status != 0)) || test_arch_die 'wrote through a symlinked mpv dir'
rm -- "${ARCH_MPV_CONFIG_DIR}"
mv -- "${TEST_ARCH_SANDBOX}/mpv-real" "${ARCH_MPV_CONFIG_DIR}"
arch_video_link_shader_pack >/dev/null

# --- Parse probe: benign output passes, mpv errors fail loudly. ---
printf '# probe fixture\n' >"${ARCH_MPV_CONFIG_DIR}/mpv.conf"
printf 'jamin: opening the probe path failed as expected\n' >"${TEST_ARCH_SANDBOX}/mpv-ok.txt"
test_arch_stub_output mpv "${TEST_ARCH_SANDBOX}/mpv-ok.txt"
arch_video_probe_mpv_config >/dev/null
printf 'Error parsing option glsl-shaders: file not found\n' >"${TEST_ARCH_SANDBOX}/mpv-bad.txt"
test_arch_stub_output mpv "${TEST_ARCH_SANDBOX}/mpv-bad.txt"
set +e
bad_out="$(arch_video_probe_mpv_config 2>&1)"
bad_status=$?
set -e
((bad_status != 0)) || test_arch_die 'mpv config errors passed silently'
printf '%s\n' "${bad_out}" >"${TEST_ARCH_SANDBOX}/bad.txt"
test_arch_assert_contains "${TEST_ARCH_SANDBOX}/bad.txt" 'Error parsing' 'failure includes mpv output'

# --- Verify: complete pipeline passes, missing link fails. ---
test_arch_stub_output mpv "${TEST_ARCH_SANDBOX}/mpv-ok.txt"
arch_video_verify >/dev/null
rm -- "${ARCH_SHADER_LINK}"
set +e
( arch_video_verify >/dev/null 2>&1 )
verify_status=$?
set -e
((verify_status != 0)) || test_arch_die 'verify passed without the shader link'

test_arch_assert_not_called sudo 'video never elevates'
test_arch_assert_no_live_paths 'video pipeline'
printf 'Video shader linking stays package-derived and refuses collisions.\n'
