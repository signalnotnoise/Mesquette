# ML & Assets

Model loading, weights provenance, and image preparation for both backends.
Pipeline/stage topology: [`docs/knowledge-graph.md`](../knowledge-graph.md) §9;
upstream runtime behavior belongs to apple-mlx-foundations, not this repo.

## Purpose & Boundary

- Owns: getting verified weights on disk, constructing runtimes exactly
  once, GPU-stream lifecycle, and turning user images into each backend's
  expected input (`ShapERuntimeStore`, `TripoSRStore`, `HFBundleDownloader`,
  `RuntimeAssetLocator`, `ImageBackgroundRemoval`).
- Does not own: sampling math or mesh extraction (vendored
  `ShapERuntime`/`TripoSRRuntime` — never patch them here; move the
  submodule pin), prompt planning (Director), or rendering (3D & Export).
- Two backends, two stores, one shared contract: callers get a ready
  runtime or a thrown error; loads are cached, failures are not.
- Platform split is only in *delivery*: Background Assets is the signed
  Release path on all platforms; HF download is the universal fallback
  (and the only path in unsigned/dev builds). iOS additionally refuses
  generation unless the app is active (enforced in `ContentViewModel`).

## Core Contracts & Invariants

- **Resolution order is fixed** (`RuntimeAssetLocator.resolve`):
  bundled `runtime_bundle` → Background Assets → HF cache. The bundled
  branch is legacy engineering builds only; products never ship it
  (Release sets `EXCLUDED_SOURCE_FILE_NAMES = runtime_bundle`).
- **Weights are pinned and verified, or they don't load.** Shap-E:
  `signalNotNoise/shap-e-mlx @ d71f70a…`; TripoSR:
  `signalNotNoise/triposr-mlx @ 17a0c52…`, file
  `triposr_swift_ready.safetensors` only (the `triposr_mlx.safetensors`
  intermediate is never loaded). Every payload file is SHA-256 checked
  against the published `checksums.sha256` (TripoSR also against a
  compiled-in digest) before a `.mesquette-verified-<revision>` stamp
  allows offline reuse. Fail closed: mismatch/missing throws.
- **Scopes are real downloads, not flags.** Shap-E text scope excludes
  `clip_vision`/`image300m` (~2.3 GB); `prepareImageWeights()` resolving
  `.full` is what makes image generation legal. A `.full` stamp satisfies
  `.text`, never the reverse (`scope(_:satisfies:)`).
- **Background Assets traps without a team ID.** `AssetPackManager`
  fatal-errors (does not throw) in ad-hoc builds, so the hosted attempt is
  gated by `hasTeamIdentifier` (SecCode signing info). A do/catch around
  BA is not sufficient protection — keep the gate in front of *every* BA
  touch. Pack layout: `shap-e-text` essential, `shap-e-image` prefetch;
  the extension (`AssetDownloader`) approves all packs.
- **BPE vocab is special**: `bpe_simple_vocab_16e6.txt.gz` ships as an app
  resource (committed, 1.3 MB) because the BA packs don't carry it; the
  HF snapshot root copy is only a fallback for resource-less builds.
- **Downloads are sequential per file today** (`HubApi.snapshot` loops
  files). Bundle = ~1,100 small tensors, so first launch is minutes, not
  a bug. Any parallel downloader must keep pin + verify + stamp semantics.

## Key Design Decisions

- **Stores are actors with epoch-guarded load tasks**
  (`ShapERuntimeStore`, mirrored by `TripoSRStore`): concurrent first
  calls share one load; a failed waiter clears `loadTask` only if its
  epoch is still current, so retry-after-failure always works and a stale
  failure can't cancel a newer attempt. Successful loads are cached for
  process lifetime (weights are GBs; there is no unload API by design).
- **Shap-E stays on the direct runtime; TripoSR goes through the facade.**
  The facade's `generate` lacks guidance/steps/seed/batch/partials that
  Shap-E UI exposes, so `ContentViewModel` uses `ShapERuntime` directly
  and `ThreeDGenerationRuntime` only for `.tripoSR`.
- **Image prep is backend-specific and not interchangeable.**
  Shap-E: app composites the Vision cutout over **white**, runtime does
  CLIP `Resize(224)`+center-crop and drops alpha. TripoSR:
  `foregroundCutout` (transparent, bbox crop, 0.85 square pad — upstream
  `resize_foreground`) and the runtime composites over gray 128. Feeding
  either backend the other's preparation produces slabs or washed input.
- **Cache location is `Caches/huggingface`** (materialized snapshot under
  `models/<repoID>`), deliberately purgeable: the OS may evict it, and
  the next launch simply re-downloads. Do not move weights to Documents.

## Concurrency, Memory & Platform Constraints

- **Metal stream must be born in the foreground.** `MLXForegroundGPU`
  binds MLX on the main thread after the scene is active (plus 80 ms
  settle on iOS/visionOS); creating it during launch/background makes
  IOGPU reject later command buffers. `prepareForGPUWork()` precedes
  every generation for this reason — don't remove it as "redundant".
- `RuntimeLaunchContext.isXcodePreview` (env vars, XCTest config, bundle
  path) hard-disables all MLX work; PreviewShell otherwise SIGABRTs.
- MLX buffer-pool caps are set once at load: iOS 256 MB, visionOS 512 MB,
  macOS uncapped. `cacheLimit` is *not* weights memory (~2.5 GB active
  for Shap-E text; TripoSR file alone is 1.67 GB) — shrinking it does not
  prevent jetsam, it forces per-layer reallocations.
- TripoSR's facade `generate` is synchronous CPU/GPU work inside an async
  wrapper; it must remain inside `withMLXError` (@concurrent) at call
  sites or the main actor freezes for the whole extraction.
- Vision masks are one-component **Float32** (`L00f`) on current OSes,
  UInt8 (`L008`) historically. Any new mask reader must switch on
  `CVPixelBufferGetPixelFormatType` (see `maskBounds`).

## Known Gotchas / Do Not Break

- `waitUntilLoadFinishes()` swallows load errors on purpose (splash must
  dismiss); Generate is the only place the real failure surfaces.
- Stamp trust is existence-only after first verification; a corrupted
  cache file post-stamp will not be re-hashed until the stamp/scope
  changes. Deleting the stamp forces a full re-verify.
- `prepareImageWeights()` resolving `.full` does not retro-load image
  weights into an already-created `ShapERuntime` — ordering vs first
  image generate matters; keep the call before image generation.
- `scripts/package-asset-packs.sh` refuses to package an unverified
  `runtime_bundle/`; stage it with `scripts/fetch-weights.sh`. Its
  `.env` sourcing is strict shell — multi-line pasted keys break it.
- `AssetPackManager.url(for:)` results must not be persisted across
  launches (system may relocate pack storage).

## Verification

- `HFBundleDownloaderTests` — pins/digests, scope globs, checksum
  parse/filter, fail-closed verify. `ImageBackgroundRemovalTests` —
  alpha bounds + 0.85 canvas math. `ModelSelectionTests` — picker gating.
- Runtime suites live upstream (`ShapERuntimeTests`, TripoSR parity in
  foundations); Mesquette-side evidence is build + through-app runs.
- Cannot verify here today: signed Background Assets download (needs
  team-signed build + uploaded packs or `ba-serve`), and the unit tests
  themselves (visionOS-only target, see AGENTS Verify).
