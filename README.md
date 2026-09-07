# Dotfiles

Personal dotfiles for Arch Linux and Fedora. One script, `dot`, installs this
machine's packages and links every config file with GNU Stow.

## Setup

Start with Arch Linux or Fedora Workstation, `git`, and a user with `sudo`:

```bash
git clone https://github.com/arnaudcouturier/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./dot init
```

`init` reads `/etc/os-release`, installs that distro's bundle, bootstraps yay on
Arch when missing, installs herdr (and Claude Code on Fedora) from their vendors'
installers, links `home/` into `$HOME`, syncs the herdr plugins, and makes fish
the login shell. Run it in a terminal — sudo, yay, and dnf all prompt. Restart
the terminal afterwards.

It asks for the sudo password once and holds it for the run. Existing config
files are overwritten without a backup, so review `home/` first — especially the
Git identity in `home/.config/git/config`. On Arch, installing repository
packages also upgrades the system (`pacman -Syu`).

## Everyday use

```bash
./dot update            # pull, install, relink, sync plugins
./dot stow              # relink after editing home/
./dot doctor            # helpers, packages, plugins, symlinks, login shell
./dot check-packages    # list bundle entries missing from this machine
./dot package list      # show this distro's bundle
./dot package add NAME  # install and record a package
./dot package remove NAME
./dot benchmark-shell   # time fish startup
```

## Packages

Each distro has one bundle — `packages/arch.bundle` or `packages/fedora.bundle`
— listing every package with a comment saying why it is there. `dot package add`
installs first and records the entry only on success; a flag picks the verb:

| Verb | Add with | Meaning |
| --- | --- | --- |
| `repo "name"` | *(default)* | pacman on Arch, dnf on Fedora |
| `aur "name"` | `--aur` | AUR via yay (Arch) |
| `repofile "URL"` | `--repofile` | vendor repository file (Fedora) |
| `copr "owner/project"` | `--copr` | COPR repository (Fedora) |
| `rpm "name" "URL"` | `--rpm` | pinned official RPM (Fedora) |
| `appimage "Name" "URL"` | `--appimage` | pinned AppImage into `~/Applications` |
| `npm "package"` | `--npm` | global npm package (Fedora) |

```bash
./dot package add gh                                  # repo package
./dot package add brave-origin-bin --aur              # AUR (Arch)
./dot package add https://example.com/app.rpm --rpm   # pinned RPM (Fedora)
```

`rpm` and `appimage` install from a pinned URL that does not reveal what it
installs, so those entries record the name too — `dot` resolves it from the RPM
header (or the file name) when you add one, and then queries and removes by
name. Bump the URL to update. Everything else updates through its own package
manager, so prefer a vendor repository over a pinned download. Flatpak is
deliberately not supported: native packages only.

Package names are never translated between distros: Arch and Fedora spell things
differently (`fd` vs `fd-find`, `github-cli` vs `gh`) or agree by coincidence.
Every Fedora entry was verified against its vendor — `packages/fedora-audit.md`
records what was checked, and which alternatives were rejected.

## Layout

- `dot` — the CLI. Everything installation-related lives here.
- `packages/*.bundle` — one package list per distro.
- `home/` — mirrors `$HOME`, linked in by Stow. Edit here, never `~` directly,
  then run `./dot stow`.
  - `.config/` — fish, Starship, Git, herdr, fastfetch, ripgrep, Hyprland input.
  - `.agents/skills/` — shared agent skills.
  - `.pi/` — pi extensions and settings (`npm install` there for development;
    `node_modules/` is not stowed).
  - `Pictures/wallpapers/` — wallpapers.

herdr plugins are one `owner/repo` per line in
`home/.config/herdr/plugins.txt`. System provisioning — GPU, bootloader,
greeter, snapshots, desktop shell — deliberately stays out of this repo.

## Acknowledgments

Inspired by [Dillon Mulroy's dotfiles](https://github.com/dmmulroy/.dotfiles).
Links are managed with [GNU Stow](https://www.gnu.org/software/stow/).
