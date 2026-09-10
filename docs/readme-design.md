# README design record

Synthesis of 36 distinct READMEs inspected 2026-09-10 against the live
`matiassingers/awesome-readme` `## Examples` showcase (catalogue HEAD
`2336159eff5d`), 12 per researcher across cohorts 0/1/2 mod 3. Zero exact
`owner/repo` overlaps between cohorts (nearest pairs are same-owner,
different repos). Working notes consolidated below; scratch files removed.

## Source table (pattern observed → adopted / rejected)

| # | Project | Useful lesson | Rejected |
|---|---|---|---|
| 1 | [Abblix/Oidc.Server](https://github.com/Abblix/Oidc.Server#readme) | bold positioning sentence + TOC on first screen | 16-badge wall (no CI here to badge) |
| 2 | [alichtman/shallow-backup](https://github.com/alichtman/shallow-backup#readme) | `> Warning` rhythm + output-tree layout | full `--help` dump inline |
| 3 | [amplication/amplication](https://github.com/amplication/amplication#readme) | dual-SVG light/dark identity mechanism | avatar-wall / feature-grid bulk |
| 4 | [aregtech/areg-sdk](https://github.com/aregtech/areg-sdk#readme) | Best-for / Not-for scope box | 657-line length without such discipline |
| 5 | [aurumz-rgb/ReviewAid](https://github.com/aurumz-rgb/ReviewAid#readme) | `<details>` bloat valve + comparison table | third-party logo strip |
| 6 | [choojs/choo](https://github.com/choojs/choo#readme) | above-fold nav menu, one line | emoji-as-identity density |
| 7 | [create-go-app/cli](https://github.com/create-go-app/cli#readme) | per-command invocation + option table | donate / sibling-project banners |
| 8 | [dmunish/notecharts](https://github.com/dmunish/notecharts#readme) | honest-competitor paragraph + code ladder | gradient-wordmark banner |
| 9 | [dowjones/react-dropdown-tree-select](https://github.com/dowjones/react-dropdown-tree-select#readme) | FAQ shape only | 40-anchor TOC; the manual inline (cautionary) |
| 10 | [EduardaSRBastos/my-essential-toolbox](https://github.com/EduardaSRBastos/my-essential-toolbox#readme) | single framed visual + breathing room | `plastic` shields, repo-size badge |
| 11 | [eylon-44/Buzz-OS](https://github.com/eylon-44/Buzz-OS#readme) | right-floated small visual geometry | borrowed-mascot artwork |
| 12 | [github-changelog-generator](https://github.com/github-changelog-generator/github-changelog-generator#readme) | exact-error-string honesty | badges-before-title |
| 13 | [ai/size-limit](https://github.com/ai/size-limit#readme) | one-sentence job + "fails when" | plugin-catalog depth |
| 14 | [alichtman/stronghold](https://github.com/alichtman/stronghold#readme) | "what it changes, and why" lines | apologetic-style warnings |
| 15 | [ankitwasankar/mftool-java](https://github.com/ankitwasankar/mftool-java#readme) | `•` nav + dual copy-paste blocks | badge strip |
| 16 | [brenocq/implot3d](https://github.com/brenocq/implot3d#readme) | honest-limits FAQ | image grid (no GUI here to show) |
| 17 | [chroline/well_app](https://github.com/chroline/well_app#readme) | per-platform get-it block first | badge-buttons for nav |
| 18 | [Day8/re-frame](https://github.com/Day8/re-frame#readme) | epigraph-grade line, near-zero badges | essay length |
| 19 | [dmunish/reach](https://github.com/dmunish/reach#readme) | problem → pipeline → checklist rhythm | banner + per-header icon HTML |
| 20 | [dsplce-co/supabase-plus](https://github.com/dsplce-co/supabase-plus#readme) | per-distro install; one funny-true line | six managers on the top screen |
| 21 | [electrikhq/slate](https://github.com/electrikhq/slate#readme) | "you have / you run" table + "not this repo if" | gallery |
| 22 | [feberts/python-game-server](https://github.com/feberts/python-game-server#readme) | 2-step quickstart + link-out depth | — (non-bloat reference) |
| 23 | [gitpoint/git-point](https://github.com/gitpoint/git-point#readme) | install-as-buttons → distro table | buried badges, giant screenshots |
| 24 | [GyulyVGC/sniffnet](https://github.com/GyulyVGC/sniffnet#readme) | 2-line pitch + OS table | sponsor / social-icon bulk |
| 25 | [aimeos/aimeos-typo3](https://github.com/aimeos/aimeos-typo3#readme) | preconditions above the first fence | stacked multi-path installs |
| 26 | [electron-markdownify](https://github.com/amitmerchant1990/electron-markdownify#readme) | 5-link nav + 4-step copy-paste | caveat placed after install |
| 27 | [AntonioFalcaoJr/EventualShop](https://github.com/AntonioFalcaoJr/EventualShop#readme) | captioned figure + collapsed depth | badge-matrix header |
| 28 | [athityakumar/colorls](https://github.com/athityakumar/colorls#readme) | per-verb transcript, inline caveats | every-flag TOC entries |
| 29 | [CCOSTAN/Home-AssistantConfig](https://github.com/CCOSTAN/Home-AssistantConfig#readme) | is / isn't block above commands | warning rendered below showcase |
| 30 | [Invisible-Driver](https://github.com/CoffeeIsAllYouNeed/Invisible-Driver#readme) | compact TOC-table nav form | backgrounders before navigation |
| 31 | [dbt-labs/dbt-core](https://github.com/dbt-labs/dbt-core#readme) | line-1 distro callout; 2-bullet start | 750px hero |
| 32 | [doomemacs/doomemacs](https://github.com/doomemacs/doomemacs#readme) | one-line nav; install + "run when" rows | uncapped screenshot |
| 33 | [dutrevis/spark-resources-metrics-plugin](https://github.com/dutrevis/spark-resources-metrics-plugin#readme) | user/dev split; Mermaid over PNG | badges inside tables |
| 34 | [emalderson/ThePhish](https://github.com/emalderson/ThePhish#readme) | numbered data-flow; fast vs scratch paths | 508-line front-page manual |
| 35 | [FileShot/FileShotZKE](https://github.com/FileShot/FileShotZKE#readme) | zero-badge lede; ≤3-column tables | front-page scope creep |
| 36 | [gofiber/fiber](https://github.com/gofiber/fiber#readme) | min-version first; Philosophy/Limits | sponsors between tagline and install |

## Content constraints (from the pre-synthesis audit)

Must survive in README-or-linked-docs: no-backup warning before any command;
Arch vs Fedora scope plus atomic exclusion; incumbent-DM refusal; Limine
append-only; `--only` filters steps, never bundle/stow; Git-identity and
monitor-layout pointers; idempotent-repair framing; Mulroy attribution.
Never promise: backups, cross-distro verbs, atomic support, MEGA on Fedora,
fake badges/metrics, eternal upstream behavior, or agent-coordination rules
as user restrictions.

## Design decisions

1. **Compact editorial field-guide with two distro doors** — scope table plus
   per-distro setup fences up front (slate/sniffnet/dbt/doom), not a banner or
   showcase. The only choice a reader makes is which table row they are.
2. **Small original dual-mode hero, imported** — concept-B masthead
   (tagline "Shared tools. Separate desktops.") as
   `docs/img/dotfiles-hero-{light,dark}.svg`, swapped via the
   GitHub-supported `prefers-color-scheme` `picture` pattern inside a
   centered `h1`. Zero badges, zero screenshots.
3. **Progressive disclosure** — homepage (scope, safety, quickstart, commands,
   customize) → `docs/usage.md` (operator reference) → `docs/arch-coverage.md`
   and bundle comments (history/rationale). Verb matrix, fingerprint, step
   internals, and alias mechanics live one click down, never inline.
4. **Safety rides with the command** — CAUTION (no-backup + Git identity) before
   the first fence; DM/Limine contracts beside `arch-setup`
   (shallow-backup/changelog-generator honesty); `--only`, NVIDIA scoping, and
   the fresh-host `arch-check` preview (which lives in the guide, not the
   paste block) stated where used.
5. **Dry-operator voice, one quiet line** — 2-line pitch naming the repo,
   5-anchor nav, tables with "run it when" clauses; the single aside is
   "Re-running it is the repair path." No brochure energy.
