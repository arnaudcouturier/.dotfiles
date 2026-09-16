#!/usr/bin/env bash
# Retired links are removed without deleting local files; skills never use stow.
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/lib/test-arch-isolation.sh
source "${TEST_DIR}/lib/test-arch-isolation.sh"
test_arch_make_sandbox
set -- help
# shellcheck source=dot
source "${TEST_ARCH_REPO_ROOT}/dot" >/dev/null
test_arch_arm_cleanup
DISTRO=fedora
mkdir -p "${HOME}/.config/fish/functions" "${HOME}/.agents/skills/bro" "${HOME}/.pi/agent"
ln -s "${HOME_DIR}/.config/fish/functions/wt.fish" "${HOME}/.config/fish/functions/wt.fish"
printf 'local\n' >"${HOME}/.config/fish/functions/wtd.fish"
printf 'foreign\n' >"${TEST_ARCH_SANDBOX}/foreign"
ln -s "${TEST_ARCH_SANDBOX}/foreign" "${HOME}/.config/fish/functions/wtl.fish"
ln -s "${HOME_DIR}/.agents/skills/bro/SKILL.md" "${HOME}/.agents/skills/bro/SKILL.md"
printf 'private credentials\n' >"${HOME}/.pi/agent/auth.json"
stow_dotfiles >/dev/null
[[ ! -L ${HOME}/.config/fish/functions/wt.fish ]] || test_arch_die 'retired worktree link survived'
[[ ! -L ${HOME}/.agents/skills/bro/SKILL.md ]] || test_arch_die 'skills still stowed'
grep -q local "${HOME}/.config/fish/functions/wtd.fish" || test_arch_die 'local function lost'
[[ -L ${HOME}/.config/fish/functions/wtl.fish ]] || test_arch_die 'foreign link lost'
grep -q private "${HOME}/.pi/agent/auth.json" || test_arch_die 'Pi credentials changed'
# Record npx calls without downloads or any live global installation.
npx() { printf '%s\n' "$*" >>"${TEST_ARCH_SANDBOX}/skills-calls"; }
sync_agent_skills >/dev/null
[[ $(wc -l <"${TEST_ARCH_SANDBOX}/skills-calls") == 3 ]] || test_arch_die 'missing skill sources'
grep -Fq 'herdrdev/herdr --skill herdr -g -y -a opencode claude-code codex pi' "${TEST_ARCH_SANDBOX}/skills-calls" \
  || test_arch_die 'official Herdr skill not globally installed for bundled agents'
printf 'Retired-link ownership and global skill dispatch checks passed.\n'
