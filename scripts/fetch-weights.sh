#!/bin/zsh
set -euo pipefail

# Stage the published Shap-E bundle into runtime_bundle/ for asset-pack
# packaging (scripts/package-asset-packs.sh). Normal builds do NOT need
# this: the app downloads the same pinned bundle on first launch via
# HFBundleDownloader. Also populates bpe_simple_vocab_16e6.txt.gz.
#
#   ./scripts/fetch-weights.sh              # full bundle (text + image)
#   ./scripts/fetch-weights.sh --text-only  # skip image families (~2.3 GB)
#
# Requires the Hugging Face CLI (https://hf.co/cli): `hf` on PATH.
# Weights are OpenAI Shap-E/CLIP tensors converted for MLX (MIT; see
# THIRD_PARTY_NOTICES.md). They are gitignored and never committed.

REPO_ID="signalNotNoise/shap-e-mlx"
REVISION="d71f70a09b9c03535188d006a719edda5c19a6eb"  # v0.1.0
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGING="$ROOT/.weights-fetch"
TEXT_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --text-only) TEXT_ONLY=1 ;;
    -h|--help) sed -n '3,13p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

command -v hf >/dev/null || {
  echo "Missing 'hf' (Hugging Face CLI). Install: curl -LsSf https://hf.co/cli/install.sh | bash -s" >&2
  exit 1
}

TEXT_FAMILIES=(clip_text text300m diffusion decoder_params renderer)
IMAGE_FAMILIES=(clip_vision image300m)
if (( TEXT_ONLY )); then FAMILIES=($TEXT_FAMILIES); else FAMILIES=($TEXT_FAMILIES $IMAGE_FAMILIES); fi

INCLUDE=(manifest.json bpe_simple_vocab_16e6.txt.gz checksums.sha256 provenance.json LICENSE)
for fam in $FAMILIES; do INCLUDE+=("$fam/*.bin"); done

echo "Downloading $REPO_ID @ $REVISION ${TEXT_ONLY:+(text-only)}..."
rm -rf "$STAGING"
mkdir -p "$STAGING"
ARGS=()
for pat in $INCLUDE; do ARGS+=(--include "$pat"); done
hf download "$REPO_ID" --revision "$REVISION" \
  $ARGS --local-dir "$STAGING" --format quiet

echo "Verifying checksums..."
(
  cd "$STAGING"
  # checksums.sha256 covers the whole Hub repo; keep only fetched scope.
  /usr/bin/grep -E "  (manifest\.json|bpe_simple_vocab_16e6\.txt\.gz|provenance\.json|LICENSE|(${FAMILIES[*]// /|})/)" \
    checksums.sha256 > checksums.fetched
  shasum -a 256 --check --quiet checksums.fetched
)
echo "Checksums OK."

mkdir -p "$ROOT/runtime_bundle"
for fam in $FAMILIES; do
  rm -rf "$ROOT/runtime_bundle/$fam"
  mv "$STAGING/$fam" "$ROOT/runtime_bundle/$fam"
done
mv "$STAGING/manifest.json" "$ROOT/runtime_bundle/manifest.json"
mv "$STAGING/bpe_simple_vocab_16e6.txt.gz" "$ROOT/bpe_simple_vocab_16e6.txt.gz"
cp "$STAGING/checksums.sha256" "$STAGING/provenance.json" "$ROOT/runtime_bundle/"
rm -rf "$STAGING"

echo "Populated runtime_bundle/ (${FAMILIES[*]}) and bpe_simple_vocab_16e6.txt.gz"
echo "Source: https://huggingface.co/$REPO_ID/tree/$REVISION"
