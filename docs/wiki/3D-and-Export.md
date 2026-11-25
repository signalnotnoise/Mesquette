# 3D & Export

Viewport, camera, mesh presentation, and file export. Placement math that
*decides* positions lives in the Director (`DirectorLayoutEngine`); this
subsystem only realizes them. Topology: [`docs/knowledge-graph.md`](../knowledge-graph.md) §10.

## Purpose & Boundary

- Owns: turning `MeshResult` tensors into renderable geometry on three
  renderers, the table/camera rigs, pin interaction visuals, and OBJ/USDZ
  export (`MeshExporter`).
- Renderers: SceneKit on macOS+iOS (`SceneKitStudio` shared,
  `Mac3DPreviewView`/`IPad3DPreviewView` hosts), RealityKit on visionOS
  (`ShapEMeshAdapter` + `ImmersiveStudio`/`ImmersiveView`).
- Does not own: which mesh goes where (Director), record lifecycle
  (Architecture), or sit/scale decisions — it consumes
  `GenerationRecord.offset{X,Y,Z}`, `placementScale`, `footprintRadius`.
- `Packages/RealityKitContent` is static table scenery only; generated
  meshes never enter it.

## Core Contracts & Invariants

- **Coordinate space, everywhere:** meters on a table, **+X right, +Z
  toward the user, Y up**. Pin/record offsets, `DirectorLayoutEngine`
  output, SceneKit placement, and visionOS staging all share it. The
  runtime's `MeshResult` vertices are consumed as-is — no axis swap at
  this layer; if a mesh looks rotated, that's Shap-E's rest pose.
- **Never pose the mesh.** `SceneKitStudio.applyTablePose` and
  `replaceGeometry` deliberately never write wrapper `eulerAngles`;
  the only rotation is the user's lock-drag on the wrapper. Compile-time
  `rotationY` from templates is data, not applied pose correction.
- **Sit is a pivot, not a pose.** Geometry lives on a child node named
  `sit-mesh`; `applyPivot` sets the wrapper pivot to bbox XZ-center and
  Y = lowest vertex (floor) or bbox center (airborne pins,
  `y >= 0.15` via the `mesquette.attachCenter` node value). Swapping a
  partial/final mesh refreshes the pivot and preserves wrapper position,
  rotation, and scale.
- **Vertex colors are the only texture.** Meshes carry an optional `RGBA`
  vertex channel (`Float` ×4/vertex). SceneKit shades it natively
  (`SCNGeometrySource` `.color`). RealityKit cannot, so
  `ShapEMeshAdapter` bakes per-triangle colors into a texture atlas
  (non-indexed expansion, 2×2 block per triangle) — vertex counts and
  texture memory explode accordingly; partial meshes skip colors.
- **All face indices pass `MeshExporter.validatedFaceIndices`** (shared by
  export and the visionOS adapter): exact `UInt32` conversion, rejects
  negatives/overflow/non-triples/out-of-range. Faces arrive as Int32 or
  Int64 tensors — any other dtype is an error, never a guess.
- **Export is format-by-extension, data-only** (`MeshExporter.export`):
  `.obj` → OBJ + companion MTL, `.usdz` → ModelIO `MDLAsset`. OBJ colors
  are lossy by design: only the average albedo lands in the MTL `Kd`;
  USDZ keeps per-vertex RGB via MDL color attribute. Share/save of OBJ
  must go through `packageWavefrontExport` (store-only ZIP of OBJ+MTL).
- **Exports use the raw mesh**, not table placement: no pin offset, scale,
  or sit is baked in. Placement lives on the record.

## Key Design Decisions

- **Custom camera rig instead of `allowsCameraControl`.**
  `StudioCameraRig` (orbit/top/walk) exists because SceneKit's turntable
  pins its target at the origin and loses pitch near the pole. The rig is
  a pure `nonisolated` value type; `SceneKitStudio.apply` is the only
  place it touches `SCNNode`s, which is what makes it unit-testable.
- **Signature-driven scene sync.** Preview hosts hash records+pins
  (`sceneSignature`) and rebuild/sync nodes only on change; pin markers
  are diffed by `pinID`. Rebuilding SceneKit geometry per SwiftUI update
  was the failure mode this avoids.
- **visionOS mirrors, doesn't re-plan.** `ImmersiveViewModel.sync` stages
  records onto the glass table with the same feet-vs-center rule
  (`plantedPosition`) and re-reads `AppModel` if a sync is requested
  mid-sync (`needsResync` loop) instead of dropping updates.
- **Shading modes are material-only**: flat = derivative-normal shader
  modifier, wireframe = `fillMode .lines`. Geometry is never rebuilt to
  change shading.

## Concurrency, Memory & Platform Constraints

- SceneKit/RealityKit work happens on the main actor via SwiftUI update
  cycles; `StudioCameraRig` math is `nonisolated` so tests/harnesses can
  call it anywhere.
- Geometry buffers are built from tensor `Data` in place on macOS/iOS
  (no per-vertex copy); the visionOS bake allocates ~3× expanded verts
  plus texture — the memory ceiling for large meshes is visionOS.
- `MeshExporter` is a `nonisolated` pure-data path (safe off-main), but
  it still materializes full `[Float]`/`[UInt32]` arrays; don't call it
  per-frame or on partials.
- Camera specifics differ per shell only in input plumbing (drag, scroll,
  gestures in the preview hosts); framing math (`frame`, `worldBounds`
  over all 8 bbox corners) is shared. Floor sits at y = −0.01 to avoid
  z-fighting with grounded meshes.

## Known Gotchas / Do Not Break

- Removing the `sit-mesh` child or writing geometry onto the wrapper
  breaks lock-drag rotation and partial-mesh swaps simultaneously.
- `apply(_:to:SCNView)` silently no-ops if the camera node isn't in the
  scene yet (`cameraInScene`); install order (`install(in:)` before
  first frame) matters.
- RealityKit color bake's fourth texel (`c1+c2−c0`) is load-bearing for
  bilinear barycentric interpolation — "simplifying" it to an average
  visibly shifts colors. UV-atlas-by-vertex-index was the previous bug.
- `UTType.usdz` must not be redeclared (infinite recursion is documented
  in `MeshExportFormat.contentType`); OBJ has no system type and uses a
  filename-extension fallback.
- USDZ export depends on ModelIO's USD exporter being registered in the
  process — true inside the app, false in bare CLI tools
  (`canExportFileExtension("usdz") == false` there). Don't debug USDZ
  from a command-line harness.
- Walk mode keeps the eye when leaving orbit (`adoptView`); top view
  snaps pitch to 86° without moving the pivot. Both are tested —
  changing rig math without updating `StudioCameraTests` will drift.

## Verification

- `StudioCameraTests` — home/top/walk pitch clamps, no flip past zenith,
  frame-centers-pivot, eye-height walk framing (pure math, no GPU).
- `MeshExporterTests` — index validation matrix (negative/overflow/
  non-triple/past-end) and OBJ+MTL ZIP packaging incl. missing-MTL error.
- No automated coverage for: SceneKit node sync, the RealityKit bake,
  immersive staging, shading modes, or USDZ output. Those are verified
  manually in-app; macOS build is the only gate that runs today, and the
  test target itself is visionOS-only/blocked (see AGENTS Verify).
