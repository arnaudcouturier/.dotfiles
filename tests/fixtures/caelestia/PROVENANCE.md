# Provenance — vendored upstream fixture files

Two files, byte-exact excerpts (126 lines total, sha256 below), taken from
the Caelestia dotfiles upstream for one purpose only: a faithful pristine
deploy in the first-install regression test
(`tests/test-arch-desktop-firstinstall.sh`). The full upstream tree is
deliberately NOT vendored.

- Source: https://github.com/caelestia-dots/caelestia
- Revision: `1ee7a98522b86582b924c5b643b534c13be64180` (checkout used for
  extraction; independent reviewer verified the same revision)
- Extracted: 2026-09-10. Files:
  - `hypr/hyprland.lua` (76 lines) — the generated entry file; carries the
    `require("hyprland.execs")` seam the greeter gate checks.
  - `hypr/hyprland/execs.lua` (50 lines) — carries the night-light block
    the `arch_desktop_night_light_patch` literal applies to at exact
    offsets (`@@ -21,3 +21,5 @@`); the test's strict patch emulation
    asserts these bytes before applying.
- License: the upstream checkout carries no LICENSE file and its README
  names none; these excerpts are used solely as read-only test inputs
  (never executed as code under test beyond parsing by the module's own
  grep/patch pipeline) with source and revision recorded here. If upstream
  adds license terms, mirror them here.
- Integrity:
  - `c7be93202375f7c6453f2b46890522370d20a780e2dce625e4b8e40d05f50c14  hypr/hyprland.lua`
  - `68e0e091d522ba40093896ac27f53c24c8303d21026632b19b23dbbcf4c70e79  hypr/hyprland/execs.lua`
- Freshness rule: if the night-light block drifts upstream, the strict
  emulation fails loudly naming the literal — refresh both the literal and
  these fixtures together, recording the new revision here.
