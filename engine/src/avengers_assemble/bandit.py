"""Two layers of Thompson-sampling bandits.

Routing bandit: for each task kind, which agent should do it?
Variant bandit: for each agent, which model variant should it run on?

Both keep a Beta posterior per arm. Posteriors are rebuilt from the stored rewards
every time, so a later 👍/👎 from the user simply replaces the judge's score.
Rewards are fractional (0..1), so one observation adds w*r to alpha and w*(1-r) to beta.

Contextual routing (text_weight t > 0): when choosing for a new task, every past observation
counts with a kernel weight k instead of all-or-nothing, so tasks that *say* similar things
share evidence even across kinds:
    routing:  k = (1 - t) * [same kind] + t * cos(task text, past task text)
    variants: k = (1 - t) + t * cos(task text, past task text)
With t = 0 this is exactly the kind-only bandit.
"""
from __future__ import annotations

import random
from dataclasses import dataclass

from .similarity import Similarity, task_text

# Prior (alpha, beta) for an agent on a kind, from its declared skills. With ten agents competing,
# a flat Beta(1,1) prior lets the luckiest of nine non-specialist draws win too often.
PRIOR_PRIMARY = (4.0, 1.0)    # the kind is the agent's first-listed skill
PRIOR_SECONDARY = (2.5, 1.0)  # the kind is one of its other skills
PRIOR_NONE = (1.0, 2.0)       # not a declared skill: possible, but must earn it
PRIOR_FLAT = (1.0, 1.0)


@dataclass
class Arm:
    alpha: float = 1.0
    beta: float = 1.0
    n: int = 0

    @property
    def mean(self) -> float:
        return self.alpha / (self.alpha + self.beta)

    def update(self, reward: float, weight: float = 1.0) -> None:
        reward = min(1.0, max(0.0, reward))
        self.alpha += weight * reward
        self.beta += weight * (1.0 - reward)
        self.n += 1


def task_reward(task: dict, user_weight: float) -> tuple[float, float] | None:
    """(reward, weight) for a task: your rating wins over the judge's score."""
    if task.get("user_rating") is not None:
        return float(task["user_rating"]), user_weight
    if task.get("judge_score") is not None:
        return float(task["judge_score"]), 1.0
    return None


@dataclass
class Observation:
    task: dict
    reward: float  # routing reward
    paid: float    # variant reward, after the cost penalty
    weight: float
    vector: dict[str, float]


class Bandits:
    def __init__(self, agents: list[dict], rng: random.Random | None = None, skill_priors: bool = True,
                 text_weight: float = 0.0):
        """agents: dicts with id, skills, variants, routable."""
        self.rng = rng or random.Random()
        self.skill_priors = skill_priors
        self.text_weight = min(1.0, max(0.0, text_weight))
        self.agents = {a["id"]: a for a in agents}
        self.routing: dict[tuple[str, str], Arm] = {}   # kind-only posteriors (the Bandit view)
        self.variants: dict[tuple[str, str], Arm] = {}
        self.observations: list[Observation] = []
        self.sim = Similarity([])

    def _prior(self, kind: str, agent_id: str) -> tuple[float, float]:
        skills = self.agents.get(agent_id, {}).get("skills", [])
        if not self.skill_priors:
            return PRIOR_FLAT
        if skills and skills[0] == kind:
            return PRIOR_PRIMARY
        if kind in skills:
            return PRIOR_SECONDARY
        return PRIOR_NONE

    def _routing_arm(self, kind: str, agent_id: str) -> Arm:
        key = (kind, agent_id)
        if key not in self.routing:
            a, b = self._prior(kind, agent_id)
            self.routing[key] = Arm(alpha=a, beta=b)
        return self.routing[key]

    def _variant_arm(self, agent_id: str, variant: str) -> Arm:
        return self.variants.setdefault((agent_id, variant), Arm())

    def fit(self, tasks: list[dict], user_weight: float, cost_penalty: float) -> "Bandits":
        """Rebuild posteriors from scored tasks."""
        kept = []
        for task in tasks:
            rw = task_reward(task, user_weight)
            if rw is None or task.get("agent") not in self.agents:
                continue
            reward, weight = rw
            # The variant bandit also pays for cost: a cheap model that is nearly as good should win.
            paid = reward - cost_penalty * float(task.get("cost_usd") or 0.0)
            self._routing_arm(task["kind"], task["agent"]).update(reward, weight)
            if task.get("variant"):
                self._variant_arm(task["agent"], task["variant"]).update(paid, weight)
            kept.append((task, reward, paid, weight))
        if self.text_weight > 0 and kept:
            self.sim = Similarity([task_text(t) for t, *_ in kept])
        self.observations = [Observation(t, r, p, w, self.sim.vector(task_text(t)) if self.text_weight > 0 else {})
                             for t, r, p, w in kept]
        return self

    def _contextual(self, text: str | None) -> list[tuple[Observation, float]] | None:
        """(observation, cosine similarity to text) pairs, or None when routing on kind only."""
        if self.text_weight <= 0 or not text:
            return None
        vec = self.sim.vector(text)
        return [(o, Similarity.cosine(vec, o.vector)) for o in self.observations]

    def agent_arm(self, kind: str, agent_id: str, text: str | None = None) -> Arm:
        sims = self._contextual(text)
        if sims is None:
            return self._routing_arm(kind, agent_id)
        a, b = self._prior(kind, agent_id)
        arm = Arm(alpha=a, beta=b)
        t = self.text_weight
        for o, cos in sims:
            if o.task["agent"] == agent_id:
                k = (1 - t) * (o.task["kind"] == kind) + t * cos
                if k > 0:
                    arm.update(o.reward, o.weight * k)
        return arm

    def variant_arm(self, agent_id: str, variant: str, text: str | None = None) -> Arm:
        sims = self._contextual(text)
        if sims is None:
            return self._variant_arm(agent_id, variant)
        arm = Arm()
        t = self.text_weight
        for o, cos in sims:
            if o.task["agent"] == agent_id and o.task.get("variant") == variant:
                arm.update(o.paid, o.weight * ((1 - t) + t * cos))
        return arm

    def choose_agent(self, kind: str, text: str | None = None) -> tuple[str, dict[str, float]]:
        candidates = [a for a in self.agents.values() if a.get("routable", True)]
        samples = {a["id"]: self.rng.betavariate(*_ab(self.agent_arm(kind, a["id"], text))) for a in candidates}
        return max(samples, key=samples.get), samples

    def choose_variant(self, agent_id: str, text: str | None = None) -> tuple[str, dict[str, float]]:
        samples = {v: self.rng.betavariate(*_ab(self.variant_arm(agent_id, v, text)))
                   for v in self.agents[agent_id]["variants"]}
        return max(samples, key=samples.get), samples

    def similar(self, text: str | None, n: int = 3, floor: float = 0.05) -> list[dict]:
        """The past tasks most like this one: the evidence text routing leaned on."""
        sims = self._contextual(text) or []
        top = sorted((x for x in sims if x[1] >= floor), key=lambda x: -x[1])[:n]
        return [{"task_id": o.task["id"], "title": o.task["title"], "kind": o.task["kind"], "agent": o.task["agent"],
                 "variant": o.task.get("variant"), "reward": round(o.reward, 3), "similarity": round(cos, 3)}
                for o, cos in top]

    def snapshot(self, kinds: list[str]) -> dict:
        routable = [a for a in self.agents.values() if a.get("routable", True)]
        routing = []
        for kind in kinds:
            for a in routable:
                arm = self._routing_arm(kind, a["id"])
                routing.append({"kind": kind, "agent": a["id"], "alpha": round(arm.alpha, 3),
                                "beta": round(arm.beta, 3), "mean": round(arm.mean, 4), "n": arm.n})
        variants = []
        for a in routable:
            for v in a["variants"]:
                arm = self._variant_arm(a["id"], v)
                variants.append({"agent": a["id"], "variant": v, "alpha": round(arm.alpha, 3),
                                 "beta": round(arm.beta, 3), "mean": round(arm.mean, 4), "n": arm.n})
        return {"kinds": kinds, "routing": routing, "variants": variants}


def _ab(arm: Arm) -> tuple[float, float]:
    return max(arm.alpha, 1e-6), max(arm.beta, 1e-6)
