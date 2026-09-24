#!/bin/sh
# Builds the release files for one Mac architecture into dist/:
#   tint-<version>-<rid>.tar.gz   the `tint` command (one self-contained file)
#   Tint-<version>-<rid>.zip      the desktop app
#
#   scripts/package.sh osx-arm64     # Apple silicon
#   scripts/package.sh osx-x64       # Intel
#
# Needs macOS (sips, iconutil, codesign, ditto) and the .NET SDK.
set -eu

rid="${1:?usage: scripts/package.sh osx-arm64|osx-x64}"
cd "$(dirname "$0")/.."
version=$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' Directory.Build.props)
work="artifacts/$rid"
rm -rf "$work"
mkdir -p "$work" dist

echo "==> tint $version ($rid): command"
# Trimmed and compressed: ~14 MB instead of ~80. PackAsTool is for NuGet only.
dotnet publish src/Tint.Cli -c Release -r "$rid" --self-contained \
  -p:PublishSingleFile=true -p:PublishTrimmed=true -p:EnableCompressionInSingleFile=true \
  -p:PackAsTool=false -p:DebugType=none -o "$work/cli"
tar -czf "dist/tint-$version-$rid.tar.gz" -C "$work/cli" tint

echo "==> tint $version ($rid): Tint.app"
dotnet publish src/Tint.App -c Release -r "$rid" --self-contained -p:DebugType=none -o "$work/app-files"
app="$work/Tint.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp -R "$work/app-files/." "$app/Contents/MacOS/"
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
# Every file in Contents/MacOS counts as code, .dll files too, and must be
# signed before the bundle. The main executable is signed with the bundle:
# signing it alone would try to sign the bundle before the rest are ready.
find "$app/Contents/MacOS" -type f ! -path "$app/Contents/MacOS/Tint" -exec codesign --force --sign - {} +
codesign --force --sign - "$app"
codesign --verify --strict "$app"

ditto -c -k --keepParent "$app" "dist/Tint-$version-$rid.zip"
echo "==> dist/"
ls -lh dist
