# Dotfiles

Personal dotfiles for Arch Linux and Fedora. One script installs this machine's
packages and links every config file with GNU Stow.

## Setup

```bash
git clone https://github.com/arnaudcouturier/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./dot init
```

`init` reads `/etc/os-release` and runs one distro's path only — pacman and yay
on Arch, dnf on Fedora, never both. It installs that distro's bundle, installs
herdr (and Claude Code on Fedora), links `home/` into `$HOME`, syncs the herdr
plugins, and makes fish the login shell. Run it in a terminal: sudo, yay and
dnf all prompt.

On Arch, installing packages also upgrades the system (`pacman -Syu`) — Arch
does not support installing into a partially upgraded system. Config files are
overwritten without a backup, so review `home/` first, especially the Git
identity in `home/.config/git/config`.

On Arch, user files are only half the machine. From a minimal archinstall
with Limine and no desktop, run `./dot init` first, then `./dot arch-check`
and `./dot arch-setup` (see Arch provisioning below).

## Everyday use

```bash
./dot update            # pull, install, relink, sync plugins
./dot stow              # relink after editing home/
./dot doctor            # helpers, packages, plugins, symlinks, login shell
./dot check-packages    # list bundle entries missing from this machine
./dot package list | add NAME | remove NAME
./dot benchmark-shell   # time fish startup
./dot arch-check        # verify Arch provisioning (Arch-only, changes nothing)
./dot arch-setup        # provision this Arch machine (Arch-only, idempotent)
```

## Arch provisioning

Starting point: a minimal archinstall with Limine as the bootloader and no
desktop environment; btrfs for `/` if pre-upgrade snapshots are wanted.
Documented path: `./dot init`, then `./dot arch-check`, then
`./dot arch-setup`. Setup is idempotent: re-running it repairs drift.

```bash
./dot arch-setup                              # everything, in order
./dot arch-setup --only system,gpu            # subset of steps, canonical order kept
./dot arch-setup --replace-display-manager    # required to displace an incumbent DM
./dot arch-check                              # read-only verification
```

Steps run in order — `system` (pacman options, swap policy, services), `gpu`
(conditional microcode and driver stacks), `snapshots` (btrfs-only snapper),
`desktop` (home overlay plus Caelestia integration), `greeter` (greetd plus
sysc-greet, only after desktop verifies), `video` (mpv shader link),
`limine` (palette theming plus a named firmware entry, last). `--only`
filters provisioning steps, not the bundle: helpers, the full bundle
install, and file stowing always run, so any subset stays repairable with
nothing hidden.

Two safety contracts: without `--replace-display-manager`, setup refuses
beside an incumbent display manager instead of displacing it; Limine entries
are only added, never removed — the archinstall entry is kept. Caelestia is
the Arch desktop; Fedora keeps its current desktop untouched.

## Packages

One bundle per distro — `packages/arch.bundle`, `packages/fedora.bundle`. Every
line is a verb, a name, and a `#` comment saying why the entry is there.

```
repo "name"             pacman (Arch) / dnf (Fedora)
aur "name"              AUR via yay (Arch)
repofile "URL"          vendor repository file (Fedora)
copr "owner/project"    COPR repository (Fedora)
rpm "name" "URL"        pinned official RPM (Fedora)
flatpak "app.id"        Flathub app, system-wide (Fedora)
appimage "Name" "URL"   pinned AppImage into ~/Applications
npm "package"           global npm package (Fedora)
npm-scripts "package"   global npm package whose postinstall must run (Fedora)
```

`dot package add NAME` installs it and records it; a `--verb` flag picks
anything other than `repo`. Pass the URL for `rpm` and `appimage` — they
resolve the package name themselves, because the URL does not reveal it.
dot reads each pinned URL's build out of the package header and compares it
against the installed one, so bumping a URL — or a rolling "latest" one, as
ChatGPT's is — updates on the next `./dot update`; everything else updates
through its own package manager. ChatGPT's RPM also sets up OpenAI's own
repository on install, so plain dnf updates find it too. Flatpak is for
vendor-verified Flathub builds an app ships nowhere else — Obsidian and
Spotify on Fedora are the ones. `npm` installs with `--ignore-scripts`;
`npm-scripts` is the exemption for a package whose postinstall is the install.

Names are never translated between distros (`fd` vs `fd-find`, `github-cli` vs
`gh`), and every Fedora entry is verified against its vendor.

## Layout

- `dot` — the CLI; the CLI entry point; Arch provisioning lives in `lib/arch-*.sh` (sourced lazily for Arch commands only). NVIDIA drivers are
  hardware-conditional: `./dot nvidia` (also part of init/update) upgrades the
  system, then installs rpmfusion and akmod-nvidia per the Fedora gaming docs,
  only when the machine has an NVIDIA GPU.
- `packages/*.bundle` — one package list per distro.
- `home/` — mirrors `$HOME`, linked in by Stow: fish, Starship, Git, herdr,
  fastfetch, ripgrep, Hyprland input, Ghostty, agent skills, pi config, wallpapers.
  Edit here, never `~` directly, then run `./dot stow`. On Arch, `home-arch/`
  (desktop overlay) stows after; shared Ghostty and hypr input yield to it there.

- `lib/arch-*.sh` — Arch provisioning modules behind one setup/verify seam
  each (system, GPU, snapshots, greeter, Limine, video); `lib/arch-desktop.sh`
  is the desktop agent's Caelestia integration, guarded by interface checks.
- `system/arch/` — Arch system templates (`/etc` and `/boot` sources of truth).
- `home-arch/` — Arch desktop overlay (desktop agent owns it); stowed after
  `home/` on Arch only, same overwrite/no-backup rules.

herdr plugins are one `owner/repo` per line in
`home/.config/herdr/plugins.txt`. Fedora system provisioning stays out of this repo apart from NVIDIA; Arch provisioning is documented above.

Inspired by [Dillon Mulroy's dotfiles](https://github.com/dmmulroy/.dotfiles),
linked with [GNU Stow](https://www.gnu.org/software/stow/).
