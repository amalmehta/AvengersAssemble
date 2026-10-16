# Instructions

## Requirements

- macOS 14 or later
- [uv](https://docs.astral.sh/uv/), which runs the Python engine and installs Python 3.12 for it:
  ```bash
  curl -LsSf https://astral.sh/uv/install.sh | sh
  ```
- Xcode or the Command Line Tools (Swift 5.9+), only to build the app
- An Anthropic API key for real runs. Without one, everything runs on the offline mock: no API calls, no cost.

## Download the Mac app

Get it from the [website](https://amalmehta.github.io/AvengersAssemble/) or the latest [GitHub release](https://github.com/amalmehta/AvengersAssemble/releases/latest). It runs on Apple silicon and Intel Macs.

1. Unzip it and move **Avengers Assemble** to Applications.
2. The app isn't notarized by Apple, so macOS blocks it the first time you open it. Go to **System Settings → Privacy & Security** and click **Open Anyway**.
3. You still need uv (see Requirements).

## Build and open the Mac app

```bash
./scripts/build-app.sh
```

```bash
open "build/Avengers Assemble.app"
```

The first launch takes about 20 seconds while uv sets up the engine's Python environment in the data folder. During development you can skip the bundle: `cd app && swift run SuiteOfAgents`.

## Use it

1. **Settings (⌘,).** Paste your Anthropic API key. It's stored in the macOS Keychain. Set the cost cap per run (default $2), the task cap (default 40), and **Tasks at once** (default 3; independent tasks run side by side). With no key, or with **Use offline mock** on, runs use the mock.
2. **New Run.** Type a goal, e.g. "Launch a company selling a home robot that folds laundry". Give the team files with **Upload…**, by dropping them anywhere on the window, or by pasting with ⌘V. Press **Start**.
   - Agents see **images** (PNG, JPEG, GIF, WebP, HEIC, TIFF, BMP) and **PDFs** as they are: pictures, tables and figures, not just text. A PDF over 20 pages is read 20 pages at a time.
   - **Word, Excel and PowerPoint** files are converted to text and tables. Other text files are read as they are.
   - The CEO plans with a short summary of every file; agents open the full files when their task needs them.
3. Watch the run. The CEO's plan appears, then each task shows which agent and model the bandits picked and **why**: the sampled scores, and the similar past tasks whose results counted. It also shows what tools the agent used, its reviewer score and its cost. The same explanation is kept for past runs. **Cancel** stops the run cleanly and still writes a report.
4. **Rate results.** 👍/👎 on any task overrides the reviewer's score and counts 3× (adjustable in Settings). Ratings change routing from the very next task. **Task wording weight** in Settings (default 0.5) sets how much a task's wording, not just its kind, decides who gets it; 0 routes on kind alone.
5. **Read the report** at the bottom of the run, or click **Open Output** to see a task's files in Finder.
6. **Team** shows every agent. **Open Agents Folder** lets you edit their YAML: prompts, skills, allowed models. Add a file to add an agent.
7. **Bandit** shows what has been learned: who gets which kind of work, and which model each agent does best on.
8. **Feedback** (bottom-right corner) saves a note to `feedback.jsonl` in the data folder.

## Command line

The engine works without the app:

```bash
cd engine && uv run suite run "Start a drone delivery company for rural pharmacies" --mock
```

| Command | What it does |
|---|---|
| `suite run "<goal>" [--input FILE]… [--mock] [--max-cost 2] [--max-tasks 40] [--parallel 3]` | Run a goal (add `--json` for the event stream) |
| `suite runs` | List runs |
| `suite show <run_id>` | Tasks, scores and the report for one run |
| `suite rate <task_id> up\|down\|clear` | Rate a result |
| `suite agents` | The team, and where their YAML files live |
| `suite bandit` | Routing posterior means, by kind and agent |

`ANTHROPIC_API_KEY` must be set for real runs. `SUITE_HOME` changes the data folder (default `~/Library/Application Support/Avengers Assemble/`).

## Test

```bash
cd engine && uv run pytest
```

```bash
cd app && SUITE_ENGINE_DIR="$PWD/../engine" swift test
```

Without `SUITE_ENGINE_DIR`, the three engine integration tests are skipped.

## Regenerate the README images

```bash
"build/Avengers Assemble.app/Contents/MacOS/SuiteOfAgents" --screenshots docs/images
```

```bash
uv run --project engine python scripts/bandit_chart.py
```

## Website and releases

The website is `site/index.html`, a single page that uses the images in `docs/images`. GitHub Pages publishes it on every push to `main` that touches it (`.github/workflows/pages.yml`). To preview it locally:

```bash
./scripts/build-site.sh
```

```bash
python3 -m http.server 8765 --directory build/site
```

To publish a new version of the app, build the universal zip and attach it to a release. The website's Download button always points at the latest release's `AvengersAssemble.zip`.

```bash
./scripts/package-release.sh
```

```bash
gh release create v1.1.0 build/AvengersAssemble.zip --title "Avengers Assemble 1.1" --generate-notes
```

## Change the app icon

The icon is drawn in code, in `app/Sources/SuiteOfAgents/AppIcon.swift`. After editing it, regenerate `app/Resources/AppIcon.icns` and `docs/images/icon.png`, then rebuild the app:

```bash
./scripts/make-icon.sh
```

## Costs

Each run stops at its cost cap. With several tasks running at once, it can go over by up to one API call per running task. List prices per million tokens (input/output): Opus 5.5 $4/$20, Sonnet 5.5 $2/$10, Haiku 4.5 $1/$5. Web search is $10 per 1,000 searches. The CEO plans on Opus, the Reviewer scores on Sonnet, and specialists run on whichever model their variant bandit picks.
