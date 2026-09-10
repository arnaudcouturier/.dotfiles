-- User-level additions to Caelestia's Hyprland configuration.
-- Managed by the arch-desktop overlay (home-arch/); reapplied by
-- arch_desktop_install_overlay, never by hand. This file loads after
-- Caelestia's hyprland.keybinds, so the binds below are added on top of
-- Caelestia's set. One hl.config call on purpose: a single table means no
-- merge semantics to guess about.
--
-- Monitor settings live HERE, not in ~/.config/hypr/hyprland.lua.
-- That entry file is upstream-owned (Caelestia installer deploys it; default
-- `hl.monitor({ output = "", mode = "preferred", position = "auto",
-- scale = 1 })` at caelestia-dots @ 1ee7a98 hypr/hyprland.lua:53-59) and
-- must never be edited (upstream README CAUTION). This file is the
-- supported override: stowed to ~/.config/caelestia/hypr-user.lua on Arch
-- and loaded last via `require("hypr-user")`. No active monitor block is
-- committed below — find your outputs with `hyprctl monitors`, then add
-- your own `hl.monitor` call. Minimal shape (commented example only):
--
-- hl.monitor({
--     output   = "HDMI-A-1",
--     mode     = "preferred",
--     position = "auto",
--     scale    = 1,
-- })
hl.config({
    -- VRR mode 3 enables adaptive sync only for fullscreen surfaces that
    -- declare `video` or `game` content type, which keeps the OLED off VRR
    -- on the desktop and during fullscreen non-media windows where it causes
    -- brightness flicker. If a game ever fails to advertise a content type
    -- it will run without VRR; test with `hyprctl keyword misc:vrr 2`
    -- before changing this permanently.
    misc = {
        vrr = 3,
    },

    -- Caps Lock behavior, ported from the shared home/.config/hypr/input.lua
    -- (excluded on Arch so one file owns the option): keep Caps Lock and
    -- the both-Shifts Caps Lock companion.
    input = {
        kb_options = "shift:both_capslock_cancel",
    },
})

-- SUPER + K shows a searchable list of the active keybinds. Caelestia had
-- SUPER + K on kbShowPanels; that moves to SUPER + B in hypr-vars.lua.
-- The absolute path avoids depending on ~/.local/bin being in the PATH that
-- Hyprland hands to exec.
hl.bind("SUPER + K", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/hypr-keybinds"))

-- Gammastep has no way to query a running daemon, so the toggle derives the
-- state from the process itself: when the daemon is running the night light
-- is on, and toggling off stops it entirely. An inhibit-style toggle
-- (SIGUSR1) cannot report the resulting state, and a state file would drift
-- from reality after a session restart or a manual daemon kill. The
-- low-urgency transient notification names the resulting state instead of
-- just confirming the keypress. Two-arg hl.bind like upstream keybinds.lua:
-- the third parameter is bind flags (locked/release), and no upstream call
-- passes a description key, so none is passed here.
hl.bind(
    "SUPER + SHIFT + N",
    hl.dsp.exec_cmd(
        "/bin/sh -c 'if /usr/bin/pgrep -x gammastep >/dev/null 2>&1; then " ..
        "/usr/bin/pkill -x gammastep && " ..
        "/usr/bin/notify-send --urgency=low --transient --expire-time=1500 " ..
        "--app-name=Gammastep --icon=night-light-symbolic \"Night light off\"; else " ..
        "/usr/bin/setsid --fork /usr/bin/gammastep >/dev/null 2>&1; " ..
        "/usr/bin/notify-send --urgency=low --transient --expire-time=1500 " ..
        "--app-name=Gammastep --icon=night-light-symbolic \"Night light on\"; fi'"
    )
)

-- Hardware video decoding for the browser: NVIDIA-only, probed at
-- config-parse time from sysfs, so Intel/AMD machines never inherit it.
-- libva 2.20 and later refuse to guess a driver once LIBVA_DRIVER_NAME is
-- set, which is why the archive this adapts broke VA-API on Intel/AMD by
-- forcing it globally. A loaded `nvidia` module means the NVIDIA kernel
-- driver owns the display, which is exactly when the direct backend works;
-- on nouveau the block stays off and Mesa VA-API applies. Guarded so a
-- sandboxed Lua without `io` simply skips it instead of breaking the whole
-- config. Static file on purpose: the overlay is stowed, and writing through
-- its symlink would mutate the repo, so there is deliberately no generated
-- variant of this block.
local have_nvidia_gpu = false
if io and io.open then
    local nvidia_version = io.open("/sys/module/nvidia/version", "r")
    if nvidia_version then
        nvidia_version:close()
        have_nvidia_gpu = true
    end
end
if have_nvidia_gpu then
    -- The direct backend talks to the NVIDIA kernel driver instead of
    -- sharing buffers through EGL; the only backend on driver series 525+.
    hl.env("LIBVA_DRIVER_NAME", "nvidia")
    hl.env("NVD_BACKEND", "direct")
end
