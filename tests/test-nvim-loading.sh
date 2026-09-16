#!/usr/bin/env bash
# Vanilla LazyVim must ignore even a leftover generated DMS theme.
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/lib/test-arch-isolation.sh
source "${TEST_DIR}/lib/test-arch-isolation.sh"
REPO="${TEST_ARCH_REPO_ROOT}"
[[ ! -e ${REPO}/home/.config/nvim/lua/plugins/base46.lua ]] || test_arch_die 'base46 restored'
grep -Fq 'import = "lazyvim.plugins"' "${REPO}/home/.config/nvim/lua/config/lazy.lua" \
  || test_arch_die 'LazyVim starter import missing'
command -v nvim >/dev/null || { printf 'SEAM PENDING: nvim not installed\n'; exit 3; }
LIVE_LAZY="${TEST_ARCH_LIVE_HOME}/.local/share/nvim/lazy"
[[ -d ${LIVE_LAZY}/lazy.nvim && -d ${LIVE_LAZY}/LazyVim && -d ${LIVE_LAZY}/tokyonight.nvim ]] \
  || { printf 'SEAM PENDING: installed plugin sources unavailable\n'; exit 3; }
test_arch_make_sandbox
# Copy, never symlink: plugin managers may update lockfiles and metadata.
mkdir -p "${HOME}/.config" "${HOME}/.local/share/nvim"
cp -a "${REPO}/home/.config/nvim" "${HOME}/.config/"
cp -a "${LIVE_LAZY}" "${HOME}/.local/share/nvim/lazy"
mkdir -p "${HOME}/.config/nvim/colors"
printf 'error("stale DMS theme was loaded")\n' >"${HOME}/.config/nvim/colors/dms.lua"
export XDG_CONFIG_HOME="${HOME}/.config" XDG_DATA_HOME="${HOME}/.local/share"
export XDG_STATE_HOME="${HOME}/.local/state" XDG_CACHE_HOME="${HOME}/.cache"
# Disable network installation/checking in this offline smoke test only.
nvim --headless --cmd 'lua local p=vim.fn.stdpath("data").."/lazy/lazy.nvim"; vim.opt.rtp:prepend(p); local l=require("lazy"); local setup=l.setup; l.setup=function(o) o.checker.enabled=false; o.install.missing=false; setup(o) end' \
  +'lua assert(require("lazy.core.config").plugins.base46 == nil, "base46 configured"); assert((vim.g.colors_name or ""):match("^tokyonight"), "default theme not loaded: " .. tostring(vim.g.colors_name)); print("VANILLA_NVIM_OK")' \
  +'qa!' >"${TEST_ARCH_SANDBOX}/nvim.log" 2>&1
cat "${TEST_ARCH_SANDBOX}/nvim.log"
grep -q VANILLA_NVIM_OK "${TEST_ARCH_SANDBOX}/nvim.log" || test_arch_die 'Neovim startup assertions failed'
if grep -Eq 'Error detected|E[0-9]{3}:|stale DMS theme was loaded' "${TEST_ARCH_SANDBOX}/nvim.log"; then
  test_arch_die 'Neovim emitted startup errors'
fi
