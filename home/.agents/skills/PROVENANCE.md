# Vendored skills

Copied from https://github.com/mattpocock/skills at commit 6654f6b (2026-09-01),
MIT license. This is the curated set shipped by the upstream Claude Code
plugin (plugin.json): 18 engineering and 7 productivity skills, flattened
from the upstream skills/engineering/ and skills/productivity/ categories.
The upstream in-progress/ and misc/ skills are intentionally excluded.

Refresh by re-copying from a newer upstream checkout and updating this note.

## dmmulroy skills (2026-09-06, from https://github.com/dmmulroy/.dotfiles at fd84f52)

Imported whole-skill (overlap skills like code-review/tdd are the same
mattpocock upstream we already vendor newer, so only the missing ones were
copied): bro, computer-use-mcp, herdr, plannotator-tui, recipe-diagrams,
show-me, workday-training, worktrees, write-discoverable-code
(write-discoverable-code is MIT per its frontmatter).

Deliberately excluded: coding-standards (TypeScript/Effect) and
cloudflare-composition-root (Cloudflare Workers) — not our stack.

Caveats: computer-use-mcp assumes macOS Helium (`net.imput.helium`) and an
`open-computer-use` MCP server; plannotator-tui needs the `plannotator-tui`
binary (his personal tap, no Arch package); workday-training needs
global `agent-browser` + authenticated Chromium; recipe-diagrams needs
Python 3 + ImageMagick. All are inert markdown until invoked.
