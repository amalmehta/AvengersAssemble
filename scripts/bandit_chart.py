"""Simulate offline mock runs and chart how the bandits learn (README figure).

    uv run --project engine python scripts/bandit_chart.py
"""
import random
import sys
import tempfile
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from suite.config import DEFAULT_SETTINGS
from suite.orchestrator import Orchestrator
from suite.providers import MockProvider

GOALS = [
    "Launch a company selling a home robot that folds laundry",
    "Build an AI app that plans meals from a fridge photo",
    "Start a drone delivery company for rural pharmacies",
    "Create a SaaS platform for pricing optimization",
    "Build a solar battery device for camping",
]
RUNS = 60
WINDOW = 8
THEMES = {
    "light": {"surface": "#fcfcfb", "ink": "#0b0b0a", "muted": "#6b6a64", "grid": "#e6e5df",
              "s1": "#2a78d6", "s2": "#eb6834"},
    "dark": {"surface": "#1a1a19", "ink": "#ffffff", "muted": "#a3a29a", "grid": "#33332f",
             "s1": "#3987e5", "s2": "#d95926"},
}


def simulate(skill_priors: bool) -> list[float]:
    """Share of each run's tasks routed to the agent whose primary skill is the task's kind."""
    home = Path(tempfile.mkdtemp())
    share = []
    for i in range(RUNS):
        orch = Orchestrator(MockProvider(seed=i), lambda e: None, settings=dict(DEFAULT_SETTINGS), suite_home=home,
                            rng=random.Random(100 + i), skill_priors=skill_priors)
        run_id = orch.run(GOALS[i % len(GOALS)])
        tasks = [t for t in orch.store.tasks(run_id) if t["judge_score"] is not None]
        share.append(sum(orch.agents[t["agent"]]["skills"][0] == t["kind"] for t in tasks) / len(tasks))
    return share


def smooth(xs, k=WINDOW):
    return [sum(xs[max(0, i - k + 1):i + 1]) / len(xs[max(0, i - k + 1):i + 1]) for i in range(len(xs))]


def draw(with_priors, flat, mode, out):
    c = THEMES[mode]
    fig, ax = plt.subplots(figsize=(8, 3.6), dpi=200)
    fig.patch.set_facecolor(c["surface"]); ax.set_facecolor(c["surface"])
    x = list(range(1, RUNS + 1))
    for ys, color, label in [(smooth(with_priors), c["s1"], "With skill priors"),
                             (smooth(flat), c["s2"], "Flat priors (learning only)")]:
        ax.plot(x, ys, color=color, lw=2, label=label)
        ax.annotate(label, (x[-1], ys[-1]), xytext=(8, 0), textcoords="offset points", va="center",
                    color=c["ink"], fontsize=8)
    ax.set_ylim(0, 1); ax.set_xlim(0.5, RUNS + 0.5)
    ax.set_xlabel(f"Run number (offline mock, {WINDOW}-run rolling mean)", color=c["muted"], fontsize=8)
    ax.set_title("Share of tasks routed to the right specialist", color=c["ink"], fontsize=11, loc="left", pad=26)
    ax.yaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(1.0))
    ax.grid(axis="y", color=c["grid"], lw=0.6); ax.set_axisbelow(True)
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.spines["bottom"].set_color(c["grid"])
    ax.tick_params(colors=c["muted"], labelsize=8, length=0)
    leg = ax.legend(loc="lower left", bbox_to_anchor=(0, 1.0), frameon=False, fontsize=8, ncols=2, borderaxespad=0.2)
    for t in leg.get_texts():
        t.set_color(c["ink"])
    fig.subplots_adjust(right=0.74, left=0.07, bottom=0.16, top=0.82)
    fig.savefig(out, facecolor=c["surface"])


if __name__ == "__main__":
    out_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/images")
    with_priors, flat = simulate(True), simulate(False)
    for mode in THEMES:
        draw(with_priors, flat, mode, out_dir / f"bandit-learning-{mode}.png")
    for name, ys in [("skill priors", with_priors), ("flat priors", flat)]:
        print(f"{name}: first {WINDOW} runs {sum(ys[:WINDOW]) / WINDOW:.0%} → last {WINDOW} {sum(ys[-WINDOW:]) / WINDOW:.0%}")
