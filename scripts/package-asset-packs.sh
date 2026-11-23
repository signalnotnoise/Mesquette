#!/bin/zsh
set -euo pipefail

# Package Shap-E weights for Apple-Hosted Background Assets, and optionally
# upload the .aar archives to App Store Connect with altool.
#
#   ./scripts/package-asset-packs.sh              # package only
#   ./scripts/package-asset-packs.sh --clean      # remove dist/
#   ./scripts/package-asset-packs.sh --upload     # package + upload
#   ./scripts/package-asset-packs.sh --upload-only
#
# Upload auth (first match wins):
#   1. App Store Connect API key
#        ASC_API_KEY, ASC_API_ISSUER
#        optional: ASC_P8_PATH  (otherwise AuthKey_<ASC_API_KEY>.p8 is searched
#        in ./private_keys, ~/private_keys, ~/.private_keys,
#        ~/.appstoreconnect/private_keys, $API_PRIVATE_KEYS_DIR)
#   2. Apple ID + app-specific password
#        ASC_USERNAME
#        ASC_PASSWORD_KEYCHAIN  (keychain item name)  or  ASC_PASSWORD
#
# Required for upload:
#   ASC_APP_APPLE_ID  — numeric Apple ID from
#     App Store Connect → Mesquette → App Information → Apple ID
#
# You can also put those variables in scripts/asset-pack-upload.env (gitignored).
#
# Local testing (optional, no App Store Connect):
#   xcrun ba-serve serve --pack dist/asset-packs/shap-e-text.aar \
#     --pack dist/asset-packs/shap-e-image.aar
#   xcrun ba-serve url-override set <printed-url>

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist/asset-packs"
BUNDLE_ID="com.visionarydevops.Mesquette"
PACKS=(shap-e-text shap-e-image)

DO_CLEAN=0
DO_PACKAGE=1
DO_UPLOAD=0
APPLE_ID="${ASC_APP_APPLE_ID:-}"

ENV_FILE="$ROOT/scripts/asset-pack-upload.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  APPLE_ID="${ASC_APP_APPLE_ID:-$APPLE_ID}"
fi

usage() {
  cat <<'EOF'
Usage: ./scripts/package-asset-packs.sh [--clean] [--upload | --upload-only] [--apple-id ID]

  --clean         Remove dist/
  --upload        Package, then upload .aar files with altool
  --upload-only   Upload existing dist/asset-packs/*.aar (skip ba-package)
  --apple-id ID   App Store Connect numeric Apple ID (or set ASC_APP_APPLE_ID)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean) DO_CLEAN=1; shift ;;
    --upload) DO_UPLOAD=1; shift ;;
    --upload-only) DO_PACKAGE=0; DO_UPLOAD=1; shift ;;
    --apple-id)
      [[ $# -ge 2 ]] || { usage; exit 1; }
      APPLE_ID="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

altool_auth=()
collect_altool_auth() {
  if [[ -n "${ASC_API_KEY:-}" && -n "${ASC_API_ISSUER:-}" ]]; then
    altool_auth=(--api-key "$ASC_API_KEY" --api-issuer "$ASC_API_ISSUER")
    if [[ -n "${ASC_P8_PATH:-}" ]]; then
      altool_auth+=(--p8-file-path "$ASC_P8_PATH")
    fi
    return 0
  fi
  if [[ -n "${ASC_USERNAME:-}" ]]; then
    altool_auth=(-u "$ASC_USERNAME")
    if [[ -n "${ASC_PASSWORD_KEYCHAIN:-}" ]]; then
      altool_auth+=(-p "@keychain:${ASC_PASSWORD_KEYCHAIN}")
    elif [[ -n "${ASC_PASSWORD:-}" ]]; then
      altool_auth+=(-p "@env:ASC_PASSWORD")
    fi
    return 0
  fi
  echo "Upload needs App Store Connect credentials." >&2
  echo "Set ASC_API_KEY + ASC_API_ISSUER (preferred), or ASC_USERNAME" >&2
  echo "plus ASC_PASSWORD_KEYCHAIN / ASC_PASSWORD." >&2
  echo "See scripts/asset-pack-upload.env.example." >&2
  exit 1
}

verify_bundle() {
  # Canonical payload: public Hub bundle fetched by scripts/fetch-weights.sh
  # (signalNotNoise/shap-e-mlx @ d71f70a, v0.1.0). Refuse to package weights
  # whose provenance cannot be checksum-verified.
  local sums="$ROOT/runtime_bundle/checksums.sha256"
  if [[ ! -f "$sums" ]]; then
    echo "runtime_bundle/checksums.sha256 missing — run ./scripts/fetch-weights.sh first." >&2
    exit 1
  fi
  echo "Verifying runtime_bundle against published checksums…"
  ( cd "$ROOT/runtime_bundle" \
    && /usr/bin/grep -E '  (manifest\.json|(clip_text|text300m|diffusion|decoder_params|renderer|clip_vision|image300m)/)' \
         checksums.sha256 | shasum -a 256 --check --quiet )
  echo "Bundle verified."
}

package_packs() {
  verify_bundle
  mkdir -p "$OUT"
  cd "$ROOT"
  echo "Packaging shap-e-text (essential)…"
  xcrun ba-package package "$ROOT/AssetPacks/shap-e-text.json" \
    --output-path "$OUT/shap-e-text.aar"
  echo "Packaging shap-e-image (prefetch)…"
  xcrun ba-package package "$ROOT/AssetPacks/shap-e-image.json" \
    --output-path "$OUT/shap-e-image.aar"
}

upload_packs() {
  if [[ -z "$APPLE_ID" ]]; then
    echo "Upload needs the numeric App Store Connect Apple ID for ${BUNDLE_ID}." >&2
    echo "App Store Connect → Mesquette → App Information → Apple ID" >&2
    echo "Then:  --apple-id 1234567890   or   ASC_APP_APPLE_ID=1234567890" >&2
    exit 1
  fi
  collect_altool_auth
  for pack in "${PACKS[@]}"; do
    local aar="$OUT/${pack}.aar"
    if [[ ! -f "$aar" ]]; then
      echo "Missing $aar — package first or drop --upload-only." >&2
      exit 1
    fi
    echo "Uploading ${pack}.aar ($(du -h "$aar" | awk '{print $1}')) to Apple ID ${APPLE_ID}…"
    xcrun altool --upload-asset-pack "$aar" \
      --apple-id "$APPLE_ID" \
      "${altool_auth[@]}"
  done
  echo
  echo "Upload accepted. Apple emails when processing finishes."
  echo "Then: App Store Connect → Mesquette → General → Asset Packs"
}

if (( DO_CLEAN && !DO_PACKAGE && DO_UPLOAD )); then
  echo "--clean --upload-only removes the archives that upload-only needs. Use --clean --upload." >&2
  exit 1
fi

if (( DO_CLEAN )); then
  if [[ -d "$ROOT/dist" ]]; then
    rm -rf "$ROOT/dist"
    echo "Removed $ROOT/dist"
  else
    echo "No dist/ to remove."
  fi
  # --clean by itself only deletes; combine with --upload to rebuild and deliver.
  if (( !DO_UPLOAD )); then
    exit 0
  fi
fi

if (( DO_PACKAGE )); then
  package_packs
  echo "Wrote:"
  ls -lh "$OUT"/*.aar
  echo
fi

if (( DO_UPLOAD )); then
  upload_packs
else
  echo "Next: ./scripts/package-asset-packs.sh --upload"
  echo "  or drop the .aar files on Transporter."
  echo "Debug builds still embed runtime_bundle locally and skip the download."
fi
