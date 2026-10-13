# Instructions

## Requirements

- macOS 14 or later
- [uv](https://docs.astral.sh/uv/), which runs the Python engine and installs Python 3.12 for it:
  ```bash
  curl -LsSf https://astral.sh/uv/install.sh | sh
  ```
- Xcode or the Command Line Tools (Swift 5.9+), only to build the app
- An Anthropic API key for real runs. Without one, everything runs on the offline mock: no API calls, no cost.

## Build and open the Mac app

```bash
./scripts/build-app.sh
```

```bash
open "build/Suite of Agents.app"
```

The first launch takes about 20 seconds while uv sets up the engine's Python environment in the data folder. During development you can skip the bundle: `cd app && swift run SuiteOfAgents`.

## Use it

1. **Settings (⌘,).** Paste your Anthropic API key. It's stored in the macOS Keychain. Set the cost cap per run (default $2), the task cap (default 40), and **Tasks at once** (default 3; independent tasks run side by side). With no key, or with **Use offline mock** on, runs use the mock.
2. **New Run.** Type a goal, e.g. "Launch a company selling a home robot that folds laundry". Give the team files with **Upload…**, by dropping them anywhere on the window, or by pasting with ⌘V. Press **Start**.
3. Watch the run. The CEO's plan appears, then each task shows which agent and model the bandits picked (and **why**, from the sampled scores), what tools it used, its reviewer score and its cost. **Cancel** stops the run cleanly and still writes a report.
4. **Rate results.** 👍/👎 on any task overrides the reviewer's score and counts 3× (adjustable in Settings). Ratings change routing from the very next task.
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

`ANTHROPIC_API_KEY` must be set for real runs. `SUITE_HOME` changes the data folder (default `~/Library/Application Support/Suite of Agents/`).

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
"build/Suite of Agents.app/Contents/MacOS/SuiteOfAgents" --screenshots docs/images
```

```bash
uv run --project engine python scripts/bandit_chart.py
```

## Costs

Each run stops at its cost cap. With several tasks running at once, it can go over by up to one API call per running task. List prices per million tokens (input/output): Opus 5.5 $4/$20, Sonnet 5.5 $2/$10, Haiku 4.5 $1/$5. Web search is $10 per 1,000 searches. The CEO plans on Opus, the Reviewer scores on Sonnet, and specialists run on whichever model their variant bandit picks.
