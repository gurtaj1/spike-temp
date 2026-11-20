#!/bin/bash
# Builds the app into dist/ and nowhere else:
#   dist/worker.js     src/worker.ts bundled by bun build into one ESM file for Workers
#   dist/assets/       a copy of public/
#   dist/migrations/   a copy of migrations/
# Needs bun on PATH and node_modules installed. Runs none of the app's code.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f package.json ] && [ -f src/worker.ts ] || { echo "build: not in the app folder" >&2; exit 1; }

rm -rf dist
mkdir dist
bun build src/worker.ts --target browser --format esm --outfile dist/worker.js
cp -R public dist/assets
cp -R migrations dist/migrations

echo "build: worker.js $(wc -c <dist/worker.js | tr -d ' ') bytes," \
  "assets $(find dist/assets -type f | wc -l | tr -d ' ') files," \
  "migrations $(find dist/migrations -type f | wc -l | tr -d ' ') files"
