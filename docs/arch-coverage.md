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
| `modules/45-caelestia.sh` (installer wrapper, tree verification, app integrations, wallpapers) | Split | Installer + user-runtime configuration: desktop agent inside `arch_desktop_configure_caelestia` (`lib/arch-desktop.sh`, `home-arch/`). Night-light patch concept survives as their patch function. Spotify/Spicetify and editor re-theming to non-selection editors are excluded; wallpapers are desktop-owned (sparse `dharmx/walls` clone into `~/Pictures/Wallpapers`, case-distinct from shared `~/Pictures/wallpapers`, which stays untouched). `uwsm` is an explicit `repo` entry (Arch extra, vendor-confirmed; desktop upstream verification confirms the Caelestia manifest ships `packages=[uwsm]`). |
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

- Scheme replay lives in an overlay `fish/conf.d` snippet; the installer
  disables its fish/starship/fastfetch components, so shared
  `fish/config.fish` is never written through its symlink.
- The `hypr/input.lua` keyboard equivalent lives in
  `home-arch/.config/caelestia/hypr-user.lua`; nothing may ever live under
  `home-arch/.config/hypr/` (upstream-deployed directory).
- `uwsm` is an explicit bundle entry (Arch extra); the installer enables
  the component, and verification asserts its session files.
- `neovim` is bundled (shared LazyVim config; Caelestia editor target); no
other editors.

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
