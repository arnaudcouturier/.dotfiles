# Dotfiles

Personal dotfiles for Arch Linux. One script installs packages and links configuration files with GNU Stow.

## Setup

Start with Arch Linux, `git`, and a user with `sudo` access:

```bash
git clone https://github.com/arnaudcouturier/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./dot init
```

`init` installs the package bundle, bootstraps yay when needed, installs Herdr and its plugins, links the configs, and sets fish as your login shell. Run it from a terminal for sudo and AUR prompts, then restart your terminal.

Repository package installs also run a full system upgrade (`pacman -Syu`).

Existing config files are overwritten. Review `home/` before installing, especially the personal Git identity in `home/.config/git/config`.

## Everyday use

```bash
./dot update                      # Pull changes, install packages, and relink configs
./dot stow                        # Relink configs after editing home/
./dot doctor                      # Check packages, helpers, plugins, symlinks, and shell
./dot check-packages              # List missing packages
./dot package list                # Show the package bundle
./dot package add NAME            # Add and install an Arch repository package
./dot package add NAME --aur      # Add and install an AUR package
./dot package remove NAME         # Remove from the bundle and uninstall
./dot benchmark-shell             # Measure fish startup
```

## Layout

- `dot`: the Bash CLI.
- `packages/bundle`: packages listed as `repo "name"` or `aur "name"`, with purpose comments.
- `home/`: files at their home-relative paths, linked into `$HOME` by Stow.
- `home/.config/`: fish, Starship, Git, Herdr, fastfetch, and ripgrep settings.
- `home/.agents/skills/`: shared agent skills.
- `home/.pi/`: pi extensions and settings.
- `home/Pictures/wallpapers/`: wallpaper collection.

Edit files in `home/`, then run `./dot stow`. Herdr plugins are listed one `owner/repo` per line in `home/.config/herdr/plugins.txt`. System provisioning stays outside this repo.

For pi extension development, run `npm install` in `~/.pi`; dependency directories are excluded from Stow.

## Acknowledgments

Inspired by [Dillon Mulroy’s dotfiles](https://github.com/dmmulroy/.dotfiles). Configuration links are managed with [GNU Stow](https://www.gnu.org/software/stow/).
