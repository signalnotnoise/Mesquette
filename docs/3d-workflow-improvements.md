# Mesquette — 3D Workflow Improvements

**Status:** Living roadmap  
**Last updated:** 2026-07-26  
**Scope:** Product and engineering improvements to turn Mesquette from a Shap‑E demo into a usable **generate → inspect → choose → export** 3D tool across macOS, iPadOS, and visionOS.

### Related context

| Topic | Summary |
|-------|---------|
| **Current stack** | On-device Shap‑E (`ShapERuntime`) → SDF / marching cubes → `MeshResult` → SceneKit (macOS/iOS) or RealityKit (visionOS) |
| **Strength** | Fast on-device ideation, multiplatform previews, progressive partial meshes |
| **Limits** | Soft organic geometry (not hard-surface CAD), no export path, GPU contention during partials, thin asset history |
| **Related code** | `ContentViewViewModel`, `AppModel`, `GenerationRecord`, `ShapEMeshAdapter`, `ImmersiveViewModel`, previews under `macOS/` / `iOS/` / `visionOS/` |

---

## 1. Product strategy

### Target loop

```
Prompt / image → Generate → Inspect → Compare / pin → Export → DCC / AR / share
```

### Positioning

| Role | Fit |
|------|-----|
| **Primary** | On-device **3D ideation shell** (Shap‑E for cheap drafts) |
| **Not primary** | High-fidelity hard-surface production (castles, machinery, clean topology) |
| **Future** | Same library UI + optional higher-quality backends for “enhance” |

### What not to over-invest in early

- Ultra-long “manifold / razor-sharp topology / 3D scan” prompt engineering — Shap‑E will not honor this
- Firebase (or similar) before export + asset library exist
- Writing every partial mesh to disk
- Pushing 256 inference steps for architecture quality
- Progressive live previews at the expense of stable finals

---

## 2. Current-state gaps (workflow lens)

| Area | Today | Gap for 3D workflows |
|------|--------|----------------------|
| **Output** | In-memory `MeshResult` / RealityKit–SceneKit only | No USDZ / OBJ / glTF handoff to Blender, Unity, Quick Look |
| **History** | Chat-style `GenerationRecord`; `historyURLs` write temp plists, unread | Not an asset browser; disk bloat; no params/seed snapshot |
| **Quality controls** | Raw sliders (steps, grid, batch, GPU) | No presets, weak guidance for what actually improves meshes |
| **Inspection** | Orbit / pan / scale previews | No wireframe, stats, scale readouts, lighting modes |
| **Stability** | Progressive partials + Metal MC + RealityKit | GPU hangs / recovery mid-sampling; stalled progress |
| **visionOS layout** | Jump animation + batch spacing | Multi-mesh batches can stack; collision can go stale |
| **Post-process** | None | No decimate, cleanup, or export LODs |

---

## 3. Improvement areas

### 3.1 Export and interchange *(highest leverage)*

Meshes currently never leave the app as DCC-ready files.

| Improvement | Formats / behavior | Why |
|-------------|-------------------|-----|
| Export USD / USDZ | Reality Composer, Quick Look, Unity, Blender USD | Apple-native handoff |
| Export OBJ (+ MTL if useful) | Universal DCC | Widest tool support |
| Export glTF 2.0 | Web, Three.js, many engines | Standard realtime path |
| Export PLY | Vertex colors / scan-like data | Good for color-heavy Shap‑E output |
| Batch export | Selected history items | Variation workflows |
| Share / save | Share sheet (iOS/visionOS), Finder save (macOS) | One-tap client handoff |
| Sidecar metadata | Prompt, seed, steps, grid, guidance, model id | Reproducibility |

**Suggested storage:** Application Support project folder, not temp; name files from prompt slug + timestamp + seed.

**Implementation sketch:**

- `MeshExporter` that reads `MeshResult` vertices / faces / RGBA
- Prefer final meshes only (not intermediate partials)
- Optional post-export open-in / Quick Look

---

### 3.2 Generation quality controls

Shap‑E + marching cubes produce soft isosurfaces. The product can still **steer** better drafts.

| Improvement | Detail |
|-------------|--------|
| **Quality presets** | **Preview:** grid ~48, steps ~16, no partials. **Standard:** grid 64, steps 32–64. **High:** grid 128 (where memory allows), steps 64 |
| **Platform caps** | Safer defaults and ceilings on visionOS/iOS; higher on macOS |
| **Prompt templates** | Categories: object, creature, prop, architecture — short, model-friendly copy |
| **Prompt UX** | Discourage useless style fluff; show examples that work for Shap‑E |
| **Seed control** | Explicit seed, “regenerate variation”, pin good seeds on records |
| **A/B compare** | Side-by-side SceneKit / RealityKit for two records |
| **Optional mesh cleanup** | Weld duplicates, drop tiny connected components, recompute normals before display/export |

**Shap‑E prompt guidance (document for users):**

- Prefer short visual descriptions: *“small white marble castle, four round towers, arched gate”*
- Avoid packing many hard constraints (battlements + buttresses + tracery + ivy + “clean manifold”)
- “Razor-sharp topology / explicit geometric boundaries” does not upgrade the mesh generator

---

### 3.3 Stabilize GPU and progressive previews

Observed failure mode: `IOGPUMetalError` / `kIOGPUCommandBufferCallbackErrorHang` during long sampling with intermediate mesh extracts, often near mid-run progress (e.g. step ~106 of a long schedule).

**Root pattern:** concurrent Metal clients —

1. **MLX** diffusion (`MLX.eval`)
2. **Metal marching cubes** (`usesGPU` → `MetalMarchingCubes`, separate `MTLCommandQueue`)
3. **RealityKit / SceneKit** uploads from partial history updates

| Improvement | Priority | Notes |
|-------------|----------|--------|
| Partials **off by default** | High | Or only last partial / every N ≫ 5 steps |
| **CPU MC for partials**, Metal MC only for **final** extract | High | Cuts hang risk while keeping GPU final quality |
| Throttle RealityKit / SceneKit sync | High | Don’t rebuild entities every progress tick; observe mesh revision tokens |
| Check `MTLCommandBuffer.error` after `waitUntilCompleted` | Medium | Surface “GPU recovered” instead of silent stall |
| Memory budgets | Medium | Extend iOS/visionOS cache limits discipline to final extract path |
| Cap steps / grid on device classes | Medium | e.g. visionOS max steps/grid |

**Related progress UX (ShapERuntime + app):**

- Non-interval sampling ticks currently report empty phase `""` and are dropped by `phaseWeight` filtering in `ContentViewViewModel`
- Percentage is `currentStep/totalSteps` **per phase**, so projecting/extracting can show 0% after sampling
- Prefer phase-aware progress (embedding → sampling → projecting → extracting → done) and unconditional debug logs when diagnosing hangs

---

### 3.4 Asset history (versioned library)

`GenerationRecord` today:

```text
id, prompt, timestamp, status, latestMesh, historyURLs
```

`historyURLs` appends a temp plist per partial and is never loaded back; progressive generation floods temp storage.

| Improvement | Detail |
|-------------|--------|
| Persist **final mesh only** (+ optional single last partial) | Disk and UX sanity |
| Session / project **library** | Thumbnail, prompt, params, seed, status |
| Favorite / pin / tags | Hero assets |
| “Iterate from this” | Reload params + prompt from a record |
| Delete / clear with file cleanup | No orphan temp files |
| Metadata schema | `GenerationParams` snapshot on complete |

Treat history as a **mini asset browser**, not chat-only.

---

### 3.5 Inspection tools (mesh QA)

| Feature | Purpose |
|---------|---------|
| Wireframe / solid / textured toggle | Topology vs shading |
| Flat shading / normal visualization | Spot bad lighting or degenerate faces |
| Bounding box + scale readout | Real-world size before export |
| Vertex / face counts | Ship vs regenerate decision |
| Watertight / empty-mesh heuristics | Fail soft with clear UI |
| Section / clip plane | Interior of blobby volumes |
| Lighting presets | Studio / outdoor / unlit vertex color |
| Ground grid + reference cube/sphere | Scale judgment |

**Platform notes:**

- macOS / iPad: inspector chrome beside SceneKit preview  
- visionOS: compact inspector in the window; immersive stays for placement

---

### 3.6 Transform and layout

Existing: immersive drag / rotate / magnify; batch entities.

| Feature | Purpose |
|---------|---------|
| Snap to grid / floor | Room placement |
| Align / distribute multi-batch | Row of variations (fix jump-anim overwriting X spacing) |
| Reset pose / frame camera | Per platform |
| Simple measure (two-point) | Spatial planning |
| Save scene arrangement | Multi-mesh mockups |

**Known immersive issues to fold into this work:**

| Issue | File (approx) | Fix direction |
|-------|----------------|---------------|
| Concurrent `sync` could drop updates | `ImmersiveViewModel` | Dirty-flag resync (partially addressed) |
| Jump animation overwrites batch X spacing | `ImmersiveViewModel.applyJumpAnimation` | Seed animation from spaced final transforms |
| Collision only on create | `ImmersiveViewModel` | Regenerate after material final mesh updates |
| First create lacks capacity reallocation fallback | `ImmersiveViewModel` | Share ensure-capacity path with updates |

---

### 3.7 Post-process pipeline

| Stage | Idea | Export value |
|-------|------|--------------|
| Decimate | Target triangle budget (e.g. ≤50k) | Games / AR |
| Optional smooth / remesh | Reduce MC stair-steps | Visual polish |
| UV unwrap + bake (later) | Real materials vs vertex color only | DCC materials |
| Collision proxy | Box / convex hull | RealityKit physics |
| “Export optimized” preset | One button | Non-expert path |

Even a single **Export optimized (≤50k tris)** path is a large workflow win.

---

### 3.8 Multi-modal input

Existing: text, image-to-3D, background removal (`ImageBackgroundRemoval`).

| Improvement | Notes |
|-------------|--------|
| Crop / mask UI for image refs | Cleaner silhouettes → better meshes |
| Local reference image library | Repeatable style refs |
| Combined prompt + image | Text for category; image for shape |
| Future: multi-view / depth / sketch | Only if backend supports or second model is added |

---

### 3.9 Multi-backend / quality ladder

Shap‑E alone caps hard-surface quality (e.g. Renaissance castle prompts → soft white isosurface).

| Path | Role |
|------|------|
| Keep Shap‑E | Fast on-device ideation |
| Optional cloud / second model | Architecture, hard surface, “enhance” |
| Shared export + history UI | One library, multiple generators |
| “Enhance” action | Send best draft out for higher-quality remesh |

**Product framing:** ideation shell first; not a single-model demo forever.

---

### 3.10 visionOS spatial workflow

| Improvement | Notes |
|-------------|--------|
| Place on real surfaces (plane detection) | Design-in-context |
| Persist world anchors | Return to same layout |
| Hand / chrome actions: regenerate, export, duplicate | Immersive-native loop |
| Fix batch spacing + collision refresh | Correct multi-mesh scenes |
| LOD / simplify when many entities | Performance |

---

### 3.11 Collaboration and handoff

| Feature | Notes |
|---------|--------|
| AirDrop / share USDZ | Designer → client |
| Project folders | Prompts + meshes + exports (studio / class packs) |
| Prompt sheet export | Markdown/PDF: prompt + params + screenshot |
| Clipboard prompt + seed | Repro across machines |

---

### 3.12 Reliability and engineering foundation

| Item | Why |
|------|-----|
| Run generation off MainActor (dedicated actor/queue) | UI stays responsive |
| Cancel in-flight generation | Essential for long runs |
| Phase-aware progress + accurate % | Sampling vs project vs extract |
| Structured errors | OOM, GPU hang, empty mesh, bundle missing |
| Remove unused Firebase products until used | Build time, binary size, packaging risk |
| `.gitignore` for root `test_*` scratch scripts/binaries | Clean tree |
| Unit tests: mesh export, adapter vertex layout, color channel contract | Prevent silent mesh corruption |
| Assert `ShapEVertex` UV offsets vs `LowLevelMesh` descriptor | Avoid corrupt meshes after layout changes |

---

## 4. Prioritized roadmap

### Phase A — Shipable workflow *(highest ROI)*

1. **USDZ / OBJ export + share** from final `MeshResult`
2. **Disable or throttle partials**; safer GPU path (CPU partials / Metal final)
3. **Quality presets** + explicit **seed**
4. **History library** (final only) with **params snapshot**
5. Progress UX: phase labels; don’t drop non-interval sampling ticks for UI %

### Phase B — 3D craft

6. Inspector: wireframe, stats, lighting, scale
7. Mesh cleanup + decimate on export
8. Immersive batch layout, jump animation spacing, collision refresh
9. Cancel generation + structured error UI

### Phase C — Product depth

10. Second backend / enhance path for hard surface
11. Spatial placement + anchors on visionOS
12. Projects / handoff packs (folder + sheet)
13. UV / material pipeline (optional, larger effort)

---

## 5. Acceptance criteria (by theme)

### Export

- [ ] User can export a completed mesh to at least **USDZ** and **OBJ**
- [ ] Export includes vertex colors when present
- [ ] Share sheet / save panel works on each platform target
- [ ] Metadata sidecar or filename encodes seed + timestamp

### Stability

- [ ] Full sampling + final extract completes on device without GPU hang at Standard preset
- [ ] Partials (if enabled) cannot starve or deadlock final generation
- [ ] Cancel stops work and leaves UI idle with clear status

### Library

- [ ] Completing a gen adds a browsable library entry with thumbnail and params
- [ ] Deleting an entry removes associated files
- [ ] “Iterate from this” restores prompt + generation parameters

### Inspection

- [ ] User can toggle wireframe and see vertex/face counts
- [ ] Scale / bounds visible before export

### visionOS

- [ ] Batch size > 1 places meshes without stacking
- [ ] Gestures hit current mesh bounds after final update
- [ ] Latest mesh always applied after concurrent progress updates (dirty resync)

---

## 6. Suggested module map (future code layout)

```text
Mesquette/
  Export/
    MeshExporter.swift          # MeshResult → USDZ / OBJ / glTF / PLY
    ExportMetadata.swift
  Library/
    GenerationStore.swift       # persistence
    GenerationRecord+Params.swift
  Generation/
    QualityPreset.swift
    GenerationCoordinator.swift # cancel, actor isolation, progress
  Inspect/
    MeshStats.swift
    PreviewShadingMode.swift
  PostProcess/
    MeshCleanup.swift
    MeshDecimator.swift
```

Keep platform previews thin; shared mesh/export/stats logic in common sources.

---

## 7. Parameter defaults (recommended starting point)

| Parameter | Preview | Standard | High (macOS-first) |
|-----------|---------|----------|--------------------|
| `numInferenceSteps` | 16 | 32–64 | 64 |
| `gridSize` | 48 | 64 | 128 |
| Partials | Off | Off or rare | Off or rare |
| Metal marching cubes | Final only / off | Final only | Final only |
| `batchSize` | 1 | 1–2 | 1–4 (memory permitting) |
| `queryBatchSize` | Platform default | Platform default | Raise carefully on Mac |

Document in-app next to sliders so users understand tradeoffs (time, memory, softness).

---

## 8. Known technical debt tied to this roadmap

Captured from review and runtime investigation (not an exhaustive bug list):

| Severity | Topic | Location (indicative) |
|----------|--------|------------------------|
| Bug / risk | GPU hang under MLX + Metal MC + live preview | `MetalMarchingCubes`, partial path in `ShapERuntime`, `ImmersiveView` sync |
| Bug | Jump animation wipes batch X spacing | `ImmersiveViewModel` |
| Bug | No capacity fallback on first entity create | `ImmersiveViewModel` |
| Bug | Collision shapes not refreshed after mesh update | `ImmersiveViewModel` |
| Bug | `historyURLs` write-only temp dumps | `ContentViewViewModel.updateRecords` |
| UX | Empty-phase progress drops most sampling ticks | `ShapERuntime` + `ContentViewViewModel` |
| Debt | Unused Firebase package products linked | Xcode project |
| Debt | Scratch `test_*` at repo root | `.gitignore` / cleanup |
| Debt | Duplicate mesh paths (SceneKit builders vs LowLevelMesh) | `ShapEMeshAdapter` |

---

## 9. Success metrics (optional)

| Metric | Intent |
|--------|--------|
| % of sessions with ≥1 export | Workflow completion |
| Final extract success rate (no hang / no empty mesh) | Reliability |
| Time-to-first-final at Standard preset | Performance budget |
| Library revisit rate (“iterate from this”) | Creative loop |
| Crash-free rate during generation | Quality bar |

---

## 10. One-line strategy

> Make Mesquette a **generate → inspect → choose → export** loop with **stable finals** and **DCC interchange**, not only a live progressive blob viewer.

---

## Document history

| Date | Change |
|------|--------|
| 2026-07-26 | Initial roadmap from 3D workflow review (export, quality, GPU stability, library, inspection, post-process, multi-backend, visionOS, reliability) |
| 2026-07-26 | **Shipped Phase A (partial):** quality presets, seed wired through, live partials off by default + `progressInterval`, CPU MC for partials, phase-aware progress UI, final-only disk persist, OBJ/USDZ export + share/save, params snapshot on records |

---

## Shipped changelog

### 2026-07-26 — Phase A foundation

| Item | Status | Notes |
|------|--------|--------|
| Quality presets (Preview / Standard / High) | Done | `QualityPreset.swift`, bound in visionOS + macOS + iPad params |
| Explicit seed passed to runtime | Done | Was always `nil` before |
| Live partials off by default | Done | `enableLivePartials`; runtime `progressInterval: 0` skips extracts |
| CPU MC for intermediate partials | Done | ShapERuntime partial path forces `useMetalMarchingCubes: false` |
| Phase-aware progress | Done | `progressPhaseLabel` + overall 0…1 mapping |
| Stop partial historyURL spam | Done | Only optional final plist; `finalMeshURL` + `params` on record |
| Export OBJ + USDZ | Done | `MeshExporter` + `ExportMeshButton` on completed chat bubbles |
| Params snapshot on records | Done | `GenerationParams` for iterate-from-this later |

**Remaining Phase A / B (next):** iterate-from-this, library browser, cancel generation, immersive spacing/collision fixes, mesh stats inspector.
