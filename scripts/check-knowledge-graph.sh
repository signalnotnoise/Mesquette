#!/usr/bin/env bash
# Fail if the knowledge graph is invalid or stale vs Swift changes.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

md="docs/knowledge-graph.md"
json="docs/knowledge-graph.json"
python="${PYTHON:-/usr/bin/python3}"

if [[ ! -f "$md" || ! -f "$json" ]]; then
  echo "knowledge graph missing: $md and $json are required" >&2
  exit 1
fi

"$python" - "$json" <<'PY'
import json, os, sys

path = sys.argv[1]
with open(path) as f:
    data = json.load(f)

required = ("schema", "nodes", "edges", "invariants", "flows")
missing = [k for k in required if k not in data]
if missing:
    sys.exit(f"{path} missing keys: {missing}")

missing_paths = []
for node in data["nodes"]:
    rel = node.get("path")
    if not rel:
        continue
    if not os.path.isfile(rel):
        missing_paths.append(f"{node.get('id', '?')}: {rel}")
if missing_paths:
    sys.exit("knowledge-graph.json paths do not exist:\n  " + "\n  ".join(missing_paths))

print(f"ok graph: {len(data['nodes'])} nodes, {len(data['edges'])} edges, {len(data['invariants'])} invariants")
PY

source_globs=(
  "Mesquette/*.swift"
  "Mesquette/**/*.swift"
  "AssetDownloader/*.swift"
  "AssetDownloader/**/*.swift"
  "MesquetteTests/*.swift"
  "MesquetteTests/**/*.swift"
)

is_source() {
  case "$1" in
    Mesquette/*.swift|Mesquette/*/*.swift|Mesquette/*/*/*.swift) return 0 ;;
    AssetDownloader/*.swift|AssetDownloader/*/*.swift) return 0 ;;
    MesquetteTests/*.swift) return 0 ;;
    *) return 1 ;;
  esac
}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

changed=()
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  changed+=("$file")
done < <(git diff --name-only HEAD; git diff --cached --name-only; git ls-files --others --exclude-standard)

source_changed=0
graph_changed=0
for file in "${changed[@]+"${changed[@]}"}"; do
  case "$file" in
    docs/knowledge-graph.md|docs/knowledge-graph.json|AGENTS.md)
      graph_changed=1
      ;;
  esac
  if is_source "$file"; then
    source_changed=1
  fi
done

if [[ "$source_changed" -eq 1 && "$graph_changed" -eq 0 ]]; then
  echo "knowledge graph is stale." >&2
  echo "Swift under Mesquette/, AssetDownloader/, or MesquetteTests/ changed," >&2
  echo "but docs/knowledge-graph.md, docs/knowledge-graph.json, and AGENTS.md did not." >&2
  echo "Update the graph in the same change, then re-run scripts/check-knowledge-graph.sh" >&2
  exit 1
fi
