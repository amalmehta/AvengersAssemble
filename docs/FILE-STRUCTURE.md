# File Structure

```
SuiteOfAgents/
├── README.md                    What it is, with pictures and links
├── SuiteOfAgents.md             The project brief, decisions and changelog
├── docs/
│   ├── INSTRUCTIONS.md          Setup, run, use, test
│   ├── SYSTEM-DESIGN.md         Architecture, flows, protocol, data, trade-offs, limits
│   ├── FILE-STRUCTURE.md        This file
│   └── images/                  App screenshots (light/dark) and the bandit learning chart
├── scripts/
│   ├── build-app.sh             Builds "build/Suite of Agents.app" with the engine bundled inside
│   └── bandit_chart.py          Simulates offline runs and draws the learning chart
├── engine/                      Python engine: the `suite` command
│   ├── pyproject.toml, uv.lock
│   ├── src/suite/
│   │   ├── cli.py               Commands and --json output (the app's interface)
│   │   ├── orchestrator.py      One run: plan → route → work → judge → review → report
│   │   ├── bandit.py            Thompson-sampling routing and variant bandits
│   │   ├── providers.py         Claude API provider and the offline mock
│   │   ├── tools.py             Workspace file tools and sandboxed Python
│   │   ├── store.py             SQLite runs and tasks (the reward log)
│   │   ├── config.py            Settings, task kinds, model variants, prices, data folder
│   │   └── agents/              Default agent roster (one YAML per agent) and its loader
│   └── tests/
│       ├── test_suite.py        Bandits, tools, sandbox, orchestration, CLI, cancel
│       └── test_anthropic_provider.py   Real provider against a fake HTTP transport
└── app/                         SwiftUI Mac app (Swift package)
    ├── Package.swift
    ├── Sources/SuiteCore/       Testable logic
    │   ├── Models.swift         Decoding of engine JSON, display names, icons
    │   ├── Events.swift         Run events and the incremental JSON-lines buffer
    │   ├── EngineRunner.swift   Finds uv and the engine, runs and cancels commands
    │   ├── Palette.swift        Kind colours: hue families, light and dark
    │   ├── Storage.swift        Data folder, settings.json, feedback, Keychain
    │   └── DemoData.swift       Sample data for screenshots
    ├── Sources/SuiteOfAgents/   The app
    │   ├── App.swift            Entry point, window, Settings scene (⌘,)
    │   ├── AppModel.swift       App state and engine calls
    │   ├── MainView.swift       Sidebar, drop-anywhere, ⌘V paste, feedback tab
    │   ├── NewRunView.swift     Goal, attachments, Upload, Start
    │   ├── RunView.swift        Live tasks, ratings, detail, budget, report
    │   ├── TeamView.swift       Agent cards
    │   ├── BanditView.swift     Routing heatmap and model chart
    │   ├── SettingsView.swift   Every preference in one place
    │   ├── MarkdownView.swift   Report rendering
    │   ├── Components.swift     Shared views (tags, chips, bars)
    │   └── Screenshots.swift    --screenshots mode
    └── Tests/SuiteCoreTests/    Decoding, palette, settings, engine integration
```

Data created at run time is not in the repo. It lives in `~/Library/Application Support/Suite of Agents/` (see [SYSTEM-DESIGN.md](SYSTEM-DESIGN.md#where-data-lives)).
