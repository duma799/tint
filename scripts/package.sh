#!/bin/sh
# Builds the release files into dist/, universal (Apple silicon + Intel):
#   tint-<version>-macos.tar.gz   the `tint` command
#   Tint-<version>-macos.zip      the app
#
# Needs macOS with Xcode (or its command-line tools).
set -eu

cd "$(dirname "$0")/.."
version=$(sed -n 's/.*tintVersion = "\(.*\)".*/\1/p' Sources/TintCore/Version.swift)
work=".build/package"
rm -rf "$work"
mkdir -p "$work" dist

echo "==> tint $version: building"
swift build -c release --arch arm64 --arch x86_64
bin=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

echo "==> the command"
cp "$bin/tint" "$work/tint"

echo "==> Tint.app"
app="$work/Tint.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/TintApp" "$app/Contents/MacOS/Tint"
sed "s/@VERSION@/$version/g" packaging/Info.plist > "$app/Contents/Info.plist"

iconset="$work/tint.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" assets/icon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" assets/icon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/tint.icns"

# Apple silicon runs only signed code. An ad-hoc signature ("-") is enough
# for that; it's not a Developer ID, so a downloaded copy still needs the
# quarantine flag removed (the Homebrew cask does it).
codesign --force --sign - "$work/tint"
codesign --force --sign - "$app"
codesign --verify --strict "$app"

tar -czf "dist/tint-$version-macos.tar.gz" -C "$work" tint
ditto -c -k --keepParent "$app" "dist/Tint-$version-macos.zip"
echo "==> dist/"
ls -lh dist
