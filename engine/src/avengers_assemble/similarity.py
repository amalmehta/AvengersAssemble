"""TF-IDF similarity between tasks, computed locally from their titles and descriptions.

It catches shared vocabulary ("gripper", "pricing", "thermal"), not deep paraphrase.
"""
from __future__ import annotations

import math
import re
from collections import Counter

STOPWORDS = set("""
a about above after again all also an and any are as at be because been before being below between both but by
can could did do does doing down during each few for from further had has have having here how i if in into is it
its itself just more most no nor not now of off on once only or other our out over own same should so some such
than that the their them then there these they this those through to too under until up very was we were what
when where which while who whom why will with would you your use using make write design build plan create
task deliverable include including first v1 one two three
""".split())


def tokens(text: str) -> list[str]:
    words = re.findall(r"[a-z][a-z0-9]+", text.lower())
    out = []
    for w in words:
        if len(w) < 3 or w in STOPWORDS:
            continue
        if len(w) > 4 and w.endswith("s") and not w.endswith("ss"):
            w = w[:-1]  # crude plural folding: "grippers" ~ "gripper"
        out.append(w)
    return out


def task_text(task: dict) -> str:
    return f"{task.get('title', '')} {task.get('description', '')}"


class Similarity:
    """Fits IDF on a corpus of task texts; cosine similarity of TF-IDF vectors, in [0, 1]."""

    def __init__(self, texts: list[str]):
        docs = [set(tokens(t)) for t in texts]
        n = len(docs)
        df = Counter(w for d in docs for w in d)
        # Smoothed IDF, so words seen in every document still count a little.
        self.idf = {w: math.log((1 + n) / (1 + c)) + 1.0 for w, c in df.items()}
        self.default_idf = math.log(1 + n) + 1.0

    def vector(self, text: str) -> dict[str, float]:
        tf = Counter(tokens(text))
        vec = {w: c * self.idf.get(w, self.default_idf) for w, c in tf.items()}
        norm = math.sqrt(sum(v * v for v in vec.values()))
        return {w: v / norm for w, v in vec.items()} if norm else {}

    @staticmethod
    def cosine(a: dict[str, float], b: dict[str, float]) -> float:
        if len(a) > len(b):
            a, b = b, a
        return sum(v * b.get(w, 0.0) for w, v in a.items())
