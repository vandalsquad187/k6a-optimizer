#!/bin/bash
# prepare_base_zip.sh
# Run this once locally to create BadazZ89_k6a_Optimizer_base.zip
# This zip contains everything EXCEPT the Rust binary.
# GitHub Actions downloads it and adds the compiled binary.

set -e
cd "$(dirname "$0")"

echo "Preparing base module zip..."

STAGING="/tmp/k6a_base_staging"
OUT="BadazZ89_k6a_Optimizer_base.zip"

rm -rf "$STAGING"
mkdir -p "$STAGING/webroot"
mkdir -p "$STAGING/bin"
mkdir -p "$STAGING/config"
mkdir -p "$STAGING/run"
mkdir -p "$STAGING/icon"
mkdir -p "$STAGING/META-INF/com/google/android"

# Copy all module files
cp module.prop       "$STAGING/module.prop"
cp customize.sh      "$STAGING/customize.sh"
cp service.sh        "$STAGING/service.sh"
cp system.prop       "$STAGING/system.prop"
cp post-fs-data.sh   "$STAGING/post-fs-data.sh"
cp boot-completed.sh "$STAGING/boot-completed.sh"

# Config
cp config/settings.conf  "$STAGING/config/settings.conf"
cp config/freeze.conf    "$STAGING/config/freeze.conf"
cp config/manual_profile "$STAGING/config/manual_profile"

# Binaries (without k6a-daemon — built in CI)
cp bin/k6a-controller  "$STAGING/bin/k6a-controller"
cp bin/k6a-lib.sh      "$STAGING/bin/k6a-lib.sh"
cp bin/k6a-diagnose.sh "$STAGING/bin/k6a-diagnose.sh"

# Webroot
cp webroot/index.html "$STAGING/webroot/index.html"
cp webroot/ascii.txt  "$STAGING/webroot/ascii.txt"

# Icon
[ -f icon/icon.png ] && cp icon/icon.png "$STAGING/icon/icon.png"

# META-INF
echo "#MAGISK" > "$STAGING/META-INF/com/google/android/updater-script"

cd "$STAGING"
zip -r "$(pwd)/../../../$OUT" . -x "*.DS_Store"

echo "Base zip created: $OUT"
ls -lh "$(pwd)/../../../$OUT"
