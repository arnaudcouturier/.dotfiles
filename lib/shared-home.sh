#!/usr/bin/env bash
# Shared user configuration lifecycle; sourced by dot, never run elevated.
set -euo pipefail

# Only retire links into this checkout. Local files and foreign links are not ours.
# The manifest also detaches old stowed skills before npx takes ownership.
prune_retired_home_links() {
  local rel target resolved shared fedora
  while IFS= read -r rel; do
    [[ -n ${rel} && ${rel} != \#* ]] || continue
    target="${HOME}/${rel}"
    [[ -L ${target} ]] || continue
    resolved="$(realpath -m -- "${target}")"
    shared="$(realpath -m -- "${HOME_DIR}/${rel}")"
    fedora="$(realpath -m -- "${FEDORA_HOME_OVERLAY_DIR}/${rel}")"
    if [[ ${resolved} == "${shared}" || ( ${DISTRO:-} == fedora && ${resolved} == "${fedora}" ) ]]; then
      log_info "Removing retired dotfiles link ${target}"
      rm -f -- "${target}"
    fi
  done <"${DOTFILES_DIR}/config/retired-home-links.txt"
}

sync_agent_skills() {
  require_command npx
  # Refresh order: curated repo sources first, then upstream sets, so the
  # requested upstream collections win any name overlaps.
  # Refresh in place: no version pin, matching the upstream install docs.
  local -a skill_install_flags=(-g -y -a opencode claude-code codex pi)
  npx -y skills add "${HOME_DIR}/.agents/skills" --skill '*' "${skill_install_flags[@]}"
  npx -y skills add mattpocock/skills --skill '*' "${skill_install_flags[@]}"
  npx -y skills add herdrdev/herdr --skill herdr "${skill_install_flags[@]}"
}
