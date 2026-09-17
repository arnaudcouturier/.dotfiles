# Spotify theming via Spicetify + Noctalia (manual, not provisioned)

Deliberately manual: the Arch bundle notes "no spicetify theming", the
Fedora plan keeps application re-theming out of desktop provisioning, and
Noctalia's template engine owns the generated `color.ini`, so stow must not
manage anything under `~/.config/spicetify/`. Spicetify itself is installed
by hand per the [Spicetify docs](https://spicetify.app/docs/getting-started);
no bundle entry installs it.

## Prerequisites

- Spotify installed (Fedora: `com.spotify.Client` Flatpak from the bundle).
- Spicetify working (`spicetify backup` has run once; live backup lives at
  `~/.local/state/spicetify/Backup`).
- The [Colorful](https://github.com/sanoojes/spicetify-colorful) theme's
  `user.css` present at `~/.config/spicetify/Themes/Colorful/user.css`
  (Colorful is only `color.ini` + `user.css`; the Noctalia template generates
  just the `color.ini`).
- Noctalia's community `spicetify` template enabled, so palette changes
  regenerate `Themes/Colorful/color.ini` (`[noctalia]` scheme) and
  `Themes/Comfy/color.ini`.

## Failure mode (seen 2026-09-17)

Spotify looked stock even though Noctalia had generated both `color.ini`
files. Causes, all three at once:

1. `Themes/Colorful/` contained only the generated `color.ini` — the base
   theme's `user.css` was never installed, so there was no CSS to inject.
2. Spicetify was still configured for the empty placeholder theme:
   `current_theme = marketplace`, `color_scheme` empty
   (`~/.config/spicetify/config-xpui.ini`).
3. The last `spicetify apply` therefore patched the default look over the
   generated colors.

## Fix

```sh
# 1. Complete the base theme without touching the generated colors.
curl -sL "https://cdn.jsdelivr.net/gh/sanoojes/spicetify-colorful@main/src/user.css" \
  -o ~/.config/spicetify/Themes/Colorful/user.css

# 2. Select the Noctalia-generated scheme.
spicetify config current_theme Colorful color_scheme noctalia \
  inject_css 1 replace_colors 1 overwrite_assets 1 inject_theme_js 1

# 3. Patch and restart (Spotify Flatpak must reload the patched files).
spicetify apply
flatpak kill com.spotify.Client
flatpak run com.spotify.Client &
```

If Spotify is already open and you only changed colors, `Ctrl+Shift+R`
inside Spotify hot-reloads instead of a restart.

## Verify

- `spicetify config` shows `current_theme = Colorful`,
  `color_scheme = noctalia`.
- The patched `.../spotify/Apps/xpui/spicetify-config.json` reads
  `"theme_name": "Colorful", "scheme_name": "noctalia"`.
- Sidebar/player use the Noctalia palette instead of stock black.

## Maintenance

Noctalia's template `post_hook` runs `spicetify -q apply --no-restart` on
every palette change, so a new palette patches the files but a running
client still needs `Ctrl+Shift+R` or a restart to show it.
