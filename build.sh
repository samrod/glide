#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SDK=$(xcrun --sdk macosx --show-sdk-path)
APP="$ROOT/Glide.app"
RESOURCES="$ROOT/resources"
ICON_SOURCE="$RESOURCES/glide-icon.png"
ICONSET_TMP=$(mktemp -d "${TMPDIR:-/tmp}/glide-iconset.XXXXXX")
trap 'rm -rf "$ICONSET_TMP"' EXIT HUP INT TERM

if [ ! -f "$ICON_SOURCE" ]; then
  echo "Missing icon source: $ICON_SOURCE" >&2
  exit 1
fi

mkdir -p "$RESOURCES"
for size in 16 32 48 128 256 512 1024; do
  sips -s format png -z "$size" "$size" "$ICON_SOURCE" \
    --out "$ICONSET_TMP/icon_${size}x${size}.png" >/dev/null
done

python3 - "$ICONSET_TMP" "$RESOURCES/Glide.icns" <<'PY'
import os
import struct
import sys

iconset, output = sys.argv[1:]
representations = (
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_48x48.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_1024x1024.png"),
)
chunks = []
for chunk_type, filename in representations:
    with open(os.path.join(iconset, filename), "rb") as image:
        payload = image.read()
    chunks.append(chunk_type.encode("ascii") + struct.pack(">I", len(payload) + 8) + payload)
body = b"".join(chunks)
temporary = output + ".tmp"
with open(temporary, "wb") as icon_file:
    icon_file.write(b"icns" + struct.pack(">I", len(body) + 8) + body)
os.replace(temporary, output)
PY

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$RESOURCES/Glide.icns" "$APP/Contents/Resources/Glide.icns"
clang -fno-objc-arc -arch x86_64 -isysroot "$SDK" \
  -mmacosx-version-min=10.6 "$ROOT/src/Glide.m" \
  "$ROOT/src/GlidePreferencesController.m" "$ROOT/src/GlideSettings.m" \
  "$ROOT/src/GlideLoginItems.m" \
  -framework AppKit -framework ApplicationServices -framework CoreGraphics -framework IOKit -framework CoreServices \
  -o "$APP/Contents/MacOS/Glide"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/../Glide-for-Mountain-Lion.zip"
echo "Built $APP and refreshed the ZIP"
