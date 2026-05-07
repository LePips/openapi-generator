#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: Scripts/artifactbundle.sh <version>" >&2
  exit 1
fi

VERSION="$1"
PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ROOT="${OPENAPI_GENERATOR_ARTIFACT_OUTPUT_ROOT:-$PACKAGE_ROOT/.build/artifactbundle}"
ARTIFACT_NAME="openapi-generator"
BUNDLE_NAME="openapi-generator_OpenAPIGeneratorCore.bundle"
TRIPLE="arm64-apple-macosx"
VARIANT="openapi-generator-macos-arm64"

cd "$PACKAGE_ROOT"

swift build -c release --product openapi-generator --arch arm64
BIN_DIR="$(swift build -c release --show-bin-path --arch arm64)"

if [[ ! -x "$BIN_DIR/openapi-generator" ]]; then
  echo "error: release executable not found at $BIN_DIR/openapi-generator" >&2
  exit 1
fi

if [[ ! -d "$BIN_DIR/$BUNDLE_NAME" ]]; then
  echo "error: resource bundle not found at $BIN_DIR/$BUNDLE_NAME" >&2
  exit 1
fi

rm -rf "$OUTPUT_ROOT"
mkdir -p "$OUTPUT_ROOT/$ARTIFACT_NAME.artifactbundle/$VARIANT/bin"

cp "$BIN_DIR/openapi-generator" \
  "$OUTPUT_ROOT/$ARTIFACT_NAME.artifactbundle/$VARIANT/bin/openapi-generator"
cp -R "$BIN_DIR/$BUNDLE_NAME" \
  "$OUTPUT_ROOT/$ARTIFACT_NAME.artifactbundle/$VARIANT/bin/$BUNDLE_NAME"

cat > "$OUTPUT_ROOT/$ARTIFACT_NAME.artifactbundle/info.json" <<JSON
{
  "schemaVersion": "1.0",
  "artifacts": {
    "$ARTIFACT_NAME": {
      "type": "executable",
      "version": "$VERSION",
      "variants": [
        {
          "path": "$VARIANT/bin/openapi-generator",
          "supportedTriples": ["$TRIPLE"]
        }
      ]
    }
  }
}
JSON

if [[ ! -x "$OUTPUT_ROOT/$ARTIFACT_NAME.artifactbundle/$VARIANT/bin/openapi-generator" ]]; then
  echo "error: artifact executable was not created" >&2
  exit 1
fi

if [[ ! -d "$OUTPUT_ROOT/$ARTIFACT_NAME.artifactbundle/$VARIANT/bin/$BUNDLE_NAME" ]]; then
  echo "error: artifact resource bundle was not created" >&2
  exit 1
fi

"$OUTPUT_ROOT/$ARTIFACT_NAME.artifactbundle/$VARIANT/bin/openapi-generator" --help >/dev/null

(
  cd "$OUTPUT_ROOT"
  /usr/bin/zip -r -q "$ARTIFACT_NAME.artifactbundle.zip" "$ARTIFACT_NAME.artifactbundle"
)

CHECKSUM="$(swift package compute-checksum "$OUTPUT_ROOT/$ARTIFACT_NAME.artifactbundle.zip")"

cat <<EOF
Artifact bundle:
  $OUTPUT_ROOT/$ARTIFACT_NAME.artifactbundle

Zip:
  $OUTPUT_ROOT/$ARTIFACT_NAME.artifactbundle.zip

Checksum:
  $CHECKSUM
EOF
