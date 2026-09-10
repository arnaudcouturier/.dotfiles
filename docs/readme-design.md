# README design record

Synthesis of 60 distinct READMEs inspected 2026-09-10 against the live
`matiassingers/awesome-readme` `## Examples` showcase (catalogue HEAD
`2336159eff5d`): 36 originals plus 24 new (12 showcase-visuals, 12 SVG
illustration). Zero exact `owner/repo` overlaps across all three sets
(nearest pair is same-owner, different repos:
`lobehub/sd-webui-lobe-theme` vs `lobehub/lobe-chat`).

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
| 37 | [ArmynC/ArminC-AutoExec](https://github.com/ArmynC/ArminC-AutoExec#readme) | hero-as-action + gradient wordmark in one SVG; captioned `(Preview)` | svgjs bloat, 11-link nav, brochure comparison table |
| 38 | [Grigorij-Dudnik/Clean-Coder-AI](https://github.com/Grigorij-Dudnik/Clean-Coder-AI#readme) | one honest hand-drawn system diagram beats paragraphs | star-begging, broken relative srcs, comparison table |
| 39 | [gui-cs/Terminal.Gui](https://github.com/gui-cs/Terminal.Gui#readme) | left-pitch / right-proof split; real-numbers strip; link-out depth | 15 MB GIF first paint, 11-bullet wall |
| 40 | [Hexworks/zircon](https://github.com/Hexworks/zircon#readme) | fence-then-literal-output pairing per claim | CDN hosting, docs-link sprawl |
| 41 | [htmlhint/HTMLHint](https://github.com/htmlhint/HTMLHint#readme) | split editorial/terminal hero grammar; install split by intent | avatar walls, shields-before-nav |
| 42 | [hywax/mafl](https://github.com/hywax/mafl#readme) | layered flat mark re-tinting light/dark; theme proof as image | emoji wall, triple install inline |
| 43 | [iharsh234/WebApp](https://github.com/iharsh234/WebApp#readme) | per-screen proof under its heading | screenshot-as-title, table lede, return promise |
| 44 | [karan/joe](https://github.com/karan/joe#readme) | per-verb transcript + overwrite/append distinction | borrowed header art, imgur hosting, output dump inline |
| 45 | [L0garithmic/FastColabCopy](https://github.com/L0garithmic/FastColabCopy#readme) | small mark + quantified lede + one full-bleed proof; flags table | stock shields, caveats buried at bottom |
| 46 | [lobehub/sd-webui-lobe-theme](https://github.com/lobehub/sd-webui-lobe-theme#readme) | pill-labeled staged captures; `back-to-top`; `picture` dark/light swap | shield wall, contrib widgets, sponsor PNG |
| 47 | [ma-shamshiri/Pacman-Game](https://github.com/ma-shamshiri/Pacman-Game#readme) | one divider atom for rhythm; per-scenario proof | repeated strips, borrowed character, social shields |
| 48 | [MananTank/radioactive-state](https://github.com/MananTank/radioactive-state#readme) | small mark where the folder is the product; GIF-in-`details` valve | coverage badges, essay length |
| 49 | [yeaight7/awesome-ai-devtools](https://github.com/yeaight7/awesome-ai-devtools#readme) | taxonomy in the art: title left, domain cards right | dark-only, missing `title`/`desc` |
| 50 | [voltagent/voltagent](https://github.com/voltagent/voltagent#readme) | hero sets width; `h3` + nav wayfinding; `picture` light/dark swap | badge cluster, screenshot bulk |
| 51 | [thelounge/thelounge](https://github.com/thelounge/thelounge#readme) | logo-as-`h1` capped 300 px; one capped screenshot; `h1`/`h3`/nav hierarchy | shields between art and choice |
| 52 | [sultan99/react-on-lambda](https://github.com/sultan99/react-on-lambda#readme) | original scene arguing the thesis; small mark + narrative panel | missing `alt`, badge row before thesis |
| 53 | [ryanoasis/nerd-fonts](https://github.com/ryanoasis/nerd-fonts#readme) | split `h1`/`h2` lockup; outlined display type; captioned data diagram | 1.38 MB diagram weight, default diagram title |
| 54 | [release-it/release-it](https://github.com/release-it/release-it#readme) | right-floated demo beside the list; CSS-motion-only; real transcripts only | fake status panels |
| 55 | [Redocly/redoc](https://github.com/Redocly/redoc#readme) | canonical `picture` block; sentence `alt`; hero-as-door | third-party badge dependency |
| 56 | [PostHog/posthog](https://github.com/PostHog/posthog#readme) | operator-at-controls scene capped ~350 px; tables carry detail | shield cluster, oversized source |
| 57 | [lobehub/lobe-chat](https://github.com/lobehub/lobe-chat#readme) | banner-as-link; one `picture` idiom everywhere; fixed brand widths | ~30 shields, contrib wall, stat thumbnails |
| 58 | [httpie/cli](https://github.com/httpie/cli#readme) | single-hue mark; color-is-function per surface; 100 px logo + tagline in `h2` | uncapped full-width animation, badge row |
| 59 | [hmpl-language/hmpl](https://github.com/hmpl-language/hmpl#readme) | 460 px lockup; 100 px ecosystem icon row; dual-`source` `picture` | shield row, tokenized third-party URLs |
| 60 | [gowebly/gowebly](https://github.com/gowebly/gowebly#readme) | two-SVG brand system (mark + banner); outlined type; adaptive chart | share badges, flag links in hero |

## Content constraints (from the pre-synthesis audit)

Must survive in README-or-linked-docs: no-backup warning before any command;
Arch vs Fedora scope plus atomic exclusion; incumbent-DM refusal; Limine
append-only; `--only` filters steps, never bundle/stow; Git-identity and
monitor-layout pointers; idempotent-repair framing; Mulroy attribution.
Never promise: backups, cross-distro verbs, atomic support, MEGA on Fedora,
fake badges/metrics, eternal upstream behavior, or agent-coordination rules
as user restrictions.

## Design decisions

1. **Compact setup with two distro paths** — scope plus
   per-distro setup fences up front (slate/sniffnet/dbt/doom), not a
   showcase. The hero is the only top visual; the supporting figure
   is after setup. The reader selects the Arch or Fedora path.
2. **Original dual-mode hero** — fanned
   config cards plus command ticket plus link twine, warm ink on paper
   (light) / warm paper on ink (dark), as
   `docs/img/dotfiles-hero-{light,dark}.svg`, swapped via the
   GitHub-supported `prefers-color-scheme` `picture` pattern inside a
   centered `h1` with sentence `alt` plus SVG `title`/`desc`. Copy is
   factual: eyebrow `ARCH LINUX · FEDORA`, tagline
   `Arch Linux and Fedora configuration.` Flat fills
   re-tinted light/dark (mafl), system fonts only
   (nerd-fonts/gowebly), capped width readable at 390 px (thelounge/hmpl).
   Zero badges, zero screenshots, zero fake terminal.
3. **One supporting figure after setup, never stacked with the hero** —
   `docs/img/dotfiles-flow-{light,dark}.svg` at Configuration: three stations
   only, edit repo → `./dot stow` → linked `~/` (bundle is not a station).
   Headline `Configuration workflow`. Text and `alt` state the same three
   stations with no fake statuses; the figure replaces the redundant
   source-table and running prose, while the three source-path bullets plus
   monitor/night-light links stay in text. Sentence `alt`, light fallback
   `img`, compositionally identical variants differing only in fills
   (Redocly/lobe/hmpl); staged captures only from real installs
   (lobehub/mafl).
4. **Progressive disclosure** — homepage (scope, safety, quickstart, commands,
   configuration) → `docs/usage.md` (operator reference) → `docs/arch-coverage.md`
   and bundle comments (history/rationale). Verb matrix, fingerprint, step
   internals, and alias mechanics live one click down, never inline.
5. **Safety rides with the command** — CAUTION (no-backup + Git identity) before
   the first fence; DM/Limine contracts beside `arch-setup`
   (shallow-backup/changelog-generator honesty); `--only`, NVIDIA scoping, and
   the fresh-host `arch-check` preview (which lives in the guide, not the
   paste block) stated where used.
6. **Factual voice** — short pitch naming the repo,
   4-anchor nav, tables with a Purpose column; idempotent repair stated once.
   No marketing language.
