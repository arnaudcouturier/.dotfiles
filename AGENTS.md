# AGENTS.md — maintainer notes for this repo (and for pi)

This repo is Arch Linux, opinionated, and Stow-based. `dot` owns install
deterministically; AI assists with edits, never with package-name translation.

## Layout

- `dot` — the only script. Entry points: `init`, `stow`, `doctor`,
  `check-packages`, `package {add,remove,list}`, `update`, `benchmark-shell`.
- `home/` — mirrors `$HOME` (`home/.config/fish` → `~/.config/fish`).
  Deployed with `stow -R -d . -t $HOME home`, skipping `node_modules/`
  (run `npm install` in `~/.pi` instead). Never edit `~` directly;
  edit `home/` then run `./dot stow`.
- `packages/bundle` — package list. Two verbs only:
  `repo "name"` (official repos, pacman) and `aur "name"` (AUR, yay).
  `dot package add/remove` edits this file; don't hand-edit the format.
- System provisioning (GPU, greeter, bootloader, snapshots, desktop shells)
  does NOT live here.

## Commands

```bash
./dot init             # helpers (yay, stow) + bundle + herdr installer + stow + herdr plugins + fish login shell
./dot stow             # re-link home/, overwriting conflicts (no backup)
./dot doctor           # helpers + packages + symlinks + login shell + broken links
./dot check-packages   # list bundle entries missing from this machine
./dot package add NAME [--aur]
./dot package remove NAME
./dot update           # git pull --rebase + install + restow + herdr plugins
./dot benchmark-shell  # time fish startup over N runs
```

Arch needs only `git` and `sudo`; `dot init` bootstraps `yay-bin` when missing.

```bash
git clone https://github.com/arnaudcouturier/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./dot init
```

## Conventions for edits

- New dotfile: place it under `home/` at its `$HOME`-relative path, then
  `./dot stow`. Keep files, never directories, as the unit (Stow handles dirs).
- New package: prefer `./dot package add NAME [--aur]`. `repo` beats `aur`
  when a package exists in both. Keep the trailing `# purpose` comment.
- Herdr plugins: one `owner/repo` source per line in
  `home/.config/herdr/plugins.txt`, synced by `./dot init`/`update` via
  `herdr plugin install --yes` (server config reloads when running).
- Conflicts are overwritten without backup — this repo is opinionated by
  design. Don't reintroduce backup logic or per-OS branching.
- Bash style: `set -euo pipefail`, double-quote expansions, `die` on parse
  errors. Test with `bash -n dot`, `./dot help`, `./dot doctor`,
  `./dot check-packages`.
- Keep installation logic in `dot`.
  Don't use `sudo` inside agent shells; `dot` calls `sudo`/`yay` itself.
- Elevation: `init`/`update` ask for the sudo password once up front, then a
  background `sudo -n -v` refresher (reaped on exit) keeps it alive.
  Terminal sudo is the only mechanism: no pkexec fallback, no NOPASSWD snippets (a scoped pacman rule is
  still full root via -U/--config/hooks), no sudo -A (yay's PKGBUILD review
  needs a terminal anyway).

## Skill layout (stowed, do not duplicate)

Canonical skills live in `home/.agents/skills/<name>/` and stow to
`~/.agents/skills/<name>`. If drift is noticed, fix it unasked:

- A skill under `home/.pi/agent/skills/` or `~/.pi/agent/skills/`: move unique
  content into `home/.agents/skills/`, then delete the `.pi` copy/symlink.
- `~/.agents/skills/<name>` is a real directory instead of a symlink: copy it
  back into `home/.agents/skills/<name>/`, remove the live dir, restore stow.
- Do not restore skills deleted from `home/.agents/skills/`.

## Anti-patterns

- Editing `~/.config/...` directly instead of `home/...`.
- Use only Arch repository and AUR package names.
- Putting secrets in `home/` (use a secret manager, never commit tokens).
- Making `init` non-idempotent — re-running `init` must be safe.
