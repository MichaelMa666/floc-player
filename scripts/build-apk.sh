#!/usr/bin/env bash
set -euo pipefail

# 走你常用的命令；额外的参数可以追加（比如 --build-name=1.0.1）。
flutter build apk --target-platform android-arm64 --release "$@"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=$(awk -F'[: +]' '/^version:/{print $3}' "$ROOT/pubspec.yaml")
SRC="$ROOT/build/app/outputs/flutter-apk/app-release.apk"
DST="$ROOT/build/app/outputs/flutter-apk/floc-player-${VERSION}-arm64-release.apk"

cp "$SRC" "$DST"
echo
echo "✔ $DST"
echo "  ($(du -h "$DST" | cut -f1))"
