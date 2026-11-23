# Third-party notices

Mesquette is MIT licensed (see [LICENSE](LICENSE)). It builds on the
following third-party work; model weights are not stored in this repository
and are redistributed under their original licenses.

## Shap-E (model architecture and weights)

Copyright (c) 2023 OpenAI. MIT License.
<https://github.com/openai/shap-e>

Mesquette runs Shap-E `text300m` / `image300m` weights converted for MLX,
published at [signalNotNoise/shap-e-mlx](https://huggingface.co/signalNotNoise/shap-e-mlx)
v0.1.0 (revision `d71f70a09b9c03535188d006a719edda5c19a6eb`). The
conversion is performed by scripts in the companion
[apple-mlx-foundations](https://github.com/signalnotnoise/apple-mlx-foundations)
repository; converted tensors remain OpenAI's weights under the MIT terms
above.

## TripoSR (optional image-to-3D backend)

Copyright (c) 2024 Stability AI and TripoSR contributors. MIT License.
<https://github.com/VAST-AI-Research/TripoSR>

TripoSR weights converted for MLX/Swift are published at
[signalNotNoise/triposr-mlx](https://huggingface.co/signalNotNoise/triposr-mlx)
(revision `17a0c5286e2b2bb6fc9e3654ca31cfc9dc4b2041`); the loaded file is
`triposr_swift_ready.safetensors`. The Swift port lives in the
`signalnotnoise/TripoSR` submodule of apple-mlx-foundations and is
consumed through its `RuntimeWrapper` facade (`ThreeDGenerationRuntime`).

## CLIP ViT-L/14 (text/image embeddings)

Copyright (c) 2021 OpenAI. MIT License.
<https://github.com/openai/CLIP>

## MLX and mlx-swift

Copyright © 2023-2024 Apple Inc. MIT License.
<https://github.com/ml-explore/mlx-swift>

## swift-numerics

Copyright © 2019-2020 Apple Inc. Apache License 2.0.
<https://github.com/apple/swift-numerics>

## ShapERuntime (companion package)

The Swift/MLX Shap-E inference runtime lives in
[apple-mlx-foundations](https://github.com/signalnotnoise/apple-mlx-foundations)
under `shap_e/swift`, MIT licensed by signalnotnoise, vendored here as a
git submodule at `Vendor/apple-mlx-foundations` pinned to v0.1.0
(`018215715177943fe72cea8e540bc7b80dcb593f`). It is a port of OpenAI's
reference implementation (see Shap-E above).
