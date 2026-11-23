# Mesquette

On-device 3D ideation for Apple platforms. Describe a scene (or drop a
photo), Apple Foundation Models split it into named objects, and Shap-E
(`text300m`, running locally via MLX) sculpts one mesh per object — placed
where you dropped pins on a virtual table. No cloud, no API keys, no
per-generation cost.

Mac is the primary UI; iPhone, iPad, and visionOS shells share the same
generation core. Export results as USDZ or OBJ+MTL.

Two generation backends, selectable in the Mac create panel:
**Shap-E** (text or image; powers pin scenes) and **TripoSR**
(image-to-3D only, cleaner geometry; weights download on first use
from `signalNotNoise/triposr-mlx`, checksum-verified).

> Set expectations: Shap-E produces soft, blobby drafts, not production
> assets. Mesquette is a private, offline sketchbook for 3D ideas — the
> pin-based scene staging is the point, not mesh fidelity.

## Requirements

- Apple Silicon Mac (building) / Apple Silicon device (running)
- macOS 26+, iOS 26.2+, or visionOS 26.2+
- Recent Xcode (developed against Xcode 27 beta; Foundation Models
  `.contentTagging` requires the latest SDKs)
- ~5 GB free disk for model weights

## Getting the code

Mesquette depends on the `ShapERuntime` Swift package from
[apple-mlx-foundations](https://github.com/signalnotnoise/apple-mlx-foundations),
vendored as a git submodule at `Vendor/apple-mlx-foundations` and pinned
to **v0.1.0** (`018215715177943fe72cea8e540bc7b80dcb593f`). Xcode
references it as a local package at
`Vendor/apple-mlx-foundations/shap_e/swift`.

```sh
git clone --recurse-submodules https://github.com/signalnotnoise/Mesquette.git
```

## Model weights (not in git, not in the app)

Weights are OpenAI's Shap-E + CLIP tensors converted for MLX (MIT, see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)), published at
[signalNotNoise/shap-e-mlx](https://huggingface.co/signalNotNoise/shap-e-mlx)
**v0.1.0** (revision `d71f70a09b9c03535188d006a719edda5c19a6eb`).
You don't fetch them manually. Resolution order at runtime
(`RuntimeAssetLocator`):

1. a `runtime_bundle` copied into the app (legacy engineering builds),
2. Apple-hosted Background Assets packs (Release; signed builds only),
3. the pinned Hugging Face bundle, snapshot-downloaded on first launch
   into `Caches/huggingface` by `HFBundleDownloader` and SHA-256
   verified against the published `checksums.sha256` (text weights
   first, image weights on first image generation; verified snapshots
   are reused offline).

So a fresh clone builds immediately (~88 MB app) and the first launch
downloads the model. `./scripts/fetch-weights.sh` still exists, but
only to stage `runtime_bundle/` when packaging Background Assets
(`scripts/package-asset-packs.sh`).

Debug builds read weights from `runtime_bundle/`; Release builds deliver
them through Apple-hosted Background Assets (`AssetPacks/` +
`AssetDownloader/`).

## Build

```sh
xcodebuild -scheme Mesquette -destination 'platform=macOS,arch=arm64' build
```

Or open `Mesquette.xcodeproj` in Xcode and run the `Mesquette` scheme.
You will need your own development team selected for signing (App Groups
and Background Assets require it).

## How it works

| Layer | Owns |
|---|---|
| Pins + code | Where meshes sit (x, y, z), empty vs filled |
| Foundation Models | Named objects, floor vs airborne, leftover extras |
| Shap-E (`ShapERuntime`) | Geometry + vertex colors |
| Viewport | Camera, drag, pin clicks |

The architecture, invariants, and generation flows are documented in
[docs/knowledge-graph.md](docs/knowledge-graph.md) (machine copy:
`docs/knowledge-graph.json`). If you change Swift code, update the graph
and run `scripts/check-knowledge-graph.sh` — see [AGENTS.md](AGENTS.md).

## Tests

Planner/layout tests live in `MesquetteTests/`. Note: the test target is
currently visionOS-only and does not compile on the latest visionOS SDK;
the verified path is the macOS build above.

## License

MIT © signalnotnoise — see [LICENSE](LICENSE). Model weights and other
third-party components keep their original licenses — see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

This is a personal project shared as-is; issues and PRs are welcome but
support is best-effort.
