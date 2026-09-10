-- User-owned Caelestia overrides for the Hyprland defaults. Deployed ONCE
-- as a real file by ./dot stow and ./dot arch-setup (copy-if-missing onto
-- the compositor's placeholder; never stowed, never overwritten afterwards
-- — the compositor recreates a missing file here within milliseconds, so
-- stow can never own this path). Edit FREELY in $HOME. Repo template:
-- home-arch/.config/caelestia/hypr-vars.lua in the dotfiles checkout;
-- template updates need a manual merge.
--
-- editor opens the existing shared Neovim config inside ghostty: this system
-- ships no VSCode/Code-OSS package, so there is no `code` binary for
-- Caelestia's default. ghostty -e wraps nvim in a terminal even when
-- Caelestia spawns the editor without one; confirm SUPER+C on the target.
--
-- browser drives Caelestia's browser keybind: Brave Origin is this system's
-- only browser (package brave-origin-bin provides the `brave-origin`
-- command, asserted by the desktop checks).
--
-- fileExplorer and audioSettings name thunar and pavucontrol, which
-- Caelestia's own keybinds invoke; both are proposed Arch desktop
-- dependencies, not Fedora packages.
--
-- sleepGestureCmd overrides Caelestia's suspend-then-hibernate default.
-- Hibernate needs a swap target this minimal profile does not promise, so
-- the gesture suspends only.
--
-- kbShowPanels moves off SUPER + K so the keybind cheatsheet can take it.
-- B is free (C D E F K L M N P Q R S T U V W X Z are taken) and reads as
-- "bars", which is what caelestia:showall reveals.
--
-- automaticNightLight controls the GeoClue + Gammastep startup in execs.lua
-- (see the arch-desktop night light patch). false keeps new sessions
-- without automatic night light; SUPER + SHIFT + N still toggles the
-- running adjustment for this session (see hypr-user.lua).
--
-- windowOpacity is the default window transparency (upstream default 0.95
-- in the deployed variables.lua). On by default; SUPER + SHIFT + O flips
-- between this and opaque via hypr-opacity-toggle, which remembers a
-- customized level across the round trip, so keep bespoke values here and
-- the toggle honors them.
return {
    kbShowPanels        = "SUPER + B",
    automaticNightLight = false,
    windowOpacity       = 0.95,

    terminal             = "ghostty",
    browser              = "brave-origin",
    editor               = "ghostty -e nvim",
    fileExplorer         = "thunar",
    audioSettings        = "pavucontrol",
    sleepGestureCmd      = "systemctl suspend",
    cursorTheme          = "Bibata-Modern-Classic",
    cursorSize           = 24,
}
