-- NvChad's base46 themes, maintained independently of NvChad's plugin stack
-- (AvengeMedia fork). Provides the "dms" colorscheme: on DMS hosts DMS
-- regenerates ~/.config/nvim/colors/dms.lua and lua/lualine/themes/dms.lua
-- from the wallpaper on every theme change, and this spec makes LazyVim
-- start with it. Those generated files are NOT in the repo, so on hosts
-- without them (Arch/Caelestia, fresh clones) the override is skipped and
-- LazyVim keeps its bundled default (tokyonight) instead of erroring back
-- to habamax with "Could not load your colorscheme".
local dms_colors = vim.fn.stdpath("config") .. "/colors/dms.lua"
local has_dms = vim.fn.filereadable(dms_colors) == 1

local specs = {
  {
    "AvengeMedia/base46",
    lazy = false,
    priority = 1000,
    opts = {},
  },
}
if has_dms then
  specs[#specs + 1] = {
    "LazyVim/LazyVim",
    opts = { colorscheme = "dms" },
  }
end
return specs
