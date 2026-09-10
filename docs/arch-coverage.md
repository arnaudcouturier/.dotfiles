# Arch provisioning coverage (archive 11afffe → this repo)

Source: `arnaudcouturier/dotfiles-system-archive @ 11afffe`
("arch: install pi via pi-coding-agent-bin AUR package"). Only
`distros/arch/` was considered; `distros/fedora/` and `distros/omarchy/`
are excluded (Fedora unchanged by order). Every requested feature below
lands somewhere: nothing was quietly omitted.

Requested set: optimizations, conditional GPU support, conditional btrfs
snapshots, greetd/sysc-greet, Hyprland/Caelestia, Limine, video configs —
from minimal archinstall with existing Limine and no DE.

## Subsystem matrix

| Archive source | Disposition | Destination / reason |
|---|---|---|
| `modules/00-base.sh`: multilib, pacman Color/VerbosePkgLists/ParallelDownloads, `-Syu base-devel git`, paru bootstrap with PKGBUILD review | Adapted | `lib/arch-system.sh` (`arch_system_setup_pacman_options`): same options, one `.dotfiles-backup`, `pacman-conf` revalidation. ILoveCandy dropped (cosmetic, unrequested). Helper stays `yay`, not paru: switching helpers contradicts the repo standard and `doctor`. |
| `packages/{base,desktop,audio,shell}.txt` stable sets | Adapted into bundle | `packages/arch.bundle` infrastructure section: desktop core, file manager, theming, fonts, PipeWire, network/hardware, recovery basics. Package-for-package rationale lives in the trailing comments. |
| `packages/apps.txt`: code, brave-bin, signal/telegram, qemu, bluetui, glab | Excluded | Kept app selection: no archive browsers, editors, chat clients, or VMs. `github-cli`, `mullvad-vpn`, `nextcloud-client`, `qbittorrent`, `tailscale` were already bundled and stay. |
| `packages/dev.txt` (python/uv/go), `winboat.txt` + `winboat-bin`, gaming stack, `hyprmod`, `protonplus`, `vkbasalt`, `vm-curator` | Excluded | Not requested. No toolchains, Windows layer, or gaming to inflate coverage. |
| `packages/aur.txt`: caelestia-cli, bibata-cursor-theme-bin, sysc-greet | Included | `arch.bundle` AUR section: installer CLI, cursor named by desktop overrides, greeter. |
| `packages/shell.txt`, `dev` shell overlap | Converged | Already bundled (fish/starship/eza/zoxide/fzf/fd/ripgrep/bat); nothing to add. |
| `modules/20-gpu.sh` + PCI-ID data | Adapted | `lib/arch-gpu.sh`: per-vendor stacks incl. hybrids, open vs DKMS vs AUR 580xx with yay review warning, per-kernel headers, `mkinitcpio -P`, `WORKSTATION_GPU` override for testing. The 160-ID legacy list is vendored verbatim as `lib/arch-nvidia-legacy-pciids.txt` (archive data from RPM Fusion nvidia-kmod 610.57.04, freshness rule in its header — deterministic vendor data, not machine-specific). Flavor mirrors the archive (`proprietary` on list hit, `unsupported` below device 0x1e00, `open` above); `unsupported` dies with the PCI IDs BEFORE any package write. No desktop environment variables here (overlay owns them, conditional only). |
| `modules/30-services.sh` + zram/sysctl templates | Adapted | `lib/arch-system.sh` + `system/arch/systemd/zram-generator.conf` + `system/arch/sysctl.d/99-arch-zram.conf` (renamed from `99-arch-config.conf`: it holds only the zram VM pair). Core units fail loudly; deselectable timers warn-skip when their package is absent — and the bundle now carries those providers (`pacman-contrib`, `reflector`, `fwupd`, `smartmontools`), so fresh installs enable them while minimal systems stay valid. Polkit agent verified by absolute path (no unit exists). `tailscaled` enabled opportunistically (already bundled); `docker` likewise (absent without WinBoat). |
| `modules/35-snapshots.sh` | Adapted | `lib/arch-snapshots.sh`: btrfs-gated, tooling installs on demand, `root` config with `/.snapshots` refusal, timeline/cleanup timers, bootloader gap warned (Limine never removes entries, so a hand-added snapshot entry survives). |
| `modules/40-greeter.sh` + `etc/greetd/config.toml` | Adapted | `lib/arch-greeter.sh` + `system/arch/greetd/config.toml`: niri/kitty/sysc-greet, binary-path reconcile, greeter account/groups, config backup, PAM keyring unlock (optional lines only), `85-greeter.rules` check. Incumbent-DM refusal happens FIRST, before any mutation; only `--replace-display-manager` displaces. |
| `modules/45-caelestia.sh` (installer wrapper, tree verification, app integrations) | Split | Installer + user-runtime configuration: desktop agent inside `arch_desktop_configure_caelestia` (`lib/arch-desktop.sh`, `home-arch/`). Night-light patch concept survives as their patch function. Spotify/Spicetify and editor re-theming to non-selection editors are excluded; no wallpaper cloning — the shell uses whatever wallpaper the user picks, and the shared `~/Pictures/wallpapers/` themes stay untouched. `uwsm` is an explicit `repo` entry (Arch extra, vendor-confirmed; desktop upstream verification confirms the Caelestia manifest ships `packages=[uwsm]`). |
| `modules/50-dotfiles.sh` (copy model) | Mechanism rejected, selection kept | Stow stays the deployer (repo standard). `dot` stows shared (skipping the two forwarding aliases everywhere) then the selected distro overlay, and prunes only provably-ours stale shared symlinks (a link resolving into shared `home/`); real files and foreign links are warned about and left. `doctor` asserts each tree against its selected source with no exemption: overlay links must resolve into `home-arch/`, and the generated Hypr tree stays outside the stowed expected set. No home backup/copy logic anywhere. |
| `dotfiles/caelestia/hypr-vars.lua`, `hypr-user.lua` | Adapted by desktop agent | `home-arch/.config/caelestia/`: overrides retargeted at current selection; NVIDIA env conditional on detected hardware; Arch user override carries the `hypr/input.lua` keyboard equivalent. |
| `dotfiles/desktop/ghostty/config` | Per-distro sources | `home-arch/` Ghostty wins on Arch; `home-fedora/` carries the DMS config on Fedora; shared `home/` keeps only a forwarding alias, never stowed. |
| `dotfiles/desktop/{gtk-3.0,gtk-4.0,environment.d}` + `hypr-keybinds` | Adapted by desktop agent | `home-arch/` verbatim carries; keybinds retargeted to `nvim in ghostty`. |
| `dotfiles/desktop/mpv/*` + `modules/52-video.sh` | Split | Configs: desktop agent (`home-arch/`). Link + parse-probe mechanics: `lib/arch-video.sh` (package-derived shader dir, required-shader gate, real-dir refusal). `dot` runs video after desktop, so `mpv.conf` exists first. |
| `modules/55-limine.sh` + `etc/limine/appearance.conf` | Adapted | `lib/arch-limine.sh` + `system/arch/limine/appearance.conf`: every candidate config themed with marker block + entry-count guard + one backup, FAT-safe staging, ESP ro→rw trap, loader auth, vfat check, conditional `Limine` entry. Entries never removed; archinstall entry kept; BIOS skips firmware registration. |
| `distros/arch/check.sh` | Patterns, not the script | Each module's `*_verify` plus `dot arch-check` (read-only, no elevation). `doctor` keeps user-space checks plus overlay-aware symlink verification. |
| `lib/{common,engine,menu}.sh`, `catalogue.sh`, `bootstrap.sh`, `install.sh` | Excluded | `dot` already owns equivalents (sudo refresher, batched `-Syu`, idempotent init). No second installer framework; no `curl|bash` bootstrap. |
| `ILoveCandy`, `unzip`, phone/network filesystems (`mtp`, `smb`, `ntfs`, `exfat`, `p7zip`, `unrar`), CJK-adjacent extras | Excluded or deferred | Not requested; `dot package add` remains the path. CJK + Liberation fonts ARE included (working web rendering is desktop infrastructure). |

## Behavior contracts

- Copy-based home deploy with `~/.config-backup` and doctor exemptions: rejected. Stow owns `$HOME`; system backup exception covers `/etc` + bootloader only.
- Forwarding aliases instead of blanket overrides: Ghostty and `hypr/input.lua` live per-distro (`home-fedora/`, `home-arch/`), shared `home/` keeps unstowed aliases so old links resolve — never a verifier that contradicts the selected stow paths.
- Silent desktop skip: rejected. `arch-setup` dies without `lib/arch-desktop.sh`; the greeter step re-verifies desktop first even under `--only greeter`.
- Incumbent DM: refuse-first before any greeter mutation; enablement only with no incumbent, existing greetd, or the explicit flag. No incidental Alias takeover.
- Caelestia installer/user-runtime: desktop agent's `arch_desktop_configure_caelestia`. `arch-setup` installs helpers + bundle + stows files BEFORE side-effecting steps, so minimal Arch has a real path (`init`, then `arch-setup`).
## Notes

- Scheme replay plus the Arch terminal look live in overlay `fish/conf.d`
  snippets (`caelestia-sequences`, `caelestia-greeting`, `caelestia-starship`);
  the installer
  disables its fish/starship/fastfetch components, so shared
  `fish/config.fish` is never written through its symlink. The Arch prompt
  comes from `home-arch/.config/caelestia/starship-caelestia.toml` via
  `$STARSHIP_CONFIG` (upstream base at `caelestia-dots @ 1ee7a98` plus the
  repo's `command_timeout`, Node probing guard, and disabled `package`); the
  Arch greeting replays the upstream Caelestia ASCII plus fastfetch with the
  overlay boxed config. Shared Starship/fastfetch stay untouched for Fedora.
- The `hypr/input.lua` keyboard equivalent lives in
  `home-arch/.config/caelestia/hypr-user.lua`; nothing may ever live under
  `home-arch/.config/hypr/` (upstream-deployed directory).
- Monitor layout lives in `home-arch/.config/caelestia/hypr-user.lua`
  (stowed to `~/.config/caelestia/hypr-user.lua` on Arch, loaded last via
  `require("hypr-user")`); never edit the generated
  `~/.config/hypr/hyprland.lua` (upstream default `hl.monitor` with
  `preferred`/`auto`). The overlay carries only a commented `hl.monitor`
  example — no active machine layout is committed.
- `uwsm` is an explicit bundle entry (Arch extra); the installer enables
  the component, and verification asserts its session files.
- `neovim` is bundled (shared LazyVim config; Caelestia editor target); no
other editors.
- MEGA Sync (Thunar integration) resolves from MEGA's own vendor repo,
  not official extra or the AUR: `Server =
  https://mega.nz/linux/repo/Arch_Extra/$arch` under section
  `[DEB_Arch_Extra]` (the section name equals the only published DB,
  `DEB_Arch_Extra.db` — inferred from pacman behavior plus the vendor
  directory listing, to confirm on Arch with `pacman -Si megasync`).
  Vendor key `B01C 8118 8048 0C85 4C73 EC7E 1A66 4B78 7094 A482`
  (`MegaLimited <support@mega.co.nz>`, `DEB_Arch_Extra.key`); the module
  verifies the fingerprint on a fetched copy and locally signs it — no
  `--recv-keys` from keyservers, no unsigned fallback. Packages are
  `megasync` then `thunar-megasync` (plugin depends on the client); the
  bundle lines are apps-owned and land after the repo seam. `dot` parses
  and validates the bundle first (malformed input fails before any key
  trust or config edit), then ensures the repo only when the parsed bundle
  requests a vendor package (one `install_packages` seam covers
  init/update/arch-setup, plus a `package add` gate for the two names).
  `arch-check` verifies read-only against the strong end state — exact
  section + pinned server, vendor key trusted (not merely present), and
  both packages visible — while `doctor` stays unchanged.
  Duplicated `[DEB_Arch_Extra]` sections are pacman-fatal rather than mere
  drift (pacman registers one database per repository name and refuses a
  second registration, which yay surfaces as `Database should be null:
  failed to register sync database`, breaking every transaction on the
  machine). `init`/`arch-setup` therefore repair them: copies that all carry
  the pinned Server/SigLevel collapse back to one — same staged write, same
  single backup, and the survivor is byte for byte what a fresh append
  produces — while copies that disagree still die, naming the header lines
  so the hand edit is a one-liner, because choosing which repository
  definition survives is a human decision. `arch-check` reports the
  duplication with its own count-and-lines diagnostic.
  Primary sources: `https://mega.io/desktop` (download URLs),
  `https://mega.nz/linux/repo/Arch_Extra/x86_64/` (directory + DB).
  Nothing MEGA is claimed on Fedora: no bundle lines, no repo, no key.
- Arch opencode2 is `aur "opencode-beta"` (binary `opencode2`); the
  official-extra `opencode` package is stable v1 (binary `opencode`) and is
  not a substitute. No `dot` change was needed (existing `aur` batch).
- Mullvad VPN needs its daemon: `arch_system_setup_mullvad` enables
  `mullvad-daemon.service` (required) only when `mullvad-vpn` is installed —
  a missing unit with the package present is a broken install and fails
  loudly, while a deselected package is a silent noop. Verify reports
  missing/disabled/inactive distinctly. Repair is
  `./dot arch-setup --only system`; init/update never provision services.

## Upstream installer package scope (resolved)

The Caelestia installer enables its default components (exact argv:
`caelestia install --noconfirm --aur-helper yay --disable-components
"firefox,fish,starship,fastfetch,foot,micro,btop" --enable-components
"uwsm,nvim"` — no vendor skip-packages flag exists). Every package the
defaults pull is now explicit in `packages/arch.bundle`, which the installer
skips when already installed, so the bundle is the single runtime recipe:
`caelestia-shell` (the shell itself; cli alone only installs it),
`pipewire-jack`, `pwvucontrol` (`pavucontrol` stays the keybind target),
`lazygit`, `ydotool`, `hyprpicker`, `frameworkintegration`, `qtengine`,
`darkly-bin`, `papirus-folders`, `git`. Disabled by flag, never installed:
`foot`, `micro`, `btop` (no second terminal/editor; `btop` stays out because
the workspace launcher hardcodes `foot`). Routes verified per package
(official extra vs AUR); `dot` owns the full recipe.
