# Architecture

State, generation orchestration, and the three platform shells.
Topology/flows: [`knowledge-graph.md`](../knowledge-graph.md) §3–§6;
planning internals: [Director.md](Director.md).

## Purpose & Boundary

- One shared brain, three thin shells. `AppModel` (state) +
  `ContentViewModel` (all generation flows) are platform-neutral; each
  platform supplies exactly one `@main` app file and its own views:
  `MesquetteApp+macOS.swift` → `MacContentView` (primary),
  `MesquetteApp+iOS.swift` → `IPadContentView` (falls back to
  `IPhoneContentView` on compact width), `MesquetteApp+visionOS.swift` →
  windowed `ContentView` + `ImmersiveSpace`.
- Every shell constructs its own `@State AppModel` and injects it via
  `.environment(appModel)`; `ContentViewModel` is owned per-shell
  (`@State` in `MacContentView`). There is no shared singleton state.
- `Mesquette/Components/` holds cross-platform SwiftUI (prompt, quality,
  director cards, export buttons). Platform folders may not reach into
  each other; shared behavior belongs in `AppModel`/`ContentViewModel`.
- All shells launch through `AppLaunchView` (splash covers first load);
  bypassing it reintroduces pre-active GPU work (see ML & Assets).

## Core Contracts & Invariants

- **`AppModel` is the only store.** `@MainActor @Observable` class holding:
  prompt/input, generation history (`generationDict` + `generationOrder` —
  dict for identity, array for display order; keep both in sync), pins,
  quality/params, Director state, progress. Views read it; only
  `ContentViewModel` and `DirectorSession` write generation state.
- **One generation at a time, structurally.** Every public
  `ContentViewModel` entry point (`generateMesh`, `generateAtPins`,
  `generateMeshSet`, `retryPin`) guards on `generationTask == nil` plus
  `!isDirectorBusy` (= generating || compiling || inventing) and silently
  no-ops otherwise. UI must mirror this (disabled controls), not rely on it.
- **Four flows, one record pipeline.** Single (`generateMesh`), pins
  (`generateAtPins`), set (`generateMeshSet`), retry (`retryPin`, same
  prompt, seed +17). All create `GenerationRecord`s up front (so the UI
  shows placeholders), run sequentially, and finish through
  `updateRecords`, which is also where final AABB fit happens and failed
  records unbind their pin.
- **Pin ownership is two-sided, always.** Only `bindPin`/`unbindPin` may
  touch `pin.recordID`/`record.pinID`; `unbindPin(..., belongingTo:)`
  no-ops if the pin was already rebound. `removeGeneration` relies on this.
- **Pin fill is derived, never stored.** `pinFillState` computes
  empty/busy/filled from the bound record; a stale `.generating` record
  reads `.empty` once `isGenerating` is false, so a stuck run cannot brick
  a pin. Failed records leave pins empty on purpose.
- **Backend selection is state, persisted.** `generationModel`
  (UserDefaults `Mesquette.generationModel`) defaults to Shap-E; selecting
  TripoSR forces `.image` input in `didSet`. Text, Compile, and pin flows
  are Shap-E-only by routing guards, not by hiding tabs.
- **Progress never goes backwards.** Phase weights
  (embedding < sampling < projecting < extract stages) plus per-phase step
  monotonicity in `ContentViewModel`; partial meshes only flow when
  `enableLivePartials` (default off — GPU contention).

## Key Design Decisions

- **Records before results.** History rows are inserted synchronously at
  tap time so chat/history UI is immediate; meshes fill in later. Partial
  meshes update the same records with `persistFinal: false` (no AABB fit —
  partials would over-scale).
- **Save/restore around generation.** Pin/set flows snapshot `prompt`,
  `batchSize`, `seed` before mutating them for per-object jobs and restore
  in `defer`. Removing a restore corrupts the user's composer silently.
- **Planning timeouts degrade to code, in the view model.** Tagging gets
  25 s, extras planning 40 s (`tagSceneCastOrNil`, `planExtraPins`):
  timeout/failure → deterministic code cast / leftover pins stay empty.
  Cancellation of the outer task is rethrown, not swallowed — the
  distinction is `Task.isCancelled` checks inside the catches.
- **Final meshes persist as plist in `temporaryDirectory`**
  (`<recordID>_final.plist`, detached utility write). History itself is
  in-memory only; nothing about sessions survives relaunch except
  `@AppStorage` UI prefs and the persisted model choice. Don't assume
  `finalMeshURL` outlives the process.
- **Sets refit as a group.** Any record update triggers `refitSet` for its
  `setID`: pack with pins locked when pins exist, expand fills only when
  pin-free. Per-record placement edits without refit create overlaps.

## Concurrency, Memory & Platform Constraints

- `AppModel` and `ContentViewModel` are `@MainActor`; generation bodies are
  `Task { @MainActor in … }` shells whose MLX work escapes via
  `withMLXError` → MLX's `@concurrent withError`. Closures crossing that
  boundary must be `@Sendable`; progress callbacks hop back with
  `Task { @MainActor }` per tick.
- `cancelInFlightGeneration()` cancels `generationTask`; iOS also sets
  `isIdleTimerDisabled` and refuses to start unless `applicationState ==
  .active` — IOGPU kills processes completing Metal work off-screen.
- Meshes are large value types held per record (`latestMesh`); history is
  unbounded by design. Duplicating record arrays copies mesh references
  through `MeshResult`'s tensors — don't add per-frame record copies.
- visionOS shares everything except rendering: `immersiveSpaceState`
  lives on `AppModel`, `ImmersiveView` observes the same records.

## Known Gotchas / Do Not Break

- `generateMesh` does **not** check `usesPlacementPins`; routing lives in
  the shells (mac: `MacContentView` closures). A shell that calls
  `generateMesh` while pins exist silently ignores the pins.
- `generateAtPins` and `generateMeshSet` **silently return** on guard
  failure (wrong input mode, empty pins, no set compilation). UI that
  enables those buttons without mirroring the guards looks broken, not
  the view model.
- `DirectorSession.revert` clears placement pins as a side effect.
- `applyQualityPreset` fires from `qualityPreset.didSet` and overwrites
  steps/grid/GPU fields — set custom params *after* changing preset.
- `inputMode.didSet` rewrites `guidanceScale` only when it still equals the
  other mode's default (15 ↔ 3). Don't "fix" this into always-reset.
- TripoSR generation is synchronous inside the facade; it must stay inside
  `withMLXError` (off-main) or the UI freezes for the whole extract.

## Verification

- No dedicated AppModel/ViewModel test file; coverage is indirect via
  `PinFillTests` (pin state/ownership on a real `AppModel`),
  `DirectorSessionTests` (apply/revert/stamp), `ModelSelectionTests`
  (picker forces image mode).
- macOS build (`xcodebuild -scheme Mesquette`) is the gate that runs
  today; unit tests run on macOS (see AGENTS Verify). Flow-level evidence also comes from driving
  `ContentViewModel` headlessly against real weights.
