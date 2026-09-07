# Fedora package audit

Where every `packages/fedora.bundle` entry comes from, and what was checked.
Fedora entries are never translated from Arch names — each was confirmed
against a primary source: Fedora's Koji/dist-git, the vendor's own repository
metadata, or the vendor's download manifest. Last verified 2026-09-07.

How to re-check an entry:

- Fedora package exists: `koji.fedoraproject.org/koji/search` (type=package),
  or `packages.fedoraproject.org/pkgs/<dist-git>/<rpm>/`. Rust crates live in
  `rust-*` dist-git repos but usually drop the prefix in the built package.
- Vendor repository content: fetch `repodata/repomd.xml`, then the primary
  metadata, and read the `<name>` entries.
- A standalone RPM's real name: `rpm -q --qf '%{NAME}' -p <URL>` (rpm fetches
  the header over HTTPS).

## Names that differ from Arch, or that surprise

| Entry | Note |
| --- | --- |
| `fd-find` | Arch calls it `fd`; the binary is still `/usr/bin/fd` |
| `gh` | Arch calls it `github-cli` |
| `ShellCheck` | capitalized — `dnf install shellcheck` fails |
| `starship` | Fedora retired `rust-starship`; the COPR `atim/starship` is the route starship's own README gives Fedora users |
| `eza`, `zoxide` | built from the `rust-eza` / `rust-zoxide` dist-git repos |
| `dnf5-plugins` | subpackage of `dnf5`; provides the `config-manager` and `copr` plugins the bundle relies on |
| no `base-devel` | Arch-only meta package; Fedora has no AUR and nothing here builds from source |

## Vendor repositories (`repofile`)

All three ship an official `.repo` file with `gpgcheck=1`, and the package
named in the bundle was confirmed in their primary metadata.

| Vendor | Repo file | repoid | Package |
| --- | --- | --- | --- |
| Tailscale | `pkgs.tailscale.com/stable/fedora/tailscale.repo` | `tailscale-stable` | `tailscale` |
| Mullvad | `repository.mullvad.net/rpm/stable/mullvad.repo` | `mullvad-stable` | `mullvad-vpn` |
| Brave | `brave-browser-rpm-release.s3.brave.com/brave-browser.repo` | `brave-browser` | `brave-origin` |

Brave's own instructions use `dnf-plugins-core` + `config-manager addrepo`;
`dot` does the same through dnf5's built-in `config-manager`, which is what
Fedora 41+ ships. Updates flow through dnf, so nothing is pinned.

## Pinned downloads (`rpm`, `appimage`)

These entries carry an explicit name because the URL does not reveal what gets
installed — verified from each package's own header:

| Entry | File name | Real package |
| --- | --- | --- |
| Keeper | `keeperpasswordmanager-18.6.1-1.x86_64.rpm` | `keeperpasswordmanager` 18.6.1-1.fc37 — note the dist tag: the NVRA in the file name (`-1.x86_64`) is not what `rpm -q` sees |
| Proton Mail | `ProtonMail-desktop-beta.rpm` | `proton-mail` 1.13.4 — the file name has no relation to the package name, and "beta" is the file name, not the channel |

- **Keeper** publishes an RPM repository
  (`download.keepersecurity.com/desktop_electron/Linux/repo/rpm/`) but no
  `.repo` file, so a pinned RPM from that repo beats hand-writing repo config.
  Its metadata carries exactly one build, currently the pinned one.
- **Proton Mail** has no repository. `proton.me/download/mail/linux/version.json`
  is the official manifest; the bundle pins the newest **Stable** entry.
- **Obsidian** ships no RPM. The official AppImage from
  `obsidianmd/obsidian-releases` is the vendor's primary Linux download.
  Watch the tags: a release can carry only the Android APK, so pin the newest
  tag that actually has an `.AppImage` asset. Obsidian's own updater may
  replace the file in place. Arch keeps the packaged `obsidian` instead.

## Flathub and npm

- **Equibop** — `org.equicord.equibop`, manifest maintained by the Equicord
  project. Its GitHub releases also carry RPMs, but Flathub brings updates.
- **pi** (`@earendil-works/pi-coding-agent`) and **Codex** (`@openai/codex`) —
  official npm packages, the only Fedora route either project documents.
  Installed with `--ignore-scripts`, pi's documented supply-chain posture.

## Installed by `dot` itself

**Claude Code** (Fedora) — npm installs are deprecated upstream, so
`claude.ai/install.sh` is the supported route; Arch uses the `claude-code`
package. **herdr** — its own installer, on both distros.

## Open

**ChatGPT desktop** — OpenAI ships Linux as a `.deb` only
(`persistent.oaistatic.com/codex-app-prod/linux/deb`; the `rpm` path 404s) and
Flathub carries only unofficial clients. No verified Fedora route; use the web
app. Arch uses the AUR `chatgpt-desktop`, which repacks that same `.deb`.

## Rejected

- **Deriving an RPM's package name from its URL** — broken for both entries
  above (dist tag, unrelated file name), which is why the bundle records the
  name.
- **Obsidian from Flathub** (`md.obsidian.Obsidian`) — community-packaged; the
  official AppImage was preferred.
- **Brave from GitHub release assets** — superseded by the vendor repository,
  which brings updates.
- **starship via `starship.rs/install.sh`** — installs outside dnf, breaking
  `rpm -q` checks and updates.
- **A hand-written Keeper `.repo` file** — GPG-less repo config in `dot` is
  worse than a pinned official RPM.
- **Converting OpenAI's `.deb` to RPM** — repackaging is exactly what this
  repo avoids: not deterministic, not auditable.
