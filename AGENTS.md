# AGENTS.md — maintainer notes

Dotfiles for Arch Linux and Fedora Workstation. Opinionated and Stow-based:
`dot` owns installation deterministically, one shared `home/`, one explicit
bundle per distro. Atomic editions (Silverblue) are out of scope, and so is
system provisioning — GPU, greeter, bootloader, snapshots, desktop shells.
README.md covers usage; this file covers the rules that are easy to break.

## Layout

- `dot` — the only script. All installation logic lives here.
- `packages/arch.bundle`, `packages/fedora.bundle` — the package lists,
  picked by `/etc/os-release`. `dot package add/remove` edits them; the
  format is documented at the top of each file.
- `packages/fedora-audit.md` — how each Fedora entry was verified, and which
  routes were rejected. Add to it whenever you add a Fedora entry.
- `home/` — mirrors `$HOME` (`home/.config/fish` → `~/.config/fish`), deployed
  with `stow -R --no-folding`. `node_modules/` is skipped (run `npm install`
  in `~/.pi` instead).

## Rules that matter

- **Never edit `~` directly.** Edit `home/`, then `./dot stow`. Files, not
  directories, are the unit — Stow creates the directories.
- **Never translate package names between distros.** Each bundle is a recipe
  for one distro. Every Fedora entry must be verified against its vendor and
  recorded in `packages/fedora-audit.md`; an unverified app gets a TODO
  comment, never a guessed name. `dot` refuses a verb that the current distro
  cannot use, and dies before changing anything.
- **Prefer the route that brings updates.** On Fedora: vendor repository >
  COPR > pinned RPM > AppImage > npm. `repo` beats `aur` on Arch.
  **Flatpak is not an option** — the user does not want it, and `dot` has no
  flatpak verb. An app with no native package gets a pinned RPM or AppImage.
  Pinned URLs (`rpm`, `appimage`) age — they carry an explicit name because
  the URL does not reveal what it installs.
- **`install_packages` runs in three passes**: configure every source
  (`repofile`, `copr`), then one batched transaction per package manager, then
  everything else in bundle order. Sources are therefore ready before any
  package installs — keep them next to the entries they feed for readability,
  not because the order is load-bearing.
- **Conflicts are overwritten without backup.** That is deliberate. Don't
  reintroduce backup logic or per-OS branching in `stow_dotfiles`.
- **Elevation is terminal sudo only.** `init`/`update` authenticate once and a
  background `sudo -n -v` keeps the timestamp alive. No pkexec, no NOPASSWD
  snippets (a scoped pacman rule is still root via `-U`/`--config`/hooks), no
  `sudo -A` — yay's PKGBUILD review needs a terminal anyway. Don't call
  `sudo` from an agent shell; let `dot` do it.
- **`init` must stay idempotent.** Re-running it is the supported repair path.
- Some tools install from their vendor's own script (`ensure_upstream`):
  herdr on both distros, Claude Code on Fedora, where npm installs are
  deprecated upstream. On Arch both come from packages.

## Skill layout (stowed, do not duplicate)

Canonical skills live in `home/.agents/skills/<name>/` and stow to
`~/.agents/skills/<name>`. If drift is noticed, fix it unasked:

- A skill under `home/.pi/agent/skills/` or `~/.pi/agent/skills/`: move unique
  content into `home/.agents/skills/`, then delete the `.pi` copy.
- `~/.agents/skills/<name>` is a real directory instead of a symlink: copy it
  back into `home/.agents/skills/<name>/`, remove the live directory, restow.
- Do not restore skills deleted from `home/.agents/skills/`.

## Style and testing

Bash with `set -euo pipefail`, double-quoted expansions, `die` on bad input,
and a comment above anything non-obvious. Before committing a change to `dot`:

```bash
bash -n dot && shellcheck dot
./dot help && ./dot check-packages && ./dot doctor
```

`check-packages` and `doctor` are read-only and safe to run anywhere. To
exercise the other distro's bundle without that distro, source the script with
its last line removed and set `DISTRO`/`BUNDLE_FILE` by hand.

## Anti-patterns

- Editing `~/.config/...` instead of `home/...`.
- Invented or translated package names; unverified Fedora sources.
- Secrets in `home/` — use a secret manager, never commit tokens.
- Installation logic anywhere but `dot`.
