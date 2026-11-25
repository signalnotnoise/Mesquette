# AGENTS.md — Mesquette

- **Product name:** Mesquette. **Mac is the primary UI.**
- **Read first:** [`docs/knowledge-graph.md`](docs/knowledge-graph.md)
- **Machine graph:** [`docs/knowledge-graph.json`](docs/knowledge-graph.json)

## Subsystem Wiki

- [`docs/wiki/Director.md`](docs/wiki/Director.md) — planning, pins, compile
- [`docs/wiki/Architecture.md`](docs/wiki/Architecture.md) — state, flows, shells
- [`docs/wiki/ML-and-Assets.md`](docs/wiki/ML-and-Assets.md) — runtimes, weights, image prep
- [`docs/wiki/3D-and-Export.md`](docs/wiki/3D-and-Export.md) — viewport, camera, export

## Knowledge Graph (Mandatory)

The graph is part of the change, not a follow-up. After **any** Swift edit under `Mesquette/`, `AssetDownloader/`, or `MesquetteTests/`:

1. Update `docs/knowledge-graph.md` and `docs/knowledge-graph.json` in the same turn.
2. Keep invariants, flows, node paths, and edges true.
3. Run `scripts/check-knowledge-graph.sh` before you finish.
4. Do not claim the task is done if that script fails.

A pre-commit hook runs the same check (`scripts/install-git-hooks.sh` once per clone).

| Change | Update |
| --- | --- |
| New / renamed / deleted Swift type or file | nodes + edges + node index |
| Different generate / pin / extras / compile path | flows + mermaid |
| New or dropped product rule | invariants + **Do Not** below |
| New test or verify command | tests / verify |

## Do Not (Hard Product Invariants)

- **Do not** pose or lock-rotate meshes. Pins own placement. Shap-E owns rotation.
- **Do not** rewrite the user's scene English (no 24-word clip). Poison-only stripping: `CAD` / `8K` / `photorealistic` / `highly detailed`.
- **Do not** paste the whole scene into every Shap-E prompt.
- **Do not** auto-fill leftover pins. Extra props are a `0…leftover` slider, default `0`.
- **Do not** map `packRecords` by array index when `record.pinID` is set.
- **Do not** deduplicate objects by last-word title (`Car`).
- **Do not** override tagging height with `looksAirborne`.
- **Do not** add an LLM repair loop or mesh-vision evaluator.
- **Do not** treat Compile (`DirectorSystemPrompt.text`) as the Generate-at-pins path.
- **Do not** route text prompts or pin scenes to TripoSR. It is image-to-3D only; the model picker forces image mode and pin routing stays on Shap-E.

## Target & Directory Boundaries

- `Mesquette/` — Shared app state, ML runtime stores (`ShapERuntimeStore`, `TripoSRStore`), mesh/image pipelines, and core models.
- `Mesquette/Director/` — Prompt compilation, layout, staging, and pin assignment. Planner/model files stay UI- and platform-agnostic (no SwiftUI, SceneKit, or RealityKit); `DirectorAvailabilityView.swift` is the existing SwiftUI exception — don't add more.
- `Mesquette/Components/` — Shared, platform-agnostic SwiftUI components.
- `Mesquette/macOS/` (**primary UI**), `Mesquette/iOS/`, `Mesquette/visionOS/` — Platform-specific views, windowing, and 3D studios (`SceneKitStudio`, `ImmersiveStudio`).
- `AssetDownloader/` & `Packages/RealityKitContent/` — Background asset extension and Reality Composer Pro assets.
- `Vendor/apple-mlx-foundations/` — Read-only submodule; do not edit directly unless intentionally updating the submodule.

## Engineering Guardrails

Baseline bar: [`docs/engineering_standards.md`](docs/engineering_standards.md).
The guardrails below are the short form; the standards doc wins on detail.

- **Minimal scope:** Make the smallest complete change that solves the task. Do not perform unrequested refactors or alter unrelated files.
- **Swift idioms over rigid rules:** Prefer value types (`struct`, `enum`) and composition over inheritance. Group tightly coupled helper types or small subviews naturally instead of creating unnecessary `project.pbxproj` churn, and verify any new file is added to the right target(s).
- **Concurrency & performance:** Isolate UI state to `@MainActor`. Never block `@MainActor` with model loading, MLX inference, background removal, or mesh export. Handle `Task` cancellation cleanly; never use `Task.sleep` to mask race conditions. Documented exceptions: the 80 ms foreground settle in `MLXForegroundGPU.prepare` (Metal stream must exist before `@concurrent` submits), the Director planning timeouts (25 s tag / 40 s extras), and SplashView's animation choreography (presentation timing, not synchronization).
- **Errors & warnings:** Never silently swallow errors (`try?` without justification) or suppress compiler/concurrency warnings. Fix root causes at the source.
- **Repo hygiene:** Never commit `DerivedData/`, downloaded model weights (`scripts/fetch-weights.sh`), packaged asset packs, or local `.env` files (`scripts/asset-pack-upload.env.example` is template-only).
- **Honest reporting:** Distinguish between what was **verified**, **not tested**, and **blocked**. Never fabricate build or test results.

## Verify

Run the primary macOS build and knowledge graph check before finishing:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -scheme Mesquette -destination 'platform=macOS,arch=arm64' build
scripts/check-knowledge-graph.sh
```

Test limitation: MesquetteTests are visionOS-only and currently fail to compile on the locator's visionOS 27 Background Assets APIs. Do not claim unit tests passed unless that blocker is resolved and tests actually ran; report this limitation explicitly.
