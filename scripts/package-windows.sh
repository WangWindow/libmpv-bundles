#!/usr/bin/env bash
# Package the official LGPL libmpv Windows release into the runtime layout
# consumed by AvaStudio (libmpv-2.dll at the archive root).
set -euo pipefail

MPV_TAG="${MPV_TAG:?MPV_TAG is required, for example v0.42.0}"
RID="${RID:?RID is required: win-x64 or win-arm64}"
TARGET="${TARGET:?TARGET is required: x86_64 or aarch64}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-$ROOT/.work/$RID}"
DIST="${DIST:-$ROOT/dist}"
BUNDLE="$WORK/bundle"
ASSET="libmpv-${MPV_TAG}-${TARGET}-w64-mingw32-lgpl.zip"

rm -rf "$WORK" "$BUNDLE"
mkdir -p "$WORK/download" "$BUNDLE" "$DIST"

if [ -n "${ASSET_PATH:-}" ]; then
    cp "$ASSET_PATH" "$WORK/download/$ASSET"
else
    gh release download "$MPV_TAG" \
        --repo mpv-player/mpv \
        --pattern "$ASSET" \
        --dir "$WORK/download"
fi

unzip -q "$WORK/download/$ASSET" -d "$WORK/extract"

if [ ! -f "$WORK/extract/libmpv-2.dll" ]; then
    echo "libmpv-2.dll is missing from $ASSET" >&2
    find "$WORK/extract" -maxdepth 2 -type f | sort
    exit 1
fi

case "$RID" in
    win-x64) expected='x86-64' ;;
    win-arm64) expected='ARM64' ;;
    *)
        echo "Unsupported RID: $RID" >&2
        exit 1
        ;;
esac

file "$WORK/extract/libmpv-2.dll" | grep -q "$expected" || {
    file "$WORK/extract/libmpv-2.dll"
    echo "Unexpected DLL architecture; expected $expected" >&2
    exit 1
}

cp "$WORK/extract/libmpv-2.dll" "$BUNDLE/"
cp "$WORK/extract/LICENSE.LGPL" "$BUNDLE/"

cat > "$BUNDLE/SOURCE.txt" <<EOF
LGPL libmpv runtime bundle

mpv:    $MPV_TAG (LGPL build)
Source: https://github.com/mpv-player/mpv/releases/tag/$MPV_TAG
Asset:  $ASSET

This is a repack of the official LGPL libmpv Windows build. Only
libmpv-2.dll is required at runtime; its remaining imports are Windows
system DLLs.
EOF

output="$DIST/libmpv-$RID.zip"
rm -f "$output"
(cd "$BUNDLE" && zip -qr "$output" .)

echo "Created $output"
unzip -l "$output"
