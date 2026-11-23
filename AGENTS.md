# Mesquette — agent notes

Product name **Mesquette**. Mac is the primary UI.

**Read first:** [`docs/knowledge-graph.md`](docs/knowledge-graph.md)  
**Machine graph:** [`docs/knowledge-graph.json`](docs/knowledge-graph.json)

## Knowledge graph (mandatory)

The graph is part of the change, not a follow-up.

After **any** Swift edit under `Mesquette/`, `AssetDownloader/`, or `MesquetteTests/`:

1. Update `docs/knowledge-graph.md` **and** `docs/knowledge-graph.json` in the same turn.
2. Keep invariants, flows, node `path`s, and edges true.
3. Run `scripts/check-knowledge-graph.sh` before you finish.
4. Do not claim the task is done if that script fails.

A pre-commit hook runs the same check (`scripts/install-git-hooks.sh` once per clone).

| Change | Update |
|---|---|
| New / renamed / deleted Swift type or file | nodes + edges + node index |
| Different generate / pin / extras / compile path | flows + mermaid |
| New or dropped product rule | invariants + Do not below |
| New test or verify command | tests / verify |

## Do not

- Pose or lock-rotate meshes. Pins own placement. Shap-E owns rotation.
- Rewrite the user’s scene English (no 24-word clip). Poison-only: CAD / 8K / photorealistic / highly detailed.
- Paste the whole scene into every Shap-E prompt.
- Auto-fill leftover pins. Extra props are a 0…leftover slider, default 0.
- Map `packRecords` by array index when `record.pinID` is set.
- Deduplicate objects by last-word title (`Car`).
- Override tagging height with `looksAirborne`.
- Add an LLM repair loop or mesh-vision evaluator.
- Treat Compile (`DirectorSystemPrompt.text`) as the Generate-at-pins path.
- Route text prompts or pin scenes to TripoSR. It is image-to-3D only; the model picker forces image mode and pin routing stays on Shap-E.

## Verify

```
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -scheme Mesquette -destination 'platform=macOS,arch=arm64' build
```

Tests are visionOS-only and currently fail to compile on the locator’s visionOS 27 Background Assets APIs.
