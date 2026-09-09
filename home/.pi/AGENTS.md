# PI AGENT WORKSPACE

npm workspace for pi agent extensions. TypeScript, ESM-only. Adapted from
https://github.com/dmmulroy/.dotfiles; only the generic extensions were kept
(nothing Cloudflare- or work-specific).

## STRUCTURE

```
.pi/
├── package.json          # Workspace root: workspaces = save-md, pi-skill-toggle, pi-worktrees
├── tsconfig.json         # Strict, bundler mode, ESNext, noEmit
├── agent/
│   ├── settings.json     # NOT tracked: provider, model, theme — configure locally in ~
│   ├── auth.json         # NOT tracked: never commit credentials
│   ├── mcp.json          # Tracked: local `computer` server (needs `open-computer-use`)
│   ├── cloak.json        # Tracked: secret masking patterns for agent output
│   └── extensions/       # Tracked: local TypeScript extensions
│       ├── save-md/              # /save-md: save last answer as Markdown
│       ├── pi-skill-toggle/      # Skill discovery + toggle UI
│       ├── pi-worktrees/         # Git worktree manager UI (pairs with worktrees skill)
│       ├── pi-cloak/index.ts     # Secret cloaking (reads ../cloak.json)
│       ├── git-interceptor.ts    # Standalone: no hanging editors, no --no-verify
│       └── continue-after-compaction.ts  # Standalone: auto-resume after compaction
```

Skills live in `home/.agents/skills/` (stowed to `~/.agents/skills/`).
Do not copy them here.

## WHERE TO LOOK

| Task | Location |
|------|----------|
| Change default model/provider | `~/.pi/agent/settings.json` (local, untracked) |
| Mask a secret pattern | `home/.pi/agent/cloak.json` |
| Create extension | `home/.pi/agent/extensions/<name>/` with `package.json` |
| Create standalone extension | `home/.pi/agent/extensions/<name>.ts` |
| Create skill | `home/.agents/skills/<name>/SKILL.md` |
| Type-check and test local packages | `npm run check` (from `~/.pi`) |

## CONVENTIONS

- Extensions as npm workspace packages: each has own `package.json`
- Standalone extensions: single `.ts` file in `extensions/`
- Skills: `SKILL.md` entry under `home/.agents/skills/`, optional bundled resources
- ESM only: `"type": "module"` everywhere
- TypeScript strict mode: `noUncheckedIndexedAccess`, `noImplicitOverride`

## ANTI-PATTERNS

- Installing deps at workspace root for extension-specific needs (use per-package)
- Committing `node_modules/` (gitignored) or `auth.json` / `settings.json`
- Editing `~/.pi` directly — edit `home/.pi` in the repo, then `./dot stow`
- Duplicating skills under `agent/skills/` — they belong in `home/.agents/skills/`

## SETUP

```bash
cd ~/.pi
npm install     # workspace deps (typecheck/tests only; pi runs extensions itself)
npm run check   # typecheck + tests
```

After changing extension code, reload pi with `/reload`.
The `computer` MCP server additionally needs the `open-computer-use` binary
for the computer-use-mcp skill; without it that server just stays unavailable.

## KNOWN TEST QUIRK

`pi-worktrees`' service test shells out to
`~/.agents/skills/worktrees/scripts/new-worktree.sh`, so it fails with ENOENT
until `./dot stow` has linked the worktrees skill into `$HOME`. That failure
means "not stowed yet", not "broken extension" — it passes post-stow.
