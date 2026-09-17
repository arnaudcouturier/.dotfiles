# Usage reference

Operator manual for this repo. The [README](../README.md) is the quickstart;
the subsystem history lives in [arch-coverage.md](arch-coverage.md); the package
recipes are [`packages/arch.bundle`](../packages/arch.bundle) and
[`packages/fedora.bundle`](../packages/fedora.bundle), one commented line per entry.

## Everyday commands

- `./dot update` — `git pull --rebase`, then everything `init` does.
- `./dot stow` — relink shared `home/` plus the selected overlay after editing
  the repo. No sudo, no backup: conflicts are overwritten.
- `./dot doctor` — checks helpers (git, stow, fish, herdr, claude, plus yay on
  Arch), login shell, full bundle, herdr plugins and integrations, and symlinks against their
  selected sources.
- `./dot check-packages` — lists bundle entries missing here (exit 1 when any).
- `./dot package list` — prints this distro's bundle.
- `./dot package add NAME|URL [--aur|--rpm|--flatpak|--repofile|--copr|--appimage|--npm|--npm-scripts]`
  — installs first, then records the entry (a failed install never leaves a
  phantom line). No flag means `repo`; e.g. `./dot package add foo --aur`.
  `rpm`, `appimage`, and `repofile` take an `https` URL: `rpm` reads the real
  name from the package header, `appimage` guesses it from the file name
  (fix by hand if wrong), `repofile` records the URL itself. Give the new
  line a trailing `# why` comment by hand.
- `./dot package remove NAME` — drops the bundle line, then uninstalls.
- `./dot benchmark-shell [-r RUNS]` — times fish startup (1–100 runs); warns past 100 ms.

Herdr plugins are one `owner/repo` per line in `home/.config/herdr/plugins.txt`;
`init`/`update` sync them and reload the live server when one runs.

Herdr uses defaults except Plannotator's two document-review shortcuts.
The integration list is empty: no agent hooks are installed automatically,
including into Pi. Pi is installed bare, without a managed extension workspace.
Removing entries does not uninstall previously installed Herdr plugins or
integrations; use `herdr plugin uninstall` / `herdr integration uninstall`
to retire those on an existing machine after reviewing its installed state.

Skills are installed globally by `init`/`update` using `npx skills` (user-owned,
never sudo). Stow skips `home/.agents/skills/`; this is the curated source set,
not the deployment mechanism. Local skills install first, then Matt Pocock's
upstream collection and Herdr's official skill override matching names. The
CLI version and agent targets live in `lib/shared-home.sh`. OpenCode and Codex
use the universal skill directory; the CLI also links Claude Code and Pi.
Plain `dot stow` does not download skills; use `init`/`update` for a full refresh.

## Fedora provisioning

Starting point: vanilla Fedora Workstation, non-atomic. `fedora-setup` and
`fedora-check` refuse on non-Fedora before elevation, network, or any mutation,
and mirror the Arch step machinery: canonical order, `--only` filters, idempotent
re-runs that repair.

Steps run in canonical order; `--only` filters steps, never the bundle install
or stow:

1. `gaming` — opt-in Steam stack: asks once (default No) and skips quietly on
   No or without a terminal. Installs only vendor-backed packages: Steam from
   RPM Fusion (the route NVIDIA drivers already use), GameMode, MangoHud,
   GOverlay, Gamescope and Protontricks from Fedora's own repos. No third-party
   COPRs: vkbasalt and ProtonPlus have no official Fedora or RPM Fusion
   package and are deliberately excluded. Fedora resolves the 32-bit game
   libraries itself; there is no multilib toggle, and GameMode needs no group
   membership on Fedora.
2. `desktop` — vanilla Umbriel plus the native Noctalia shell: `umbriel-nightly`
   from the community Terra repository (bootstrapped once via its release
   package; later transactions keep signature checks), `noctalia`, `ghostty`
   (Mod+Return overrides the packaged kitty default), `xwayland-satellite`,
   the GTK portal fallback, and `gnome-keyring` for Secret Service. The Umbriel portal
   backend arrives as an `umbriel-nightly` dependency and prefers
   `umbriel;gtk` without touching the retained GNOME session. The personal
   keybindings are Mod+K for the native cheatsheet plus Mod+Return for
   ghostty; everything else stays packaged defaults, and Noctalia autostarts
   once from the compositor.
3. `greeter` — greetd plus Noctalia Greeter (`noctalia-greeter-session`, which
   bundles its own login compositor). GDM and GNOME stay installed for
   recovery, never enabled alongside greetd. Re-verifies the desktop first,
   even under `--only greeter`.

Safety contracts (same as Arch): without `--replace-display-manager`, setup
refuses beside an incumbent display manager instead of displacing it. Only
the explicit flag switches. One exception is not a switch: gdm arrives only
as the recovery desktop, and if its dnf preset enables it on a host that had
no display manager, setup stands that artifact back down without demanding
the flag. The previous `/etc/greetd` config gets one
`.dotfiles-backup`, like the Arch boot/login templates.

`./dot fedora-check [--only step,...]` verifies without changing anything; on a
fresh host it reports what setup will add.

NVIDIA drivers are not a step: they install through `init`/`update` (and
`./dot nvidia`) when the hardware probe finds an NVIDIA display controller,
following the Fedora gaming docs.

## Arch provisioning

Starting point: minimal archinstall with Limine, no desktop; btrfs on `/` only
if pre-upgrade snapshots are wanted. `arch-setup` and `arch-check` refuse on
non-Arch before elevation, network, or any mutation.

Steps run in canonical order; `--only` filters steps, never the bundle install
or stow, so any subset stays repairable:

1. `system` — pacman options, swap/zram policy, services (incl. `mullvad-daemon`,
   enabled only when `mullvad-vpn` is installed).
2. `gpu` — conditional microcode and driver stacks per detected hardware.
3. `snapshots` — snapper on btrfs only; other filesystems skip cleanly.
4. `desktop` — Arch overlay plus Caelestia integration.
5. `greeter` — greetd plus sysc-greet; re-verifies the desktop first, even under
   `--only greeter`.
6. `limine` — palette theming plus a named firmware entry, last.

Safety contracts:

- Without `--replace-display-manager`, setup refuses beside an incumbent display
  manager instead of displacing it. Only the explicit flag switches.
- Limine entries are only added, never removed or reordered; the archinstall
  entry is kept.
- `./dot arch-check [--only step,...]` verifies without changing anything; on a
  fresh host it reports what setup will add. After setup: reboot, then
  `arch-check` from a Hyprland session.

## Fedora notes

Fedora system provisioning covers the gaming, desktop, and greeter steps
above, plus NVIDIA. Atomic/OSTree editions are not supported.

`./dot nvidia` (also part of `init`/`update`) is Fedora-only and refuses
elsewhere. It probes once (`lspci` for a vendor-`10de` display controller —
`VGA`/`3D`/`Display` class, so non-display NVIDIA functions never trigger
it) and is a silent no-op without NVIDIA display hardware. On a hit it follows the Fedora gaming docs: full
system upgrade first (a driver built against a fresh install's stale kernel
comes up incomplete), then rpmfusion release packages, then `akmod-nvidia`.
The kernel module keeps building after install — wait a few minutes
(check `modinfo nvidia`), then reboot.

## Package policy

| Verb | Distros | Meaning |
|---|---|---|
| `repo "name"` | both | official and configured vendor repositories (`pacman` / `dnf`) |
| `aur "name"` | Arch | AUR via `yay`, with a PKGBUILD review prompt |
| `repofile "URL"` | Fedora | vendor repository file, configured before installs |
| `copr "owner/project"` | Fedora | COPR enablement, configured before installs |
| `rpm "name" "URL"` | Fedora | pinned official RPM; name read from the package header |
| `flatpak "app.id"` | Fedora | system-wide Flathub install; vendor-verified builds only |
| `appimage "Name" "URL"` | both | pinned AppImage into `~/Applications` plus launcher |
| `npm "package"` | both | user-global install into `~/.local` (no sudo), always `--ignore-scripts` |
| `npm-scripts "package"` | both | exemption when the postinstall *is* the install (entry's own scripts allow-listed via `--allow-scripts`, run as the user) |

Rules: names are never translated between distros; every Fedora entry is
verified against its vendor before adding — never guessed from the Arch name.
Prefer the route that brings updates (vendor repo > COPR > verified Flathub >
pinned RPM > AppImage > npm) and `repo` over `aur`; npm is the vendor route for
JS-only tools that no repo or AUR entry carries (pair it with `repo "npm"` on
Arch). npm globals live in the user-owned `~/.local` prefix, so npm entries
never use sudo; `init`/`update` converge the prefix and sweep stale
root-owned copies out of `/usr`. Flatpak entries need
`repo "flatpak"` in the bundle so the client installs first. Pinned `rpm` URLs
are build-compared on every run, so a bumped URL — or a rolling `latest` one —
updates on the next `./dot update`. A verb the current distro cannot use dies
before anything changes.

Arch installs run `pacman -Syu`, never `-S`: Arch does not support installing
into a partially upgraded system.

## Layout and files

- `dot` — the CLI. Arch provisioning lives in `lib/arch-*.sh`, sourced lazily
  for Arch commands only; `system/arch/` holds the `/etc` and `/boot` templates
  (the one place that keeps a `.dotfiles-backup`).
- `home/` — shared configs; stow skips the Ghostty forwarding alias, skills,
  and the retired Pi workspace. `config/retired-home-links.txt` lists obsolete
  stow links to remove, only when they resolve into this checkout. Local files
  and foreign symlinks are preserved.
- `home-fedora/` — Fedora's standalone Ghostty configuration. Hyprland input
  has been retired; Arch's compositor-owned configuration is unchanged.
- `home-arch/` — Arch desktop overlay, stowed on Arch only, except the two
  compositor-owned user files (`hypr-user.lua`, `hypr-vars.lua`), which
  deploy once as real files you may edit freely.
- `doctor` asserts every tree against its selected source (overlay links plus
  deployed user files). All three trees are
  yours to edit; the generated `~/.config/hypr/` tree is upstream output, not
  a source.
- Elevation is terminal sudo only (asked once, refreshed for the run). Fish
  becomes the login shell via `usermod -s`; it takes effect at next login.

## Verify and repair

Re-running `init`, `update`, or `arch-setup` is the supported repair path —
everything is idempotent. Useful landmarks:

- `./dot doctor` — user-space truth (helpers, bundle, plugins, links, shell).
- `./dot arch-check` — Arch system truth, read-only.
- Mullvad daemon complaints name their fix: `./dot arch-setup --only system`.
- Login-shell change lands at next login; NVIDIA module needs minutes plus a reboot.
