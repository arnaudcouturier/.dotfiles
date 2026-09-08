-- NvChad's base46 themes, maintained independently of NvChad's plugin stack
-- (AvengeMedia fork). Provides the "dms" colorscheme: DMS regenerates
-- ~/.config/nvim/colors/dms.lua and lua/lualine/themes/dms.lua from the
-- wallpaper on every theme change, and this spec makes LazyVim start with it.
return {
  {
    "AvengeMedia/base46",
    lazy = false,
    priority = 1000,
    opts = {},
  },
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "dms" },
  },
}
