#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
git config core.hooksPath scripts/githooks
chmod +x scripts/githooks/pre-commit scripts/check-knowledge-graph.sh
echo "core.hooksPath=scripts/githooks"
