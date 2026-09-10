#!/usr/bin/env bash
# lib/arch-video.sh — mpv plus the CNN shader pack link.
#
# mpv is this Arch desktop's video upscaler: browser video hands off to mpv,
# where libplacebo plus a CNN shader doubles luma instead of interpolating.
# The shader directory is derived from the installed package on every run, so
# a package rename surfaces as a loud error, never a dangling link.

set -euo pipefail

readonly ARCH_MPV_CONFIG_DIR="${HOME}/.config/mpv"
readonly ARCH_SHADER_LINK="${HOME}/.config/mpv/shaders"
readonly ARCH_REQUIRED_SHADER=ArtCNN_C4F16.glsl
readonly ARCH_OPTIONAL_SHADERS=(
  ArtCNN_C4F32.glsl
  FSRCNNX_x2_16-0-4-1.glsl
  Anime4K_Clamp_Highlights.glsl
  Anime4K_Restore_CNN_M.glsl
  Anime4K_Upscale_CNN_x2_M.glsl
  Anime4K_AutoDownscalePre_x2.glsl
  Anime4K_AutoDownscalePre_x4.glsl
  Anime4K_Upscale_CNN_x2_S.glsl
)

# Resolve the on-disk shader directory from the installed package. The
# upstream prefix has moved before; deriving beats hardcoding.
arch_video_shader_dir() {
  require_command pacman
  pacman -Q mpv-shim-default-shaders >/dev/null 2>&1 \
    || die 'mpv-shim-default-shaders is not installed. Run ./dot arch-setup after the bundle installs.'
  local dir
  dir="$(pacman -Ql mpv-shim-default-shaders 2>/dev/null \
    | awk '$2 ~ /\.glsl$/ { sub(/\/[^\/]*$/, "", $2); print $2; exit }')"
  [[ -n ${dir} && -d ${dir} ]] \
    || die 'mpv-shim-default-shaders ships no .glsl files; the shader directory is unresolvable.'
  printf '%s\n' "${dir}"
}

# Point ~/.config/mpv/shaders at the pack. Refuses a real directory or a
# symlinked mpv dir rather than merging or following either.
arch_video_link_shader_pack() {
  require_command mpv
  local dir missing=() shader
  dir="$(arch_video_shader_dir)"
  [[ -e ${dir}/${ARCH_REQUIRED_SHADER} ]] \
    || die "${ARCH_REQUIRED_SHADER} is missing from ${dir}; mpv.conf auto-applies it below 1440p. List ${dir}/ArtCNN* and update mpv.conf plus this module."
  for shader in "${ARCH_OPTIONAL_SHADERS[@]}"; do
    [[ -e ${dir}/${shader} ]] || missing+=("${shader}")
  done
  ((${#missing[@]} == 0)) \
    || log_warn "Shaders named by input.conf but absent from ${dir}: ${missing[*]}. Those keybinds stay silent."
  [[ ! -L ${ARCH_MPV_CONFIG_DIR} && ! -e ${ARCH_MPV_CONFIG_DIR} ]] || true
  if [[ -L ${ARCH_MPV_CONFIG_DIR} ]]; then
    die "Refusing to write through a symlinked mpv dir: ${ARCH_MPV_CONFIG_DIR}"
  fi
  mkdir -p -- "${ARCH_MPV_CONFIG_DIR}"
  if [[ -e ${ARCH_SHADER_LINK} && ! -L ${ARCH_SHADER_LINK} ]]; then
    die "${ARCH_SHADER_LINK} is a real directory. Move your shaders aside, then rerun ./dot arch-setup."
  fi
  ln -sfn -- "${dir}" "${ARCH_SHADER_LINK}"
  log_ok "${ARCH_SHADER_LINK} -> ${dir}"
}

# Ask mpv to parse its own configs against a nonexistent path: it reads
# mpv.conf and input.conf, fails to open the path (expected), and exits. Only
# mpv's own config errors count; the exit status itself is meaningless here.
arch_video_probe_mpv_config() {
  [[ -f ${ARCH_MPV_CONFIG_DIR}/mpv.conf ]] \
    || die "${ARCH_MPV_CONFIG_DIR}/mpv.conf is missing. The home overlay ships it; its installer runs before this step."
  local output
  output="$(mpv --vo=null --ao=null --force-window=no "${TMPDIR:-/tmp}/arch-video-probe-does-not-exist" 2>&1 || true)"
  grep -Eq 'Error parsing|option not found' <<<"${output}" \
    && die "mpv rejects its configuration: ${output//$'\n'/; }"
  log_ok 'mpv parses mpv.conf and input.conf without errors.'
}

# Link the pack, then prove the configs parse. Safe to re-run.
arch_video_setup() {
  arch_video_link_shader_pack
  arch_video_probe_mpv_config
}

# Check the video pipeline without changing anything. Reports drift; never writes.
arch_video_verify() {
  local failed=0
  if [[ ! -L ${ARCH_SHADER_LINK} ]]; then
    log_error "${ARCH_SHADER_LINK} is not a symlink to the shader pack."
    return 1
  fi
  [[ -e ${ARCH_SHADER_LINK}/${ARCH_REQUIRED_SHADER} ]] \
    || { log_error "Shader link misses ${ARCH_REQUIRED_SHADER}."; failed=1; }
  if [[ -f ${ARCH_MPV_CONFIG_DIR}/mpv.conf ]]; then
    local output
    output="$(mpv --vo=null --ao=null --force-window=no "${TMPDIR:-/tmp}/arch-video-probe-does-not-exist" 2>&1 || true)"
    grep -Eq 'Error parsing|option not found' <<<"${output}" \
      && { log_error "mpv rejects its configuration: ${output//$'\n'/; }"; failed=1; }
  else
    log_error "${ARCH_MPV_CONFIG_DIR}/mpv.conf is missing."
    failed=1
  fi
  return "${failed}"
}
