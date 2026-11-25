Engineering Standards — Mesquette

This document defines the baseline engineering bar for Mesquette. For day-to-day agent workflows, hard product invariants ("Do Not" rules), and build commands, see AGENTS.md and docs/knowledge-graph.md.

1. Core Principles & Simplicity

Favor the simplest viable solution. Complexity must be justified by a real requirement, never by hypothetical future needs.

Optimize for the next maintainer. Write explicit, readable code that communicates intent without requiring reverse-engineering.

Keep changes scoped. Implement the smallest complete change that satisfies the requirement. Avoid unrequested refactors or modifying unrelated code.

2. Architecture & Swift Idioms

Respect platform and subsystem boundaries. Keep ML inference, mesh processing, and Director/ logic strictly decoupled from SwiftUI, SceneKit, and RealityKit. Keep platform-specific rendering and windowing inside macOS/ (primary), iOS/, and visionOS/.

Prefer value types and composition. Favor struct, enum, and focused protocols over class inheritance unless an Apple framework requires NSObject subclassing.

Keep files cohesive. Give each file a clear responsibility without forcing tiny helper types or subviews into separate files that create unnecessary project.pbxproj churn.

Follow Swift naming conventions. Use clear, descriptive names (UpperCamelCase for types/protocols, lowerCamelCase for properties/methods/cases) and guard / early returns to avoid deep nesting.

Preserve data compatibility. Maintain backward compatibility for persisted GenerationRecord data and AssetPacks/ schemas unless a breaking change is explicitly approved.

3. Concurrency, Performance & Memory

Protect @MainActor. Isolate UI state updates to @MainActor and never block it with model loading, MLX inference, image background removal, or mesh export.

Use structured concurrency. Handle Task cancellation cleanly for long-running generation and asset downloads. Avoid orphaned background tasks and never use Task.sleep to mask race conditions.

Respect device memory limits. Avoid unnecessary copies of mesh buffers, textures, and MLX tensors, and release GPU/ML resources promptly—especially for iOS and visionOS devices.

Measure before optimizing. Profile with Instruments before introducing complex optimizations, and document significant performance trade-offs.

4. Error Handling & Observability

Make failures explicit. Never silently swallow errors (try? without justification or empty catch blocks) or hide broken behavior behind silent fallbacks.

Use typed domain errors. Surface clear, user-safe errors at architectural boundaries (e.g., DirectorError) while preserving diagnostic context.

Log intentionally. Use os.Logger for lifecycle events and failures (model loads, downloads, exports, Director compilation). Keep hot render/inference loops quiet and never log tokens, credentials, or sensitive user data.

5. Testing & Debugging

Design for testability. Add or update deterministic unit tests in MesquetteTests/ for meaningful behavioral changes, covering expected paths, invalid input, boundary conditions, and regressions.

Fix root causes. Reproduce the issue, gather evidence, fix the underlying defect, and add regression coverage. Never weaken assertions, delete failing tests, or add blind retries to make a build green.

Be honest about coverage. When automated tests cannot run (e.g., hardware-only visionOS immersive behavior or current SDK blockers), state what was verified versus not tested.

6. Security & Dependencies

Validate untrusted input. Treat user prompts, imported images, and downloaded asset manifests as untrusted.

Guard secrets and entitlements. Never hardcode tokens or commit local .env files. Maintain least privilege in Mesquette.entitlements and AssetDownloader.entitlements, and never disable App Sandbox to work around an issue.

Minimize external dependencies. Prefer Apple system frameworks and existing packages. Before adding a SwiftPM dependency, evaluate security, maintenance, multi-platform support (macOS, iOS, visionOS), and licensing (update THIRD_PARTY_NOTICES.md).

7. Documentation & Repo Hygiene

Document the why. Add doc comments for public APIs, non-obvious invariants (coordinate-space conversions, concurrency guarantees, memory constraints), and trade-offs. Skip comments that merely restate the code.

Keep architecture docs in sync. Update docs/knowledge-graph.{md,json} in the same change as Swift edits and verify with scripts/check-knowledge-graph.sh. Update README.md or subsystem docs when pipelines or contracts change.

Keep commits clean. Never commit DerivedData/, downloaded model weights, or packaged asset packs. Fix compiler and Swift concurrency warnings at the source instead of suppressing them.

8. Significant Architectural Changes

Before introducing a major architectural change or breaking change, document:

Problem & motivation — Why the current design is insufficient.

Options considered — Simpler alternatives and why the proposed design wins.

Impact — Effects on macOS, iOS, visionOS, memory/performance, security, and backward compatibility.

Rollout & rollback — Migration needs and how to revert safely.

9. Definition of Done

A change is complete when:

Requirements are met and all product invariants in AGENTS.md remain intact.

Code is clean, warning-free, and appropriately documented.

docs/knowledge-graph.{md,json} is updated and scripts/check-knowledge-graph.sh passes.

Relevant tests are added/updated and all runnable build/test checks have been verified.

Known limitations or unverified areas are explicitly disclosed.