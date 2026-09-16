# Fedora desktop refactor: Noctalia family

Status: research and proposed implementation plan only. No deployment authorized or performed.
Research date: 2026-09-16.

## 1. Decision summary

Build a fresh, non-atomic **Fedora Workstation** desktop around:

- **Umbriel** as the session compositor, starting with its native **scrolling** layout and dynamic workspaces.
- **Noctalia v5**, the native desktop shell, for the bar, launcher, notifications, clipboard, lock screen, desktop controls and theming.
- **Noctalia Greeter**, launched by greetd through `noctalia-greeter-session`.
- Existing shared applications and **fish** remain. “Shell replacement” means the desktop shell, not the terminal/login shell.

User decisions collected during research:

1. Use the current Arch/Caelestia desktop as a **read-only behavioral reference**.
2. Target **fresh Fedora Workstation**, not migration of an existing Fedora desktop installation.
3. Prefer the **native Umbriel experience**, rather than recreating Hyprland inside another compositor.
4. Tabbed window groups, groups of ten workspaces, tiled special app workspaces and a searchable cheatsheet are **not required**. Native alternatives or omission are acceptable.
5. Terra's documented Umbriel nightly package is acceptable. Keep GNOME and GDM installed for recovery; switch the default display manager only after validation.
6. Support both the current desktop and an **HP OmniBook Ultra 14** laptop. The exact laptop SKU and Fedora release remain unspecified.

### Final scope amendment — vanilla across the entire Noctalia family

**This decision supersedes customization proposals elsewhere in this research document.** The user wants the least additional desktop complexity possible: vanilla Umbriel, vanilla Noctalia shell and vanilla Noctalia Greeter. Historical parity tables below are research, not an implementation backlog.

- Use the chosen packages' defaults for layout, workspaces, gestures, appearance, shell widgets/panels, greeter appearance and supported desktop services.
- Preserve packaged keybindings. The **only personal keybinding override is Super+K → Umbriel's native `cheatsheet-toggle`**, as explicitly requested. Document the packaged terminal shortcut (Super+Enter → Kitty in the inspected example); ensure its executable is available rather than changing the shortcut. See [the final keybind decision](fedora-noctalia-keybinds.md).
- Add only missing installation/session wiring: package sources and dependencies, one shell startup path, packaged session launcher, necessary portal selection and greetd configuration. Prefer package-provided integration; add nothing already supplied correctly.
- No custom themes, palette synchronization, Ghostty theme integration, widget arrangements, app/window rules, opacity/PiP helpers, scratchpad schemes, extra shortcut banks or Hyprland behavior ports.
- No additional plugins, daemons or services merely to reproduce the Arch setup. Required dependencies and working authentication, locking and session cleanup are not optional “bloat.” Verify them before cutover; do not invent a replacement architecture.
- Do not impose the old monitor mode, VRR policy, keyboard/gesture tuning, idle timings or NVIDIA environment tweaks as desktop defaults. Retain hardware testing. If a default is unusable or unsafe, report the concrete issue and agree on the smallest necessary exception instead of silently customizing it.
- Leave optional greeter appearance sync disabled; it is unnecessary for vanilla setup and conflicts with the current no-pkexec provisioning rule.
- Application packages and shared application configurations are a separate concern. Do not expand, purge or retheme them as a side effect of desktop provisioning. The user's application choices do not justify extra compositor configuration.
- Keep the previously approved GNOME/GDM recovery path. “Least bloat” is not authorization to remove the retained recovery desktop or prune unrelated packages.

**Revised implementation sequence:** verify package compatibility → install the native stack and its required dependencies → add only missing session/login integration and the single cheatsheet override → validate on both machines with GDM retained → perform the explicitly authorized greetd cutover → document defaults and rollback.

The migration is feasible in principle, but package compatibility, physical GPU behavior and secure login/lock integration remain acceptance gates. No configuration deployment is authorized by this plan.

## 2. Scope and evidence boundaries

### In scope

Fedora package sources, desktop dependencies, Fedora-only config deployment, session services, portals, greetd setup and rollback, desktop/laptop checks, documentation and isolated regression tests.

### Explicitly out of scope

- Changing any Arch configuration or behavior.
- Editing `home-arch/`, `system/arch/`, `lib/arch-*.sh` or `packages/arch.bundle`.
- Installing or starting a new compositor on the current Arch host.
- Removing GNOME/GDM, repartitioning, bootloader changes, hibernation provisioning or general Fedora system tuning.
- Converting fish, Neovim or other shared application configurations to Noctalia.
- Forking Umbriel to emulate optional Hyprland features.

Shared entrypoints such as `dot` can eventually receive narrowly Fedora-gated dispatch. That is not permission to refactor their Arch paths. Existing Arch tests may be run in their isolated harness but should not be rewritten to accommodate a Fedora change.

### What was actually inspected

Repository: `dot`, `packages/fedora.bundle`, `home-fedora/`, README and test layout; Arch reference files read without modification.

Live read-only reference: `~/.config/hypr/hyprland.lua`, `variables.lua`, `hyprland/{keybinds,general,input,misc,execs,gestures,rules,group}.lua`, `utils/functions.lua`, `~/.config/caelestia/hypr-{user,vars}.lua`, and `shell.json`.

The live `hyprctl -j binds` response is malformed on this installation, consistent with the warning in `home-arch/.local/bin/hypr-keybinds`. Do not treat that response as a clean machine-readable inventory. Lua sources establish action intent; live shell/global shortcuts must also be checked during the eventual acceptance comparison.

The current desktop reports NVIDIA RTX 4090 and AMD Raphael display controllers. Its user config requests a 3840×2160@240 mode, scale 1, and content-specific fullscreen VRR. These are reference requirements, not a portable connector configuration and not proof of Fedora compatibility.

Official Umbriel documentation and source were inspected. Source snapshot:

`32cc131278cd296b70c41a8e5e1460a98df6a26e`

That snapshot includes a same-day breaking rename of scrolling `default_width` terminology to `default_extent`. This is concrete evidence that documentation/main and a packaged nightly can differ. Validate against the **installed package**, not just current web examples.

No Fedora installation, package transaction, graphical session, screen recording, login, suspend or physical display test was performed. There is no local Umbriel binary for offline validation. Distinguish “upstream documents this” from “tested successfully on the target.”

## 3. Current Fedora repository gap

`home-fedora/` currently has only:

- `.config/ghostty/config`, whose theme is `dankcolors` (DMS-generated).
- `.config/hypr/input.lua`, containing `shift:both_capslock_cancel`.

`packages/fedora.bundle` does not currently provision a complete Hyprland/DMS/greeter stack. Thus this is primarily **new Fedora desktop provisioning**, not removal of a complete old desktop implementation from the repository.

Shared stow skips two compatibility forwarding paths, including the old Hyprland input path. The Fedora and Arch overlays are selected separately. Do not delete that compatibility machinery or its target casually: it participates in older symlink deployments and existing Arch checks. For this change, leaving the tiny legacy Fedora input source inert is safer than a shared cleanup; document it as unused by Umbriel. A separate cleanup can follow only after proving no cross-distro impact.

`AGENTS.md` currently excludes Fedora system provisioning apart from NVIDIA. Implementation must amend that scope explicitly for Fedora desktop/greetd setup. Its current backup exception is Arch-specific; any Fedora `/etc/greetd` rollback snapshot needs a similarly narrow, documented exception. Do not introduce home-file backups.

## 4. Installation and session design

### Package routes

| Component | Research-backed route | Required verification before implementation |
|---|---|---|
| Noctalia native v5 | Upstream documents Fedora 44+ repository package `noctalia` | Confirm release/architecture availability and version; do not install legacy Quickshell `noctalia-shell` in its place. |
| Umbriel | Upstream documents Terra `umbriel-nightly` | Resolve current RPM, version and dependency closure on the selected Fedora release. |
| Greeter | Upstream documents Terra `noctalia-greeter` tagged releases on Fedora 44+ | Confirm wrapper/assets, service account and dependencies are installed. |
| X11 compatibility | Umbriel requires `xwayland-satellite` when Xwayland is enabled | Confirm Fedora/Terra provider and compatible installed version. |
| Screen capture portal | Upstream backend `xdg-desktop-portal-umbriel` | Resolve actual RPM provider/name; require packaged backend and desktop-specific routing. |
| greetd / GTK portal / Secret Service / fonts / app launch dependencies | Fedora packages where available | Query Fedora metadata, not Arch-name translations. |

Sources: [Noctalia installation][n-install], [Umbriel installation][u-install], [Umbriel packaging][u-packaging], [Greeter installation][g-install].

Do not enable a large Hyprland COPR just because it also contains Noctalia snapshots. Prefer the Fedora stable shell, Terra compositor and Terra stable greeter, subject to their compatibility. Do not build from source in `dot init` as an unannounced fallback.

Additional application dependencies must be resolved explicitly: Ghostty, a file manager for SUPER+E, an audio GUI if retaining Ctrl+Alt+V, and any screenshot/recording/color-picker helper that survives the native-first design. The current Fedora bundle already supplies Brave Origin, Neovim, wl-clipboard, Spotify and Equibop through its existing vendor-verified routes. Preserve those routes.

### Terra bootstrap and update policy

The greeter documentation's bootstrap command installs `terra-release` using a temporary repository and `--nogpgcheck`. Record this trust bootstrap honestly; it is not equivalent to an already verified vendor repository.

Implementation gate:

1. Inspect Terra's current release package, repository definitions and signing-key publication.
2. Establish an explicitly reviewed bootstrap path, retaining package signature checks afterward.
3. Fit it into source setup **before** dependent package installation. Do not assume the existing `rpm` verb will install a release RPM early enough, or invent a `.repo` URL.
4. Avoid unintentionally replacing unrelated Fedora packages. Review the proposed DNF transaction and dependency provenance.
5. Record a tested version set for shell/compositor/portal/greeter and retain a documented recovery route. A package's presence in a source spec or index is not proof that dependencies resolve on the target.

Nightly updates are accepted, but not assumed safe: run config validators and session checks after upgrades; retain/retrieve known-good RPMs where feasible rather than promising `dnf downgrade` can always find them.

### Session startup

Use the packaged Wayland session `umbriel.desktop`, with `Exec=start-umbriel`. Do not substitute bare `umbriel`, reuse `start-hyprland`, or layer UWSM around the upstream launcher without evidence it is needed.

`start-umbriel` supports a noninteractive login fish environment and a systemd-managed session. Umbriel publishes graphical environment state before starting `umbriel-session.target`. Native startup and logout must be tested for environment cleanup; avoid globally forcing NVIDIA variables or Hyprland desktop identifiers. [Sources][u-install] [and packaging][u-packaging]

Choose **one shell lifecycle owner**. Use `general.autostart = ["noctalia"]`, upstream's documented compositor-startup pattern. The research pass found no upstream-shipped Noctalia user service; do not invent or enable one alongside autostart. Recheck distribution packaging for extra startup integration before deployment. Reload must not launch another shell; logout must not leave it attached to a dead compositor.

### Greeter architecture

Noctalia Greeter now bundles its own focused wlroots login compositor. greetd launches **`noctalia-greeter-session`**, not Umbriel, niri, cage, or the UI binary directly. The chosen desktop session starts Umbriel only after login. This is still the Noctalia family throughout; a second general-purpose compositor is not needed. [Source][g-overview]

Use the package's actual service account and installed wrapper path. No autologin. Keep GNOME installed, but treat restoring GDM from a TTY as the dependable recovery route: displaying GNOME in greetd's session list does not establish that it launches correctly through greetd. Verify PAM, keyring unlock, logind session registration and SELinux with enforcing mode intact; do not paste Arch PAM files or disable SELinux.

## 5. Umbriel behavior: retain familiar chords, adopt native semantics

> **Superseded keybind proposal:** the second, native-first audit in
> [fedora-noctalia-keybinds.md](fedora-noctalia-keybinds.md) is the proposed
> implementation shortlist. The matrix below remains a historical inventory of
> the Hyprland baseline, **not an instruction to implement every row**. The user
> subsequently chose packaged defaults with **only Super+K for the native
> cheatsheet**. Super+Enter opens the packaged terminal (Kitty in the inspected
> example); Super+L and Super+T retain native focus/floating behavior. Do not build
> opacity/normalization/PiP helpers or app-specific scratchpads in the baseline.

### Important semantic differences

1. **Scrolling rather than Dwindle:** left/right navigation follows columns; up/down navigates stacked windows. Moving horizontally often means moving a column, not just the selected window. Resizing affects fractions/columns rather than the Hyprland helper's ±10% of the current window size. [Layouts][u-layout] [Actions][u-actions]
2. **Dynamic per-output workspaces:** number bindings select positions on the pointer-preferred output. An index beyond the current inventory selects the last workspace; it does not create workspace 10. Empty anonymous workspaces can be removed and renumbered. There is a 64-workspace limit per output. Keep this native behavior, not a 100-workspace bank emulation. [Workspaces][u-workspaces]
3. **Keybind repetition:** Umbriel repeats by default. Set `repeat = false` for launch, close, toggle, screenshot, lock and other one-shot actions. Preserve repetition deliberately for resizing, navigation and volume. [Keybinds][u-keybinds]
4. **Modifier-only launcher:** Umbriel supports a Super tap on release, cancelled by other discrete input. It accepts either logical Super key; this is not an exact left-only Hyprland bind. Ensure Super+other shortcuts do not also launch the launcher.
5. **Scratchpads:** available natively, global and named, but always floating. Returning a window restores its saved workspace, not necessarily the current one. Tiled special workspaces are not required, so do not write an emulation layer. [Scratchpads][u-scratchpads]
6. **Window groups:** stacked scrolling columns are not Hyprland tab groups. Retire the group toggle/lock/ungroup shortcuts rather than relabeling an unrelated action.
7. **Gestures:** native source handles three-finger scrolling/workspace movement and four-finger overview. The current Hyprland four-finger horizontal workspace and downward-suspend/custom special-workspace gestures are not portable config actions. Adopt Umbriel gestures; retain keyboard suspend. [Input][u-input] and `src/input/gestures.cpp` at the inspected commit.
8. **Defaults and conflicts:** explicitly audit native and configured bindings together, including `Mod` versus `Super` aliases. Do not blindly combine the entire upstream example with the old Caelestia table. Keep an explicit chosen map and test conflicts under both XKB layouts.

### Keybind disposition matrix

Notation: `S` = Super, `C` = Ctrl, `A` = Alt, `Sh` = Shift. Noctalia commands below are appended to `noctalia msg`; Umbriel actions are direct bind actions unless noted. These are proposed mappings, not a deployed configuration.

| Current chord(s) | Proposed Fedora behavior | Parity / decision |
|---|---|---|
| S tap; S+Space (live user comment identifies shell launcher) | `panel-toggle launcher` | Retain both after checking no conflict. Native Super release behavior. |
| S+K | Umbriel `cheatsheet-toggle` | Native active-keybind display. No search; user accepts. No custom Fuzzel helper. |
| S+N | `panel-toggle control-center` | Native control center replaces Caelestia sidebar. |
| S+B | `bar-toggle` or `bar-show`, select one during UX validation | No exact “show every Caelestia panel” concept. Recommend toggle bars. |
| C+A+Delete | `panel-toggle session` | Native session menu. |
| C+A+C | `notification-clear-active` | Dismiss toasts, preserve history. Clearing history is a separate operation. |
| S+L | `session lock` | Native lock screen. |
| S+Sh+L | `session lock-and-suspend` | Safer native suspend sequence; do not copy raw suspend if locking is intended. |
| S+A+L | Retire restore-lock hack; document recovery procedure | Do not promise restarting the shell can recover every abandoned lock safely. |
| C+S+Sh+R; C+S+A+R | Retire shell kill shortcut; optional explicit restart via chosen service owner | Never kill the whole QuickShell namespace. Test lock failure/restart separately. |
| S+1…0 | `workspace-switch:1` … `:10` | Dynamic positions, not fixed globally numbered workspaces. 0 maps to 10. |
| S+A+1…0 | `window-move-to-workspace:1` … `:10` | Native move behavior/output scope; verify destination focus behavior. |
| S+wheel; S+PageUp/PageDown; C+S+Left/Right | `workspace-previous` / `workspace-next` | Preserve workspace navigation chords. Replaces native wheel column focus intentionally. |
| S+A+wheel/PageUp/PageDown; C+S+Sh+Left/Right | `window-move-to-workspace-previous` / `-next` | Native transfer behavior; do not assume wrapping. |
| C+S+digits/wheel; C+S+A+digits | Retire workspace-bank shortcuts | User accepts no groups-of-ten emulation. |
| S+arrows | `window-focus-left/right/up/down` | Native scrolling column/row focus. |
| S+Sh+Left/Right | `column-move-left/right` | Moves a column and its members. Explicit native semantic change. |
| S+Sh+Up/Down | `window-move-up/down` | Reorder inside a column. |
| A+Tab; A+Sh+Tab | `window-focus-next` / `window-focus-previous` | Immediate native layout-order cycling. Noctalia's optional switcher is an explicit-selection overlay, not automatically the same behavior. |
| C+A+Tab; C+A+Sh+Tab; S+Comma; S+Sh+Comma; S+U | Retire tab-group operations | Native stacked columns remain available, but not a disguised group emulation. |
| S+Minus/Equal; S+A+Left/Right | `window-modify-width:<delta>` | Choose/test a fractional step; not exact ±10% current-window math. |
| S+Sh+Minus/Equal; S+A+Up/Down | `window-modify-height:<delta>` | Native row/floating sizing. |
| S+left/right mouse drag | Native move/resize gestures | Preserve. Check tiled reorder, floating resize and drag edge behavior. |
| S+Z / S+X keyboard-triggered drag/resize | Omit unless installed Umbriel exposes a suitable native action | Mouse equivalents remain; no verified direct action in current action list. |
| C+S+Backslash | `window-center` | Floating only. Scrolling `column-center` is a different action; can be offered separately. |
| C+S+A+Backslash | Optional ordered set-width/set-height/center sequence | 55% × 70% of usable area is possible for floating windows, but not necessary for native-first baseline. |
| S+A+Backslash | Native pinning or omit special PiP positioning helper | No verified general runtime pixel-position action matching the old bottom-right/aspect-ratio script. |
| S+P | `window-toggle-pinned` | Native pin floats window, stays above fullscreen, restores prior state on unpin. |
| S+F | `window-toggle-fullscreen` | Native fullscreen. |
| S+A+F | `window-toggle-maximize` | Native full-width column/maximize semantics, not a promise of Hyprland bordered-fullscreen geometry. |
| S+A+Space | `window-toggle-floating` | Preserve. |
| S+Q | `window-close` | Preserve; no repeat. |
| S+S; S+A+S; C+S+Sh+Up/Down | Optional single native scratchpad: toggle/store/restore | Allowed native alternative, not required. Restore means saved destination. |
| S+M/D/R; C+Sh+Escape | Optional native music/chat/todo/system-monitor launchers or scratchpads | Not required. Do not install Todoist/foot/Discord merely because upstream Caelestia defaults name them. |
| S+T | Spawn `ghostty` | Preserve; add verified Fedora package route. |
| S+W | Spawn `brave-origin` | Preserve existing vendor package route and verify binary. |
| S+C | Spawn `ghostty -e nvim` | Preserve shared editor config. |
| S+E | Spawn chosen file manager | Current reference is Thunar; verify Fedora package or explicitly choose Workstation's existing file manager. |
| C+A+V | Audio GUI / native audio controls | Current reference pavucontrol; do not translate package names without verification. |
| Print | `screenshot-fullscreen` | Captures focused monitor; use `all` only if desired. |
| S+Sh+S | `screenshot-annotate` | Native frozen-screen annotation; not identical to freeze-and-region selection. |
| S+Sh+A+S | `screenshot-region` | Native region capture. |
| C+A+R; S+A+R; S+Sh+A+R | Recording: pending backend decision | Do not invent Noctalia recording IPC. Verify packaged native/plugin capability or propose a Fedora-packaged external recorder, including audio/region/stop behavior. |
| S+Sh+C | Color picker: pending native/backend check | Do not assume hyprpicker must remain or is compositor-exclusive. Verify before choosing helper. |
| Brightness keys | `brightness-up` / `brightness-down` | Built-in backlight versus desktop DDC capability must be tested independently. |
| Media keys; C+S+Space/Equal/Minus/Backspace | `media toggle/next/previous/stop` | Stop also dismisses native media player UI until reactivated. |
| Volume keys; S+Sh+M; mic mute key | `volume-up/down`, `volume-mute`, `mic-mute` | Match 10-point step/100% cap where supported; verify unmute behavior, OSD and repeat. |
| S+V | `panel-toggle clipboard` | Native history; do not also launch cliphist watchers. |
| S+A+V | Open clipboard panel for managed deletion, or leave unbound | Do not silently map selective-delete UI to destructive `clipboard-clear`. |
| C+A+Sh+V | Defer typing latest history into application | Native `clipboard-text` prints text; it is not equivalent to ydotool input injection. |
| S+Period | `panel-toggle launcher /emo` | Native emoji search. Verify copy/paste behavior in target apps. |
| A+Space | Umbriel `keyboard-layout-next` | Configure `us,ca` and `shift:both_capslock_cancel`. Native physical-keyboard synchronization. |
| S+Sh+N | `nightlight-force-toggle` with schedule disabled initially | Manual adjustment versus return-to-disabled schedule. Do not equate schedule-toggle with force-on. |
| S+Sh+O | Optional Fedora-only opacity toggle | Rule opacity and reload exist; global toggle is not a documented direct action. Preserve only with a small dedicated state/include helper if wanted. |
| S+A+F12 | Optional notification smoke-test command | Debug convenience, not a desktop requirement. |
| Caps/Num Lock notification hooks | Native indicators/OSD if available | Preserve XKB behavior; don't port non-consuming Lua hook machinery. |

Command references: [Umbriel actions][u-actions], [Noctalia shell IPC][n-ipc-shell], [surfaces][n-ipc-surfaces], [media/UI][n-ipc-media], [system controls][n-ipc-system].

**Never blindly copy `allow_when_locked`** from the old map. Allow media/brightness deliberately; keep screenshots, clipboard access, app launching and text injection blocked. Noctalia session and Umbriel lock behavior must enforce this in runtime tests.

## 6. Features beyond bindings

### Window rules and presentation

- Keep native scrolling defaults, animations, overview and gaps initially. The user chose native UX, not a pixel-for-pixel Caelestia reproduction.
- Opacity, blur, rounded corners, shadows, floating placement, pinned windows and fullscreen are supported. Map only rules for installed applications.
- Umbriel rule matching uses `app_id`, title and supported state/content selectors—not Hyprland tags or arbitrary Lua callbacks. Some rules are opening-only, others reapply while open. Validate actual app IDs, especially Flatpak Spotify and X11 clients through satellite.
- PiP can receive floating/pinned/default-position rules. Do not claim exact preservation of the old live-title-driven aspect-ratio/positioning script.
- Current Equibop opacity exception can be retained with a specific rule. Do not copy irrelevant Quickshell, Bitwarden, game or editor exceptions indiscriminately.
- Dynamic lone-window gap behavior and per-app idle-inhibit rules are not all direct equivalents. Prefer native presentation and application's inhibitor protocol; test actual fullscreen media/games.

Sources: [Window rules][u-rules], [Appearance][u-appearance], [Configuration][u-config].

### Keyboard, input and displays

Retain US and French Canada, Caps Lock/both-Shifts behavior, and reference repeat delay/rate (250 ms / 35 Hz) if comfortable. Use a compositor-level Alt+Space switch, not conflicting XKB modifier-subset toggles. Verify punctuation and digit shortcuts in both layouts, hotplugged keyboards and laptop hotkeys.

Keep automatic GPU discovery. No baked-in PCI addresses, connector names, disk paths or hostnames. Separate optional per-machine output preferences from portable defaults. Do not force a 4K240 desktop mode onto the laptop or greeter.

Desktop VRR starting policy: disabled on ordinary desktop; content-type game/video rules with fullscreen VRR may express the current anti-flicker intention. Test the interaction with focused windows and actual client content hints. A blanket fullscreen policy is not identical to Hyprland `vrr = 3`. Leave tearing off as in the reference. HDR is a capability, not an instruction to enable it. [Outputs][u-outputs] [Rules][u-rules]

The OmniBook model name alone is insufficient to establish GPU, panel, fingerprint reader, touch or suspend support. Record its exact hardware inventory on Fedora; do not guess from the product family. Test native gestures, backlight, lid/docking, suspend/resume, battery/power profiles and Wi-Fi/Bluetooth separately from the desktop.

### Core desktop services

- One notification server, clipboard manager, idle manager, polkit agent and night-light owner in the Umbriel session.
- Native Noctalia services replace Caelestia, cliphist watchers, Gammastep and external idle tools where supported. Avoid running two gamma-control clients.
- Noctalia idle lock/monitor-off defaults are disabled. Automatic lock/suspend timings need an explicit user decision; this plan does not infer them from defaults.
- Use lock-and-suspend for explicit keyboard suspend, then validate lid/logind-triggered sleep also locks before suspend. Avoid duplicate lid handlers.
- Ensure a working Secret Service for Noctalia encrypted storage and applications; merely launching gnome-keyring is not proof that login unlock works through greetd.
- Prefer native Noctalia polkit support if the package enables it; verify one agent rather than copying an Arch `/usr/lib/...` path.
- Preserve tray functionality for VPN/communication apps. Tailscale systray in `home-arch/` is not automatically a Fedora requirement; select it explicitly if desired.
- Do not copy unrelated startup tasks such as automatic trash deletion without a stated need.

Sources: [Noctalia configuration][n-config], [Idle][n-idle], [Night light][n-night], [Startup][n-start].

### Portals and application compatibility

Use the Umbriel capture backend for Screencast/Screenshot and an appropriate fallback backend for other interfaces such as file choosers. Route by the Umbriel desktop rather than replacing global portal defaults and breaking the retained GNOME session. Verify D-Bus activation and `XDG_CURRENT_DESKTOP` in native session startup.

Acceptance must include Brave screen/window sharing, one practical conferencing client, OBS or another portal consumer if used, Flatpak file pickers, screenshots and X11/Electron applications. Correct portal package names and metadata are a prerequisite, not proof of operation. Also check RemoteDesktop/GlobalShortcuts requirements before assuming the capture backend implements them.

## 7. Configuration ownership and theming

> **Vanilla amendment applies.** Create as little managed configuration as the
> packages genuinely require. Their packaged defaults already cover layout,
> appearance, widgets and shell behavior. Do not pre-create curated theme,
> widget, input or rules fragments just to have dotfiles content, and do not
> theme applications as part of desktop provisioning. Application choices are
> the user's separate responsibility, per the scope amendment in section 1.

### Proposed layout (created only during implementation, only when needed)

```text
home-fedora/.config/umbriel/
  config.toml          # small entrypoint: packaged-default include + the sole Mod+K override
home-fedora/.config/noctalia/   # only if a required setting cannot stay default
system/fedora/greetd/  # greetd/admin-owned greeter config templates
lib/fedora-desktop.sh
lib/fedora-greeter.sh
# additional Fedora source/bootstrap helper only if necessary
```

Avoid fragment proliferation: a single include-style Umbriel entrypoint is preferred over split keybind/input/rules files. Split further only when ownership or independent validation demands it.

**Umbriel:** one stowed entrypoint that includes the package's default configuration and adds only `Mod+K = cheatsheet-toggle`, per [the keybind decision](fedora-noctalia-keybinds.md). Upstream never recreates/writes the user config, so the Arch Caelestia copy-once exception is unnecessary. Includes are applied before the including file; root values win. Verify the installed package's config path and include behavior; fall back to a minimal standalone map only if inclusion proves unsuitable. [Configuration][u-config]

**Noctalia v5:** no curated config in the baseline; run packaged defaults. If a required setting must be pinned, add one small stowed `~/.config/noctalia/*.toml` and say why it cannot stay default. GUI overrides belong to `~/.local/state/noctalia/settings.toml` and win over curated files. Do not stow state, credentials, clipboard data or plugin caches. [Configuration][n-config]

**Generated themes / application theming: out of scope.** No Ghostty retheme, no built-in/community template enablement, no palette mirroring. If the user later wants application theming, treat it as a separate explicit decision—do not enable templates as a desktop-provisioning side effect. The historical per-app theme-include guidance above is retained only as reference. [App theming][n-theming]

**Keyboard layouts:** retain packaged/system defaults. Do not carry forward the Arch US/French-Canada configuration or Caps Lock tuning automatically. Any personal input override requires a later explicit request.

### Greeter appearance sync: explicit policy conflict

Upstream constrained live sync uses a root-owned helper through **pkexec**; direct sudo invocation is not supported for that sync path. The repository explicitly forbids pkexec and passwordless elevation. Do not bypass either contract with a wrapper.

Baseline plan: curated administrator-owned greeter appearance/input settings provisioned through terminal sudo in `dot`; leave GUI/automatic appearance sync disabled. This still gives the Noctalia Greeter visual design, but not live wallpaper/palette mirroring.

If live sync is desired, ask for a narrow, documented policy change first. Do not install passwordless Polkit rules automatically. Keep packaged polkit authentication for normal desktop apps distinct from permission to add an elevation path to dotfiles provisioning. [Greeter sync][g-sync]

## 8. Ordered implementation phases and acceptance gates

### Phase A — Freeze scope, release and package transaction

- Confirm Fedora release (upstream minimum documented here is 44), architecture and exact laptop hardware.
- Record approved native-first behavior and remaining feature choices.
- Make the narrow Fedora provisioning policy amendment in `AGENTS.md`; preserve Arch rules verbatim where possible.
- Verify all RPM providers, service files, dependencies, Terra trust bootstrap and tested version set in Fedora, without replacing the display manager.
- Inspect `dot` source/install ordering before adding new source handling.

**Gate:** DNF resolves the intended native v5 stack on fresh Fedora with no unexplained removal/replacement transaction. Stop rather than fall back to legacy Noctalia or a source build.

### Phase B — Fedora-only deployment and read-only checks

- Add self-gated Fedora modules with a small interface for prerequisites, deploy and check.
- Proposed explicit commands: `./dot fedora-setup`, `./dot fedora-check`, and a greeter cutover flag such as `--replace-display-manager`.
- Refuse non-Fedora and unsupported/atomic targets before elevation, networking or mutation.
- `stow` remains user config deployment, not display-manager switching. `init`/`update` may install/stow Fedora pieces but must not silently replace GDM.
- Add config and package checks to Fedora diagnostics; no new Fedora command invokes Arch provisioning.
- Retain the existing Fedora NVIDIA detection path; any desktop GPU additions stay conditional and do not redesign that driver setup accidentally.

**Gate:** isolated tests prove wrong-distro refusal and no changes to Arch selection/behavior.

### Phase C — Native shell/compositor config and keybinds

- Create minimal scrolling configuration and the chosen map from `docs/fedora-noctalia-keybinds.md`; the original section 5 matrix is historical, not the implementation checklist.
- Configure keyboard layouts and necessary app rules.
- Add native Noctalia shell settings without copying all upstream defaults.
- Configure one autostart owner, appropriate portals and Secret Service/polkit integration.
- Migrate Fedora Ghostty theming with an audited generated-output boundary.
- Run `umbriel validate -c <candidate/config.toml>` and `noctalia config validate <candidate-directory>` using the selected package versions. TOML syntax validation alone is not enough.

**Gate:** validators succeed without unhandled warnings, expected bindings are accepted, generated files do not overwrite owned source/state.

### Phase D — Test Umbriel from retained GDM/TTY

- Select the packaged Umbriel session while GDM remains the default.
- Verify shell startup, desktop environment export, logout cleanup and re-login without duplicate services.
- Test both keyboard layouts, holding/releasing shortcuts and native scrolling semantics.
- Test browser/Flatpak/X11 applications, Secret Service, screen sharing, screenshot paths and lock/suspend behavior.
- Test physical GPU/output behavior on desktop, then laptop. A nested session or VM cannot certify 4K240, VRR, backlight or suspend.

**Gate:** both machines have a usable native session, not just a successful compositor launch.

### Phase E — Greeter configuration, cutover and rollback

- Install/verify greeter assets, greetd account and PAM before modifying enablement.
- Record the actual incumbent display-manager unit and preserve the original `/etc/greetd` config/enablement state under the approved narrow system-config backup exception.
- Configure greetd to run the package's `noctalia-greeter-session`; use package/user-account facts, not Arch constants.
- Validate greeter config and permissions; keep administrator config separate from greeter-owned runtime state.
- Require explicit cutover authorization from a TTY with saved work. Disable the incumbent and enable greetd for the controlled transition; never kill the user's active desktop from an ordinary `dot update`.
- Reboot and test login, failed password, session selection, keyboard layouts, logout, greeter return and another reboot with SELinux enforcing.
- Keep GNOME and GDM installed, not concurrently enabled with greetd.

**Rollback:** from the retained TTY, restore the recorded display-manager enablement and any saved greetd configuration, then reboot. Restoring Git files alone does not restore system services. Do not assume a package downgrade is available unless the known-good RPM set was retained.

**Gate:** real successful authentication and desktop launch on each target, plus a rehearsed recovery path.

### Phase F — Documentation, update/repair tests, optional extras

- Document native behavioral changes, commands, generated files, GUI override ownership, per-machine customization and rollback.
- Re-run setup/stow/update paths to verify idempotency; second runs do not duplicate services, includes, users or source entries.
- Keep recording, color picker, opacity helpers and app scratchpads out of the baseline. Consider an addition only for a newly confirmed practical need, not historical Hyprland parity.
- Do not remove unused legacy shared-forwarding mechanisms in the same change without an independent cross-distro justification.

## 9. Verification checklist

### Automated and repository checks

- Bash parsing/ShellCheck for `dot` and new Fedora modules; existing required pre-commit checks remain in force.
- Existing isolated regression suite unchanged, plus new Fedora-only tests.
- Test non-Fedora/atomic refusal before sudo/network/mutation; missing dependencies produce actionable errors.
- Test Fedora overlay selection, symlink collisions and idempotent restow without home backups.
- Test no writes beneath protected Arch paths; inspect final diff and preserve existing untracked user work.
- Test source-before-package ordering and no silent legacy v4/native v5 substitution.
- Validate candidate configs with the installed binaries, then validate effective Noctalia config including runtime overrides.
- Test missing optional generated theme, malformed TOML, failed reload retaining last good config, and successful recovery.
- Test all spawn commands resolve; one-shot keys do not repeatedly launch/close/toggle while held.
- Run `./dot doctor` as the existing read-only repository check when appropriate; never run `init`, `stow` or setup on this Arch host to test Fedora.

### Desktop hardware

- NVIDIA proprietary driver and AMD iGPU discovery, no forced wrong renderer.
- 4K240 advertised/selected mode, scale, cursor, lock/unlock, suspend/resume, output hotplug.
- VRR desktop flicker avoidance and game/video policy; fullscreen direct scanout/capture transitions.
- Browser video decode and WebRTC capture; test rather than globally forcing `LIBVA_DRIVER_NAME=nvidia`.
- DDC brightness only if supported by actual monitor and permissions.

### Laptop hardware

- Exact CPU/GPU/panel/device inventory; no assumptions from “OmniBook Ultra 14”.
- Backlight and media Fn keys; keyboard layout switch; native touchpad gestures.
- Battery indication, power profiles, lid close/open, dock/undock, mixed-DPI external displays.
- Suspend/resume and locked wake on AC/battery; no hibernation assumption.
- Wi-Fi/Bluetooth/audio, camera and fingerprint authentication if the user relies on them. Fingerprint login must not be presented as proof of keyring unlock.

### Session/security

- One shell/notification/clipboard/polkit/idle/night-light owner per session.
- Lock success, failed authentication, shell crash while locked, safe recovery; no exposed session during suspend/wake.
- Secrets unavailable to greeter; no user-home permission relaxation just for wallpaper sync.
- Greetd login with PAM/logind/keyring working and no unexplained SELinux AVCs.
- Portals routed correctly for Umbriel while retained GNOME still works.

## 10. Decisions still needed before implementation/cutover

These do not prevent this plan, but must not be silently guessed:

1. Exact Fedora release and laptop SKU/hardware inventory.
2. Idle lock/monitor-off/suspend timeouts, and whether desktop/laptop differ.
3. Whether recording, color picking and the global opacity-toggle shortcut are must-haves. They were not among the optional features explicitly waived.
4. Whether to keep Thunar/pavucontrol shortcuts or prefer native/Workstation alternatives.
5. Whether static greeter appearance is sufficient under the current no-pkexec rule. Live sync requires an explicit policy exception.
6. Terra bootstrap trust details and installed package/portal compatibility must be verified on Fedora before approving the transaction.

## Primary sources

All web sources below were consulted on 2026-09-16; moving documentation may describe a newer revision than an installed package.

[u-install]: https://docs.noctalia.dev/umbriel/installation/
[u-packaging]: https://github.com/noctalia-dev/umbriel/blob/32cc131278cd296b70c41a8e5e1460a98df6a26e/PACKAGING.md
[u-config]: https://docs.noctalia.dev/umbriel/configuration/
[u-keybinds]: https://docs.noctalia.dev/umbriel/keybinds/
[u-actions]: https://docs.noctalia.dev/umbriel/actions/
[u-layout]: https://docs.noctalia.dev/umbriel/layout/
[u-workspaces]: https://docs.noctalia.dev/umbriel/workspaces/
[u-scratchpads]: https://docs.noctalia.dev/umbriel/scratchpads/
[u-input]: https://docs.noctalia.dev/umbriel/input/
[u-outputs]: https://docs.noctalia.dev/umbriel/outputs/
[u-rules]: https://docs.noctalia.dev/umbriel/window-rules/
[u-appearance]: https://docs.noctalia.dev/umbriel/appearance/
[n-install]: https://docs.noctalia.dev/noctalia/getting-started/installation/
[n-start]: https://docs.noctalia.dev/noctalia/getting-started/running-the-shell/
[n-config]: https://docs.noctalia.dev/noctalia/configuration/
[n-theming]: https://docs.noctalia.dev/noctalia/theming/app-theming/
[n-idle]: https://docs.noctalia.dev/noctalia/services/idle/
[n-night]: https://docs.noctalia.dev/noctalia/services/night-light/
[n-ipc-shell]: https://docs.noctalia.dev/noctalia/ipc/shell/
[n-ipc-surfaces]: https://docs.noctalia.dev/noctalia/ipc/surfaces/
[n-ipc-media]: https://docs.noctalia.dev/noctalia/ipc/media-and-ui/
[n-ipc-system]: https://docs.noctalia.dev/noctalia/ipc/system-controls/
[g-overview]: https://docs.noctalia.dev/greeter/
[g-install]: https://docs.noctalia.dev/greeter/installation/
[g-sync]: https://docs.noctalia.dev/greeter/sync/
