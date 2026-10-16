PROJECT NAME: AvengersAssemble

META-INSTRUCTIONS:

<Read it all before acting. Ask about anything unclear, contradictory or
 underspecified — before starting and mid-build. Ask in the question widget
 (AskUserQuestion): related questions batched, concrete options, your
 recommendation first. Plain text only if the widget isn't available.>

<Don't expand scope. Anything not listed here is a proposal, including changes
 to this file — propose it, don't do it.>

<Prefer doing over describing: run the code, write the files, test it.>

<Always in scope, no proposal needed: when it goes on GitHub, a README that is
 easy to read at a glance — a line on what it is, then clear visuals
 (screenshots, a diagram or a chart), then links. Everything else goes in
 linked files: docs/INSTRUCTIONS.md (setup, run, use),
 docs/SYSTEM-DESIGN.md (see below) and docs/FILE-STRUCTURE.md (what's where). If what you're
 building is an application rather than a script, also a small unobtrusive feedback tab, and a settings
 button or tab (⌘, on the Mac) that gathers its preferences in one place.>

<If what you're building is an application, build it as a Mac app first; the
 website comes after, as its own step.>

<When an application takes files as input, offer a visible Upload button that
 opens the file picker, accept files dragged anywhere onto the window (not
 only onto a small drop zone), and accept pasting them with ⌘V.>

<Color-code tags, categories and types by similarity: related ones share a
 hue family, with shades far enough apart to tell them apart at a glance, in
 both light and dark mode.>

<Name things the way a person would say them — "Goal Tracker", not
 goal_tracker — for the app, its windows, titles, files people open, repo
 descriptions and README headings. When you create the GitHub repo, name it
 with no "_" or "-": one word or joined words, e.g. GoalTracker.>

<Always in scope: a system design doc in the codebase, docs/SYSTEM-DESIGN.md,
 kept current as the build changes. Cover the architecture (with a Mermaid
 diagram), each component's job, the main flows, where data lives, the key
 design decisions and their trade-offs, how it's tested, and known limits.>

<Finish by listing every deliverable: path, what it is, how to check it works.>

<Git rules (no Claude attribution, never commit .claude/) are in
 ~/.claude/CLAUDE.md and apply on their own — nothing to repeat here.>

<Keep the changelog at the bottom current.>

CONTEXT:

multi-armed bandit system that can do anything together (i..e bukld a new company if you have a ceo agent, researcher, marketer, product, swe, hardware, robotics, ai, math, physics, etc)

DELIVERABLES:

suite of autonomous agents. ask me if you dont know

OPEN QUESTIONS / ASSUMPTIONS:

<Agent fills in: what it guessed, what it decided without asking.>

Asked and answered (2026-10-13):
- Form: Mac app (SwiftUI) driving a Python engine that also works as a CLI.
- Bandits: both layers. A routing bandit picks the agent per task kind; a per-agent variant bandit picks the model.
- Reward: LLM reviewer score (0–1); your 👍/👎 overrides it with weight 3.
- Powers: think, write files, web search, run Python in a sandbox. Nothing is sent, bought or published.
- LLM: Claude API (Opus 5.5 / Sonnet 5.5 / Haiku 4.5) plus an offline mock; API key in the Keychain.
- Roster: everyone from CONTEXT plus a Reviewer, as editable YAML.
- GitHub: public repo AvengersAssemble (created as SuiteOfAgents; renamed 2026-10-14).
- Budget: per-run caps, default $2 and 40 tasks, adjustable in Settings.

Decided without asking:
- Thompson sampling with Beta posteriors over 10 fixed task kinds (strategy, marketing, product, software, hardware, robotics, research, ai, math, physics), colour-grouped into business / engineering / science.
- Informative routing priors from each agent's declared skills; flat priors learned too slowly with 10 agents (measured, see SYSTEM-DESIGN.md).
- Variant reward is reduced by $0.20 per dollar of task cost, so cheaper models win when nearly as good.
- The CEO plans on Opus 5.5 and the Reviewer scores on Sonnet 5.5 (not bandit-routed). Up to 3 plan/review rounds.
- Parallel tasks (added on request after v1): up to 3 independent tasks run at once by default ("Tasks at once" in Settings, `--parallel` on the CLI). Routing stays on one thread.
- Routing on what a task says (added on request): local TF-IDF similarity, applied to both bandits as a kernel over past results (`text_weight` 0.5, "Task wording weight" in Settings). "Why this agent" lists the 3 most similar past tasks, and routing evidence is stored so past runs keep it. Measured in simulation: 50% vs 43% best-agent routing after 60 runs. Tried calibrating the cosine; no measurable gain, so not kept.
- Uploads made readable (added on request): agents open images and PDFs natively, on demand, via read_file (image and document blocks in the tool result). PDFs over 20 pages come back as text, with page ranges to open natively. HEIC → JPEG, TIFF/BMP → PNG, images downscaled to 1568 px. DOCX/XLSX/PPTX → Markdown. The CEO plans from a digest of every file. Parsing uploads is sandboxed: Python parsers in the strict workspace-only sandbox, image decoding only by Apple's sips (which also needs the per-user temp folder). New dependencies: pypdf, python-docx, openpyxl, python-pptx.
- App icon (added on request): a central node (the CEO) joined to six agents in the three kind families' colours on a navy tile, deliberately unlike Marvel's logo. Drawn in SwiftUI on Apple's macOS icon grid, with simplified 16 and 32 px sizes; scripts/make-icon.sh renders the .icns.
- Website (added on request): a static landing page on GitHub Pages (https://amalmehta.github.io/AvengersAssemble/) with a Download button for a universal .app attached to GitHub release v1.0.0. The app isn't notarized (that needs a paid Apple Developer account), so the site explains macOS's one-time Open Anyway step. It doesn't say "open source" because the repo has no license yet, and it states it's not affiliated with Marvel or Disney.
- Opus/Sonnet requests use refusal fallbacks (`fallbacks: "default"`).
- Python runs under macOS sandbox-exec: no network, writes only inside the run's workspace, 60 s limit.
- The website is a later, separate step and was not built.
- Not yet tested against the live API (no key available during the build); covered by a fake-transport test instead.


CHANGELOG:

- 2026-10-13 — created
- 2026-10-14 — added the website (GitHub Pages landing page) and the v1.0.0 release with a universal Mac download
- 2026-10-14 — added the app icon (team assembling around a central node)
- 2026-10-14 — renamed to Avengers Assemble: app, data folder, Keychain entry, GitHub repo and this file (was SuiteOfAgents.md); existing data moves over automatically
- 2026-10-13 — uploads made readable: images and PDFs opened natively by agents; HEIC/TIFF/BMP converted; Word, Excel and PowerPoint converted to text; planning digest of uploads
- 2026-10-13 — routing on what a task says: wording-aware bandits, similar past tasks in "Why this agent", new "Task wording weight" setting
- 2026-10-13 — independent tasks run in parallel (default 3 at once; new setting "Tasks at once" and `--parallel` flag)
- 2026-10-13 — built v1: Mac app + Python engine, layered Thompson-sampling bandits, 10 agents + Reviewer, offline mock, docs, public GitHub repo
- 2026-09-15 — added meta-instruction: built-out applications include a small feedback tab
- 2026-09-15 — added meta-instruction: no "Claude" attribution in commits, PRs, or branches
- 2026-09-16 — added meta-instruction: always include a README when adding to GitHub
- 2026-09-16 — changed meta-instruction: ask clarifying questions in the question widget
- 2026-09-17 — added meta-instructions: Claude never a contributor; never commit .claude/
- 2026-09-26 — compressed the meta-instructions and every field prompt; git rules moved to the global instruction file
- 2026-09-27 — added meta-instruction: applications are built as a Mac app first, then a website
- 2026-09-28 — folded inputs, instructions, constraints, deliverables and done criteria into one free-form CONTEXT
- 2026-09-28 — changed meta-instruction: a README on GitHub always includes a visual
- 2026-09-28 — added meta-instruction: name things like a person would, never snake_case
- 2026-09-28 — changed meta-instruction: README leads with visuals; instructions live in a linked guide
- 2026-09-28 — changed meta-instruction: README is visuals and links; details in docs/INSTRUCTIONS.md and docs/FILE-STRUCTURE.md
- 2026-09-29 — changed meta-instruction: GitHub repo names have no "_" or "-"
- 2026-10-02 — added a DELIVERABLES field after CONTEXT
- 2026-10-02 — added meta-instruction: every project has a system design doc at docs/SYSTEM-DESIGN.md
- 2026-10-05 — added meta-instruction: applications include a settings button or tab
- 2026-10-08 — added meta-instruction: color-code tags by similarity (related share a hue family, each distinct)
- 2026-10-09 — added meta-instruction: apps that take files have an Upload button, drop anywhere, and paste
