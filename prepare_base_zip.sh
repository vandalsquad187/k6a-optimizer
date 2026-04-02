#!/bin/bash
# prepare_base_zip.sh
# Run this once locally to create module/BadazZ89_k6a_Optimizer_base.zip
# This zip contains everything EXCEPT the Rust binary.
# GitHub Actions downloads it and adds the compiled binary.

set -e
cd "$(dirname "$0")"

echo "📦 Preparing base module zip..."

STAGING="/tmp/k6a_base_staging"
OUT="module/BadazZ89_k6a_Optimizer_base.zip"

rm -rf "$STAGING"
mkdir -p "$STAGING/webroot"
mkdir -p "$STAGING/bin"
mkdir -p "$STAGING/config"
mkdir -p "$STAGING/run"
mkdir -p "$STAGING/icon"
mkdir -p "$STAGING/META-INF/com/google/android"

# Copy module files
cp module/module.prop   "$STAGING/module.prop"
cp module/service.sh    "$STAGING/service.sh"
cp module/system.prop   "$STAGING/system.prop"
cp module/index.html    "$STAGING/webroot/index.html"

# Copy icon if present
[ -f module/icon.png ] && cp module/icon.png "$STAGING/icon/icon.png"

# META-INF
echo "#MAGISK" > "$STAGING/META-INF/com/google/android/updater-script"
[ -f module/update-binary ] && \
    cp module/update-binary "$STAGING/META-INF/com/google/android/update-binary"

cd "$STAGING"
zip -r "$(pwd)/../../../$OUT" . -x "*.DS_Store"

echo "✅ Base zip created: $OUT"
ls -lh "$(pwd)/../../../$OUT"
