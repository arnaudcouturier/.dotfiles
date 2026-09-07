# .pi

Global pi config, synced via dotfiles and stowed into `~/.pi`.

## Extension dependency workspace

Package-style extensions stay in `agent/extensions/` so pi can still
auto-discover them from:

- `~/.pi/agent/extensions/*.ts`
- `~/.pi/agent/extensions/*/index.ts`

This directory is the shared npm workspace root for extensions with their
own `package.json` files.

Install or refresh all extension dependencies from here:

```bash
npm install
```

Run workspace checks:

```bash
npm run check
```

Current workspace-managed extensions:

- `agent/extensions/save-md` — save last answer as Markdown (`/save-md`)
- `agent/extensions/pi-skill-toggle` — skill discovery UI
- `agent/extensions/pi-worktrees` — worktree manager UI

Standalone extensions (no package needed):

- `git-interceptor.ts`, `continue-after-compaction.ts`, `pi-cloak/`

After changing extension code, reload pi with `/reload`.

`agent/settings.json` and `agent/auth.json` are intentionally untracked —
configure provider/model locally.
