<h1 align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/img/dotfiles-hero-dark.svg">
  <img alt=".dotfiles — Configuration files and setup scripts: fanned configuration cards tied by a stow string" src="docs/img/dotfiles-hero-light.svg" width="760">
</picture>
</h1>

Dotfiles managed with GNU Stow.

<p align="center">
<a href="#setup">Setup</a> · <a href="#commands">Commands</a> · <a href="#arch-system">Arch system</a> · <a href="#configuration">Configuration</a>
</p>

> [!CAUTION]
> Install and restow overwrite conflicting files under `$HOME` **with no backup**
> (`doctor` and `arch-check` only inspect — they change nothing).
> Before running setup, review `home/`, `home-arch/`, and `home-fedora/` —
> notably the Git identity in
> [`home/.config/git/config`](home/.config/git/config).

## Setup

Run as the regular user, never root:

```bash
git clone https://github.com/arnaudcouturier/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

`init` installs helpers and this distro's bundle, links configs, syncs herdr
plugins and integrations, and sets fish as the login shell.

**Arch** — from minimal archinstall (Limine, no desktop; btrfs for snapshots).
Links `home/` + `home-arch/`:

```bash
./dot init
./dot arch-setup
./dot arch-check
```

**Fedora** — Workstation, non-atomic only. Links `home/` + `home-fedora/`;
system provisioning is out of scope except NVIDIA:

```bash
./dot init
./dot doctor
```

Rerun `init` to reapply the setup.

## Commands

| Command | Purpose |
|---|---|
| `./dot update` | Pull, reinstall, relink, resync plugins |
| `./dot stow` | Relink configs after editing the repo; never edit `~` directly |
| `./dot doctor` | Check helpers, packages, links, shell |
| `./dot check-packages` | List bundle entries not installed |
| `./dot package add NAME` | Install and record one entry (`--aur`/`--rpm`/… for non-repo) |
| `./dot package remove NAME` | Drop the bundle line, then uninstall |
| `./dot benchmark-shell` | Time fish startup; warns past 100 ms |
| `./dot nvidia` | Fedora NVIDIA drivers; no-op without the hardware |

## Arch system

`arch-setup` runs `system → gpu → gaming → snapshots → desktop → greeter → video → limine`
in order. `--only` filters steps, never the bundle install or stow. `gaming`
is opt-in: it asks once (default No) and skips quietly when declined.

> [!NOTE]
> `arch-setup` refuses to replace an existing display manager unless
> `--replace-display-manager` is provided. Existing Limine entries are
> preserved. Details:
> [`docs/usage.md`](docs/usage.md), [`docs/arch-coverage.md`](docs/arch-coverage.md).

## Configuration

Edit the repo, then run `./dot stow`:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/img/dotfiles-flow-dark.svg">
  <img alt="Configuration workflow: edit the repo, then run ./dot stow to link configs into the home directory" src="docs/img/dotfiles-flow-light.svg" width="760">
</picture>

- Shared: [`home/`](home/) — Fish ([`config.fish`](home/.config/fish/config.fish)), Git, nvim, agent skills
- Arch: [`home-arch/`](home-arch/) — monitors in [`hypr-user.lua`](home-arch/.config/caelestia/hypr-user.lua), night light in [`hypr-vars.lua`](home-arch/.config/caelestia/hypr-vars.lua) (`automaticNightLight`; <kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>N</kbd> toggles)
- Fedora: [`home-fedora/`](home-fedora/) — Ghostty theme, hypr input

On Arch, `~/.config/hypr/` is generated output; edit the sources above.

Packages: [`arch`](packages/arch.bundle) · [`fedora`](packages/fedora.bundle) —
one commented line per entry. Verbs and policy: [`docs/usage.md`](docs/usage.md).
