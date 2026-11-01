#!/usr/bin/env bash
# Creates the generated Android/Linux shells and applies MawjTVH's platform
# patches. Run this once after cloning, or let CI run it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.8}"
FLUTTER_HOME="${FLUTTER_HOME:-$ROOT/.flutter}"

cd "$ROOT"

if ! command -v flutter >/dev/null 2>&1; then
  if [[ ! -x "$FLUTTER_HOME/bin/flutter" ]]; then
    echo "Flutter was not found; cloning $FLUTTER_VERSION into $FLUTTER_HOME"
    git clone --depth 1 --branch "$FLUTTER_VERSION" \
      https://github.com/flutter/flutter.git "$FLUTTER_HOME"
  fi
  export PATH="$FLUTTER_HOME/bin:$PATH"
fi

echo "Using $(flutter --version | sed -n '1p')"

flutter config --no-analytics >/dev/null
flutter config --enable-linux-desktop >/dev/null

if [[ ! -d "$ROOT/android" || ! -d "$ROOT/linux" ]]; then
  TEMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TEMP_DIR"' EXIT
  echo "Generating platform shells with flutter create"
  flutter create \
    --platforms=android,linux \
    --org com.mmbesar \
    --project-name mawjtvh \
    --no-pub \
    "$TEMP_DIR/mawjtvh" >/dev/null

  for platform in android linux; do
    if [[ ! -d "$ROOT/$platform" ]]; then
      cp -R "$TEMP_DIR/mawjtvh/$platform" "$ROOT/$platform"
      echo "  added $platform/"
    fi
  done
else
  echo "Platform shells already present."
fi

python3 "$ROOT/tool/configure_platforms.py"
flutter pub get
echo "Bootstrap complete."
