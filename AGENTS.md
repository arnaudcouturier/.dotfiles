# AGENTS.md — maintainer notes

Dotfiles for Arch Linux and Fedora Workstation. `dot` owns installation, one
shared `home/`, one bundle per distro, plus an Arch-only `home-arch/` overlay.
Arch system provisioning lives behind `./dot arch-setup`/`arch-check`
(idempotent; re-running repairs). Fedora system provisioning lives behind
`./dot fedora-setup`/`fedora-check` (same machinery: canonical steps,
`--only` filters, idempotent repair): one opt-in gaming step
(`lib/fedora-gaming.sh`, official packages only), one desktop step
(`lib/fedora-desktop.sh`: vanilla Umbriel plus native Noctalia, Terra
bootstrap for the compositor, Fedora packages otherwise), and one greeter
step (`lib/fedora-greeter.sh`: greetd plus Noctalia Greeter, GDM/GNOME kept
installed for recovery, explicit `--replace-display-manager` to switch).
NVIDIA still installs through init/update. Atomic editions stay out of scope. README.md
covers usage; these are the rules that are easy to break.

- **Never edit `~` directly.** Edit `home/`, then `./dot stow`. Conflicts are
  overwritten without backup, deliberately — don't add backup logic (home files never do). The `/etc` and bootloader backups inside
  `lib/arch-*.sh` are the narrow exception: boot and login configs get one
  restorable backup. The one-time `/etc/greetd/config.toml` backup inside
  `lib/fedora-greeter.sh` is the same narrow exception on Fedora. Second narrow exception: the two compositor-owned user
  files (`~/.config/caelestia/hypr-user.lua`, `hypr-vars.lua`) deploy once as
  real files and are edited in place — stow can never own paths the running
  compositor recreates, and upstream defines both as user-edited.
- **Stow is per-distro selection.** Shared `home/` holds common files plus
  a Ghostty forwarding alias that shared stow skips on
every distro; `home-fedora/` stows the Fedora sources and `home-arch/`
the Arch ones, each with the same overwrite/no-backup rules. `home-arch/`
additionally excludes the two compositor-owned user files from stow (the
desktop module copy-deploys them as real files instead). `doctor`
checks each tree against its selected source. The retired Hyprland input path
remains in the exclusion list only for legacy-link cleanup.
- **Never translate package names between distros.** Each bundle is a recipe
  for one distro. `dot` refuses a verb the current distro cannot use and dies
  before changing anything. Verify a Fedora entry against its vendor before
  adding it — never guess a name from an Arch one.
- **Flatpak only for a vendor-verified Flathub build.** `flatpak` entries
  install system-wide from flathub and are Fedora-only; an app whose Flathub
  build is not verified by its vendor gets a pinned vendor RPM or an AppImage
  instead. Fedora's flatpak entries need `repo "flatpak"` in the bundle: repo
  packages install before anything else, so the client is there in time.
- **Prefer the route that brings updates**: vendor repository > COPR >
  verified Flathub > pinned RPM > AppImage > npm, and `repo` over `aur`.
- **npm entries install with `--ignore-scripts`.** The `npm-scripts` verb is
  the deliberate exemption, for a package whose postinstall *is* the install
  (it fetches the platform binary). Don't file an entry there to make an
  install quieter — only when the CLI is a stub without it. `npm-scripts`
  allow-lists only the entry's own package via `--allow-scripts` (npm 12
  denies all scripts by default). Globals live in the user-owned `~/.local`
  prefix, so installs and postinstalls run as the user, never root (no
  `sudo npm install`); `init`/`update` converge the prefix and sweep stale
  root-owned copies out of `/usr`.
- **`rpm` and `appimage` entries carry an explicit name** because the URL does
  not reveal it — `keeperpasswordmanager-18.6.1-1.x86_64.rpm` installs as
  `keeperpasswordmanager`, and
  Keeper's real dist tag is `1.fc37`. Read a name with
  `rpm -q --qf '%{NAME}' -p <URL>`.
- **Arch installs run `pacman -Syu`.** Arch does not support installing into a
  partially upgraded system; don't weaken it to `-S`.
- **NVIDIA handling is hardware-conditional (Fedora path below; Arch lives in lib/arch-gpu.sh).** `ensure_nvidia` (init/update, or
  `./dot nvidia`) detects a PCI vendor-10de display controller (VGA/3D/Display
  class, mirroring `arch_gpu_detect_vendors`) with one lspci call and, on
  a hit, follows the Fedora gaming docs (system upgrade, then rpmfusion release
  packages + akmod-nvidia — a driver built against a fresh install's stale
  kernel comes up incomplete). It is a silent no-op otherwise; keep it that way.
- **Arch gating precedes sudo.** `arch-setup`/`arch-check` refuse on non-Arch
  before elevation, network, or any mutation. Keep it that way.
- **Display-manager changes need the explicit flag.** `arch-setup` refuses
  beside an incumbent DM; only `--replace-display-manager` disables one.
  `fedora-setup` follows the same contract for its greeter step.
  Limine entries are only added, never removed or reordered.
- **No hardcoded machine layout.** GPU environment stays conditional on
  detected hardware; no PCI IDs, disks, or hostnames in modules.
- **`lib/arch-desktop.sh` belongs to the desktop agent.** `dot` guards its
  interface with `declare -F`; never implement desktop behavior in `dot` or
  system modules. `home-arch/` likewise: reference, never create.
- **Elevation is terminal sudo only.** `init`/`update` authenticate once and
  refresh in the background. No pkexec, no NOPASSWD, no `sudo -A`. Don't call
  `sudo` from an agent shell — let `dot` do it.
- **`init` must stay idempotent**: re-running it is the supported repair path.

Curated skill sources live in `home/.agents/skills/<name>/`. Stow skips skills
and the retired Pi workspace. `dot init`/`update` installs skills globally via
`npx skills` for OpenCode, Claude Code, Codex and Pi; `lib/shared-home.sh`
then refreshes Matt Pocock's set and Herdr's official skill. npx owns deployed
skill directories and compatibility links. Edit curated sources in the repo,
not the installed copies. Never restore a deleted skill. Retired stow links
are removed only when they resolve into this checkout; preserve local files.

Bash: `set -euo pipefail`, quoted expansions, `die` on bad input, a comment
above anything non-obvious. Before committing a change to `dot`:
`bash -n dot lib/arch-*.sh && shellcheck dot lib/arch-*.sh && ./dot doctor`.
