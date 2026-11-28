# Director

Scene planning: turns user English (plus clicked pins) into per-object
Shap-E jobs and placements. Structure: [`knowledge-graph.md`](../knowledge-graph.md) §5–§8.

## Purpose & Boundary

- Owns: object naming/splitting, floor-vs-airborne choice, per-object
  `shapEPrompt`s, scale/material hints, slot layout, AABB fit, pin packing.
- Does not own: mesh generation (`GenerationSessionStore`), mesh pose/rotation
  (Shap-E), rendering, or any UI. Planner code in `Mesquette/Director/` is
  Foundation-only; the one SwiftUI exception is `DirectorAvailabilityView.swift`.
- Entry points are all called by `ContentViewModel` (Architecture page):
  `DirectorClient` (Foundation Models) and pure `DirectorStaging` /
  `DirectorLayoutEngine` (`nonisolated`, `Sendable` value types).
  Platform-neutral; only variance is FM availability
  (`DirectorAvailabilityChecker`), checked first by every client method.

## Core Contracts & Invariants

- **Two entry points, never merged.** Compile (`compile(intent:)` +
  `DirectorSystemPrompt.text` → `CompiledPrompt.normalized()`) and
  Generate-at-pins (`tagSceneCast`/`planPins` + code cast) are separate.
  Editing only the compile prompt changes nothing on the pin path.
- **Two models, two jobs.** `SystemLanguageModel(useCase: .contentTagging)`
  only tags named objects+height; `SystemLanguageModel.default` does compile,
  invent, and extras. Do not swap them.
- **User English is data, not instructions to rewrite.** The only edit allowed
  is `DirectorStaging.objectPrompt`: trim + poison strip (`highly detailed`,
  `cad`, `8k`, `octane`, `manifold`, `polycount`, `photorealistic`). No
  length clip exists (`testObjectPromptDoesNotClipLength`).
- **One concrete object per prompt.** `objectPromptIssue` rejects only
  structural failures: empty, leaked field labels (`title:` etc.), the whole
  scene verbatim, and generic-only filler ("a complementary closed prop").
  Paraphrase is allowed; do not tighten this into style policing.
- **Identity is the full normalized phrase + inventory UUID**
  (`normalizedIdentityKey`, `SceneObject.id`, `PinAssignment.inventoryID`).
  `shortObjectTitle` is display-only. Red/blue sports cars are two objects;
  a repeat of the same phrase is one.
- **Structured height beats heuristics.** `ingestTaggedObject` trusts
  `TaggedHeight.floor/.airborne`; `looksAirborne` (moon/sun/bird/lantern…)
  applies only to `.unspecified`. Pin side: `y >= 0.15`
  (`PlacementPin.airborneThreshold`) is airborne; `y` clamps to `0...2.4`.
- **Code places named objects; the LLM never coordinates.** The pin-plan LLM
  returns only `pinIndex` (1-based into `allPins`) + title/prompt/scale/
  material. `assignmentsMatchingPinIndex` matches by pin identity, requires
  membership in the current chunk, and skips invalid/duplicate/generic items —
  never zip-by-array-order as a recovery.
- **Leftovers stay empty by default.** Extras run only for
  `extrasBudget > 0` pins (chunked at 8 per FM call) and invalid extras are
  skipped, not replaced. `complementaryPinJobs` is intentionally `[]`.
- **Ground is never a mesh.** `isGroundLike` drops track/road/sky/weather;
  the studio floor is the ground. Named forest/meadow patches are single
  mounds; `expandFills` grows them only in the non-pin pack path.
- **Failure degrades to code, visibly.** Tagger failure/short cast falls back
  to `sceneCast` (comma list) and `spatialPair` ("X under/over Y"); jobs get
  `route: .fallback`. There is no retry/repair loop and no second FM pass.
- **Stamp only on exact prompt match** (`DirectorSession.stamp`): scale/
  material/rationale must not leak onto a user-edited prompt.

## Key Design Decisions

- **Foundation Models, not a bundled LLM** — Shap-E already owns GPU/RAM via
  MLX; the system model adds no weights/API key (`DirectorClient` header).
- **Code-first cast, FM as enricher.** `resolvedCast` prefers tagged objects
  only when ≥2 survive filtering; otherwise spatial-pair/code cast wins.
  Atmosphere clauses are dropped by token rules, with explicit keepers
  (e.g. an amber *bottle* survives `isAtmosphereClause`).
- **Slots, not meters, from the LLM.** Compile gets `DirectorSlot` +
  `DirectorLayout`; `applyTemplate`/`restPose` convert to meters and always
  emit yaw 0 (`testRestPoseDoesNotInventYaw`, `testIgnoresLLMMeterOffsets`).
- **`normalized()` is the contract enforcer**: caps sets at 6 parts,
  variations at 4, coerces 1-part sets to `.single`, guarantees non-empty
  parts, drops ground-like parts *after* hero selection. Fix shapes here,
  not at call sites.
- **Scales are spans, not heights.** `DirectorScale.targetSpan` fits the
  mesh's longest AABB axis; thin-axis scaling made walls of flat objects.
  Hero pin jobs are forced `.tabletop`; others go through keyword
  `inferredScale`. `pinWorldScale` grows objects (≤8×) when pins sprawl.
- **Packing respects pins absolutely.** `packRecords` locks any record with
  `pinID` to that pin (never array index), pushes only unlocked records,
  and disables recentering when pins exist.

## Concurrency, Memory & Platform Constraints

- `DirectorServicing` is `@MainActor`; every FM call is `async` off a fresh
  `LanguageModelSession` per operation (one session reused across pin-plan
  chunks, so chunk N sees chunks <N in context — ordering matters).
- All staging/layout/value types are `nonisolated` + `Sendable`; keep them
  that way or `ContentViewModel`'s `@concurrent` generation path breaks.
- No Director state is persisted; `AppModel` owns `lastCompilation`,
  `directorIntent`, `selectedPartID`, `pinPlanNote`, `pinExtrasBudget`.
  `compileGeneration` (AppModel) exists so stale async results can't apply
  over a newer request — preserve that check at call sites.

## Known Gotchas / Do Not Break

- `sceneCast` splits on the **first colon** as setting:inventory and on
  commas; it deliberately does **not** split "under/over" (`spatialPair` is
  a separate fallback). Changing the comma rule breaks hero detection
  ("X as the hero") and many `PinFillTests` fixtures.
- `takePin` silently falls back to *any* remaining pin when no height match
  exists — a sky object can land on the floor if no lifted pin is free.
  That's accepted behavior; don't make it throw.
- Whole-token matching (`containsToken`) guards real bugs: `carved` must not
  infer car scale; `roadster` must not be ground. New keyword lists must go
  through it, never raw `contains`.
- `pack()` clamps to ±0.85 m when recentering, ±5.5 m with pins; hero must
  be assigned before support ordinals are consumed (`applyTemplate`).
- `PlacementDebug.log` is `print`, not `os_log` (knowledge graph says
  otherwise) — pin traces only appear in stdout/Xcode console.
- `DirectorSession.revert` also **clears all placement pins**.
- `spices.randomElement()` makes invent output nondeterministic by design.

## Verification

- `PinFillTests` — pin ownership/fill state, Yorkshire cast, 6 vs 21 pins,
  slider max 15, red/blue car identity, grounded lantern, amber bottle,
  pinIndex skip rules, name-the-height-split prompt text.
- `DirectorLayoutEngineTests` — slots vs LLM meters, pack by `pinID`,
  locked pins, no recenter near pins, fills, span-based fit.
- `DirectorCompiledPromptTests` — `normalized()` clamps/coercions, poison
  strip without clipping, ground dropping, JSON round-trip.
- `DirectorSessionTests` / `DirectorSplitPolicyTests` — stamp non-leakage,
  revert, prompt-policy phrases.
- Suite runs on macOS via the shared scheme (see AGENTS Verify);
  through-app generation runs remain the evidence for FM-dependent paths.
