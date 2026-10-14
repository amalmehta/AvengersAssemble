#!/usr/bin/env bash
# Assembles the website into build/site: site/index.html plus the images it uses from docs/images,
# so the README and the site share one copy of every screenshot. GitHub Pages publishes build/site.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/site"
rm -rf "$OUT"
mkdir -p "$OUT/images"
cp "$ROOT/site/index.html" "$OUT/"
# Every image the page references must exist.
for img in $(grep -o 'images/[A-Za-z0-9._-]*\.png' "$ROOT/site/index.html" | sort -u); do
    cp "$ROOT/docs/$img" "$OUT/$img"
done
touch "$OUT/.nojekyll"
echo "Built $OUT ($(ls "$OUT/images" | wc -l | tr -d ' ') images)"
