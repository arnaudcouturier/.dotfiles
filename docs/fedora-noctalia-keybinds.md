# Fedora keybind decision: vanilla Umbriel

Status: planning only; no configuration deployed.
Updated: 2026-09-16.

## Final user direction

Use the most vanilla packaged Umbriel experience possible. This replaces all earlier custom keybind proposals, including the three previously approved familiar overrides.

Only two things need to be obvious:

- **Super+Enter opens the terminal.** The inspected upstream packaged example binds `Mod+Return` to `spawn:kitty`. Install the verified Fedora Kitty package and retain that default. Ghostty may remain available independently; do not override the terminal binding just to preserve old habits.
- **Super+K opens Umbriel's native cheatsheet**, using `cheatsheet-toggle`. No Fuzzel menu, generated shortcut list, plugin or helper script.

All other compositor bindings, scrolling behavior, workspace behavior, gestures and shipped defaults remain vanilla. In particular, Super+T remains floating and Super+L remains focus-right. Super+K necessarily replaces the default Vim-style focus-up shortcut; Super+Up remains available.

## Minimal implementation strategy

Start from the **installed package's default configuration**, not the prior Hyprland inventory or our previous curated shortlist. Preserve its defaults and add only the required Noctalia startup integration and cheatsheet override.

Where the selected package supports the documented include behavior, a small repository-managed entrypoint can include `/usr/share/umbriel/config.toml` and override just:

```toml
[keybinds]
"Mod+K" = { action = "cheatsheet-toggle", repeat = false }
```

This excerpt is the sole personal keybinding change, not a complete standalone configuration. Verify the package's installed config path and include/override behavior before implementing. Do not include the user entrypoint itself recursively. Do not copy the whole default map into a separately maintained personal map unless packaging makes inclusion unsuitable.

Use `Mod` consistently with the upstream example. In a native DRM session it defaults to Super. Do not add a competing literal `Super+K` beside upstream `Mod+K`.

Noctalia must still start once and session/login/portal integration must work. These are requirements for the requested Noctalia-family desktop, not permission to add custom shortcuts, app-specific rules or Hyprland behavior emulation. Hardware-specific necessities remain separate validation decisions.

## What is no longer planned

- No Super+T terminal override or Super+L lock override.
- No custom floating relocation, navigation aliases, resizing shortcuts or app/media shortcut bank.
- No custom scratchpad scheme, opacity toggle, PiP/normalization helper or shell restart shortcuts.
- No removal of packaged scratchpad bindings merely because the earlier shortlist omitted them.
- No blanket rewrite of default repeat policies, workspace numbering or gestures.
- No custom cheatsheet implementation.

Use Noctalia's normal UI and whatever integration bindings ship in the chosen Umbriel default configuration. Add further personal bindings only if explicitly requested later.

## Evidence and acceptance

Inspected upstream snapshot: `32cc131278cd296b70c41a8e5e1460a98df6a26e`.

- [Packaged example](https://github.com/noctalia-dev/umbriel/blob/32cc131278cd296b70c41a8e5e1460a98df6a26e/examples/config.toml): `Mod+Return = spawn:kitty`, modifier-only Noctalia launcher, native layout bindings.
- [Keybind documentation](https://docs.noctalia.dev/umbriel/keybinds/#cheatsheet): native `cheatsheet-toggle`, `cheatsheet-open`, `cheatsheet-close`; lists active bindings.
- [Configuration documentation](https://docs.noctalia.dev/umbriel/configuration/): includes, including-file precedence, configuration lookup and validation.
- [Config source](https://github.com/noctalia-dev/umbriel/blob/32cc131278cd296b70c41a8e5e1460a98df6a26e/src/config/config.cpp): seeds built-in bindings, then merges configured chords. The packaged example's comment claiming the complete set is replaced conflicts with this implementation; verify installed behavior rather than relying on that comment.

Before cutover:

1. Inspect the actual Fedora package defaults. Confirm terminal command, config path and native cheatsheet action; report any change instead of silently relying on this moving snapshot.
2. Verify the Fedora terminal package provides the default executable.
3. Validate the small entrypoint with the installed Umbriel validator.
4. Test Super+Enter opens one usable terminal and Super+K opens the native active-bindings overlay without repeated toggling while held.
5. Confirm Super+Up still focuses upward, Super+T floats, and Super+L focuses right.
6. Confirm the final map differs from the packaged defaults only at Mod+K; no unintended duplicate effective binding remains.
7. Test on both keyboard layouts and both target machines. No runtime validation has yet been performed.

The migration plan's historical parity matrix is reference material only. **This document is the keybind implementation decision.**
