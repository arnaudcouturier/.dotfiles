# AGENTS.md — maintainer notes

Dotfiles for Arch Linux and Fedora Workstation. `dot` owns installation, one
shared `home/`, one bundle per distro. System provisioning (GPU, bootloader,
greeter, desktop shell) and atomic editions are out of scope. README.md covers
usage; these are the rules that are easy to break.

- **Never edit `~` directly.** Edit `home/`, then `./dot stow`. Conflicts are
  overwritten without backup, deliberately — don't add backup logic.
- **Never translate package names between distros.** Each bundle is a recipe
  for one distro. `dot` refuses a verb the current distro cannot use and dies
  before changing anything. Verify a Fedora entry against its vendor before
  adding it — never guess a name from an Arch one.
- **No Flatpak.** There is no flatpak verb and there will not be one. An app
  with no distro package gets a pinned vendor RPM or an AppImage.
- **Prefer the route that brings updates**: vendor repository > COPR > pinned
  RPM > AppImage > npm, and `repo` over `aur`.
- **`rpm` and `appimage` entries carry an explicit name** because the URL does
  not reveal it — `ProtonMail-desktop-beta.rpm` installs as `proton-mail`, and
  Keeper's real dist tag is `1.fc37`. Read a name with
  `rpm -q --qf '%{NAME}' -p <URL>`.
- **Arch installs run `pacman -Syu`.** Arch does not support installing into a
  partially upgraded system; don't weaken it to `-S`.
- **Elevation is terminal sudo only.** `init`/`update` authenticate once and
  refresh in the background. No pkexec, no NOPASSWD, no `sudo -A`. Don't call
  `sudo` from an agent shell — let `dot` do it.
- **`init` must stay idempotent**: re-running it is the supported repair path.

Skills live in `home/.agents/skills/<name>/` and stow to `~/.agents/skills/`.
If a copy shows up under `.pi/`, fold it back and delete the copy; if a stowed
skill became a real directory, copy it into `home/` and restow. Never restore
a skill deleted from `home/`.

Bash: `set -euo pipefail`, quoted expansions, `die` on bad input, a comment
above anything non-obvious. Before committing a change to `dot`:
`bash -n dot && shellcheck dot && ./dot doctor`.
