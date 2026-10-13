"""Simulate offline mock runs and chart how the bandits learn (README figure).

    uv run --project engine python scripts/bandit_chart.py

The mock judge rewards the best agent for each task: usually the kind's specialist, but some task
wording ("battery", "pricing", "gripper"...) calls for a different expert. Each line is the mean
of several independent simulations, so differences reflect the method rather than one lucky seed.
"""
import random
import sys
import tempfile
from multiprocessing import Pool
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from suite.config import DEFAULT_SETTINGS
from suite.orchestrator import Orchestrator
from suite.providers import MockProvider, best_agent
from suite.similarity import task_text

GOALS = [
    "Launch a company selling a home robot that folds laundry",
    "Build an AI app that plans meals from a fridge photo",
    "Start a drone delivery company for rural pharmacies",
    "Create a SaaS platform for pricing optimization",
    "Build a solar battery device for camping",
]
RUNS = 60
REPS = 4
WINDOW = 8
CONFIGS = [  # (label, skill priors, text weight)
    ("Kind + task wording (default)", True, 0.5),
    ("Kind only", True, 0.0),
    ("Kind only, flat priors", False, 0.0),
]
THEMES = {
    "light": {"surface": "#fcfcfb", "ink": "#0b0b0a", "muted": "#6b6a64", "grid": "#e6e5df",
              "series": ["#2a78d6", "#eb6834", "#1baf7a"]},
    "dark": {"surface": "#1a1a19", "ink": "#ffffff", "muted": "#a3a29a", "grid": "#33332f",
             "series": ["#3987e5", "#d95926", "#199e70"]},
}


def simulate(job) -> list[float]:
    """Share of each run's tasks routed to the best agent for that task."""
    skill_priors, text_weight, rep = job
    home = Path(tempfile.mkdtemp())
    share = []
    for i in range(RUNS):
        # One task at a time keeps each simulation deterministic.
        orch = Orchestrator(MockProvider(seed=1000 * rep + i), lambda e: None, suite_home=home,
                            settings={**DEFAULT_SETTINGS, "max_parallel_tasks": 1, "text_weight": text_weight},
                            rng=random.Random(7919 * rep + i), skill_priors=skill_priors)
        run_id = orch.run(GOALS[i % len(GOALS)])
        tasks = [t for t in orch.store.tasks(run_id) if t["judge_score"] is not None]
        share.append(sum(t["agent"] == best_agent(t["kind"], task_text(t), orch.agents) for t in tasks) / len(tasks))
    return share


def smooth(xs, k=WINDOW):
    return [sum(xs[max(0, i - k + 1):i + 1]) / len(xs[max(0, i - k + 1):i + 1]) for i in range(len(xs))]


def draw(lines, mode, out):
    c = THEMES[mode]
    fig, ax = plt.subplots(figsize=(8, 3.6), dpi=200)
    fig.patch.set_facecolor(c["surface"]); ax.set_facecolor(c["surface"])
    x = list(range(1, RUNS + 1))
    for (label, ys), color in zip(lines, c["series"]):
        ys = smooth(ys)
        ax.plot(x, ys, color=color, lw=2, label=label)
        ax.annotate(label.split(" (")[0], (x[-1], ys[-1]), xytext=(8, 0), textcoords="offset points",
                    va="center", color=c["ink"], fontsize=8)
    ax.set_ylim(0, 1); ax.set_xlim(0.5, RUNS + 0.5)
    ax.set_xlabel(f"Run number (offline mock, mean of {REPS} simulations, {WINDOW}-run rolling mean)",
                  color=c["muted"], fontsize=8)
    ax.set_title("Share of tasks routed to the best agent", color=c["ink"], fontsize=11, loc="left", pad=26)
    ax.yaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(1.0))
    ax.grid(axis="y", color=c["grid"], lw=0.6); ax.set_axisbelow(True)
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.spines["bottom"].set_color(c["grid"])
    ax.tick_params(colors=c["muted"], labelsize=8, length=0)
    leg = ax.legend(loc="lower left", bbox_to_anchor=(0, 1.0), frameon=False, fontsize=8, ncols=3, borderaxespad=0.2)
    for t in leg.get_texts():
        t.set_color(c["ink"])
    fig.subplots_adjust(right=0.78, left=0.07, bottom=0.16, top=0.82)
    fig.savefig(out, facecolor=c["surface"])


if __name__ == "__main__":
    out_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/images")
    jobs = [(priors, tw, rep) for _, priors, tw in CONFIGS for rep in range(1, REPS + 1)]
    with Pool() as pool:
        results = pool.map(simulate, jobs)
    lines = []
    for n, (label, _, _) in enumerate(CONFIGS):
        reps = results[n * REPS:(n + 1) * REPS]
        lines.append((label, [sum(r[i] for r in reps) / REPS for i in range(RUNS)]))
    for mode in THEMES:
        draw(lines, mode, out_dir / f"bandit-learning-{mode}.png")
    for label, ys in lines:
        print(f"{label}: runs 1–10 {sum(ys[:10]) / 10:.0%} → runs 41–60 {sum(ys[40:]) / 20:.0%}")
