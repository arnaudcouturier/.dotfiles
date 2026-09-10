-- Overrides for the Caelestia Hyprland defaults.
-- Managed by the arch-desktop overlay (home-arch/); reapplied by
-- arch_desktop_deploy_overlay, never by hand. Upstream Caelestia owns every
-- other key.
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
return {
    kbShowPanels        = "SUPER + B",
    automaticNightLight = false,

    terminal             = "ghostty",
    browser              = "brave-origin",
    editor               = "ghostty -e nvim",
    fileExplorer         = "thunar",
    audioSettings        = "pavucontrol",
    sleepGestureCmd      = "systemctl suspend",
    cursorTheme          = "Bibata-Modern-Classic",
    cursorSize           = 24,
}
