<img src="docs/images/icon.png" width="96" alt="Avengers Assemble app icon: a central node joined to six agents in warm, green and blue">

# Avengers Assemble

**A company made of AI agents: a CEO, a researcher, a marketer, product, software, hardware, robotics, AI, math and physics. Multi-armed bandits learn which agent, on which model, should do each task, from its kind and from what it says.**

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/run-dark.png">
  <img alt="A run: the CEO's plan, which agent and model took each task, reviewer scores, your ratings and the final report" src="docs/images/run-light.png">
</picture>

## How it works

```mermaid
flowchart LR
    G([Your goal + files]) --> CEO[CEO plans tasks]
    CEO --> R{Routing bandit<br/>which agent?<br/>kind + wording}
    R --> V{Variant bandit<br/>which model?}
    V --> A[Agent works<br/>web search · files · sandboxed Python]
    A --> J[Reviewer scores 0–1]
    J --> L[(Rewards)]
    U([Your 👍 / 👎]) --> L
    L -. learns .-> R
    L -. learns .-> V
    J --> C{CEO: done?}
    C -- follow-ups --> R
    C -- yes --> Rep([Report])
```

<table>
<tr>
<td width="50%">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/bandit-dark.png">
  <img alt="What the bandits have learned: who gets which kind of work" src="docs/images/bandit-light.png">
</picture>
</td>
<td width="50%">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/bandit-learning-dark.png">
  <img alt="Share of tasks routed to the best agent over 60 offline runs: routing on task wording reaches 50%, kind-only routing 43%" src="docs/images/bandit-learning-light.png">
</picture>
</td>
</tr>
<tr>
<td>
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/new-run-dark.png">
  <img alt="New run: a goal, attached files, Upload or drop anywhere or paste" src="docs/images/new-run-light.png">
</picture>
</td>
<td>
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/team-dark.png">
  <img alt="The team: every agent, its skills and models" src="docs/images/team-light.png">
</picture>
</td>
</tr>
</table>

## Links

- **[Website](https://amalmehta.github.io/AvengersAssemble/)**: what it is, and the Mac download
- **[Instructions](docs/INSTRUCTIONS.md)**: set up, run and use it (Mac app and command line)
- **[System design](docs/SYSTEM-DESIGN.md)**: architecture, bandit maths, protocol, data, trade-offs, limits
- **[File structure](docs/FILE-STRUCTURE.md)**: what's where
