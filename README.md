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

## Everyday use

```bash
./dot update            # pull, install, relink, sync plugins
./dot stow              # relink after editing home/
./dot doctor            # helpers, packages, plugins, symlinks, login shell
./dot check-packages    # list bundle entries missing from this machine
./dot package list | add NAME | remove NAME
./dot benchmark-shell   # time fish startup
```

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

- `dot` — the CLI; all installation logic lives here. NVIDIA drivers are
  hardware-conditional: `./dot nvidia` (also part of init/update) installs
  rpmfusion and akmod-nvidia per the Fedora gaming docs only when the machine
  has an NVIDIA GPU.
- `packages/*.bundle` — one package list per distro.
- `home/` — mirrors `$HOME`, linked in by Stow: fish, Starship, Git, herdr,
  fastfetch, ripgrep, Hyprland input, agent skills, pi config, wallpapers.
  Edit here, never `~` directly, then run `./dot stow`.

herdr plugins are one `owner/repo` per line in
`home/.config/herdr/plugins.txt`. System provisioning stays out of this repo.

Inspired by [Dillon Mulroy's dotfiles](https://github.com/dmmulroy/.dotfiles),
linked with [GNU Stow](https://www.gnu.org/software/stow/).
