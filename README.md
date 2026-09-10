<h1 align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/img/dotfiles-hero-dark.svg">
  <img alt="Dotfiles for Arch and Fedora: shared tools, separate desktops" src="docs/img/dotfiles-hero-light.svg" width="760">
</picture>
</h1>

**Dotfiles** — one script installs this machine's packages and links every config with GNU Stow.
Arch gets the full Caelestia workstation; Fedora gets apps and config on the desktop it already has.

[Setup](#setup) · [Everyday](#everyday) · [Arch system](#arch-system) · [Packages](#packages) · [Customize](#customize)

> [!CAUTION]
> Install and restow overwrite conflicting files under `$HOME` **with no backup**
> (`doctor` and `arch-check` only inspect — they change nothing).
> Before running setup, review `home/`, `home-arch/`, and `home-fedora/` —
> notably the Git identity in
> [`home/.config/git/config`](home/.config/git/config).

|  | Arch | Fedora |
|---|---|---|
| Scope | full workstation: system plus Caelestia desktop | apps and config on your current desktop (NVIDIA drivers excepted) |
| Starts from | minimal archinstall (Limine, no DE; btrfs for snapshots) | Workstation (not atomic) |
| Configs linked | `home/` + `home-arch/` | `home/` + `home-fedora/` |

## Setup

Run everything in a terminal as your regular user, never root: sudo asks once,
and `yay` shows each AUR build for review.

```bash
git clone https://github.com/arnaudcouturier/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

`init` installs helpers, this distro's bundle, links configs, syncs herdr
plugins, and sets the fish login shell.

**Arch** — init, then provision the system:

```bash
./dot init
./dot arch-setup    # idempotent; re-running repairs drift
./dot arch-check    # verify afterwards; changes nothing
```

**Fedora** — init is the whole install:

```bash
./dot init
./dot doctor        # read-only check that everything landed
```

Re-running setup is the repair path.

## Everyday

| Command | Run it when… |
|---|---|
| `./dot update` | you want the latest: pull, reinstall, relink, resync plugins |
| `./dot stow` | after editing the repo; never edit `~` directly |
| `./dot doctor` | something feels off; checks helpers, packages, links, shell |
| `./dot check-packages` | you want the bundle entries missing here |
| `./dot package add NAME` | adding one thing (recorded in the bundle; `--aur`/`--rpm`/… for non-repo) |
| `./dot package remove NAME` | removing one thing |
| `./dot benchmark-shell` | fish feels slow; warns past 100 ms |
| `./dot nvidia` | Fedora-only NVIDIA drivers; refuses on Arch, no-op without the hardware |

## Arch system

`arch-setup` runs `system → gpu → snapshots → desktop → greeter → video → limine`
in canonical order. `--only` filters steps — never the bundle install or stow —
so any subset stays repairable.

> [!NOTE]
> Two contracts: without `--replace-display-manager`, setup refuses beside an
> incumbent display manager instead of displacing it; Limine entries are only
> added, never removed. Step-by-step reference: [`docs/usage.md`](docs/usage.md).

## Packages

One bundle per distro — [`arch`](packages/arch.bundle), [`fedora`](packages/fedora.bundle).
Every line is a verb, a name, and a `# comment` saying why it's there. Names are never
translated between distros (`fd` vs `fd-find`, `gh` vs `github-cli`); Fedora sources are
verified against their vendors; global npm entries install with `--ignore-scripts` unless
the postinstall *is* the install. Verb and policy reference: [`docs/usage.md`](docs/usage.md).

## Customize

Edit the repo, then `./dot stow` to relink:

- Shared: [`home/`](home/) — including Fish ([`config.fish`](home/.config/fish/config.fish)), Git, nvim, agent skills
- Arch desktop: [`home-arch/`](home-arch/) — monitors in [`hypr-user.lua`](home-arch/.config/caelestia/hypr-user.lua), night light in [`hypr-vars.lua`](home-arch/.config/caelestia/hypr-vars.lua) (`automaticNightLight`; <kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>N</kbd> toggles anytime)
- Fedora desktop: [`home-fedora/`](home-fedora/) — Ghostty theme, hypr input

On Arch, the generated `~/.config/hypr/` tree is upstream output — customize the sources above, not it.

## Read more

- [`docs/usage.md`](docs/usage.md) — command, package-policy, and Arch safety reference
- [`docs/arch-coverage.md`](docs/arch-coverage.md) — where every provisioned subsystem came from
- [`packages/arch.bundle`](packages/arch.bundle) · [`packages/fedora.bundle`](packages/fedora.bundle) — the actual recipes

---
*Inspired by [Dillon Mulroy's dotfiles](https://github.com/dmmulroy/.dotfiles), linked with [GNU Stow](https://www.gnu.org/software/stow/).*
