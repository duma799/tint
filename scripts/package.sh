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

# Signing. With TINT_SIGN_IDENTITY set to a Developer ID ("Developer ID
# Application: Name (TEAMID)"), both are signed with the hardened runtime;
# without it, ad hoc ("-") — enough for Apple silicon to run them, but a
# downloaded copy then needs the quarantine flag removed (the cask does it).
identity="${TINT_SIGN_IDENTITY:--}"
sign() {
  if [ "$identity" = "-" ]; then
    codesign --force --sign - "$1"
  else
    codesign --force --options runtime --timestamp --sign "$identity" "$1"
  fi
}
sign "$work/tint"
sign "$app"
codesign --verify --strict "$app"

# Notarizing, when Apple ID credentials are given: Apple checks the files,
# and the app gets a "ticket" stapled to it, so macOS opens it without asking.
if [ "$identity" != "-" ] && [ -n "${TINT_NOTARY_APPLE_ID:-}" ]; then
  notarize() {
    xcrun notarytool submit "$1" --wait \
      --apple-id "$TINT_NOTARY_APPLE_ID" --team-id "$TINT_NOTARY_TEAM_ID" --password "$TINT_NOTARY_PASSWORD"
  }
  echo "==> notarizing"
  ditto -c -k --keepParent "$app" "$work/notarize-app.zip"
  notarize "$work/notarize-app.zip"
  xcrun stapler staple "$app"
  ditto -c -k "$work/tint" "$work/notarize-cli.zip"
  notarize "$work/notarize-cli.zip"
fi

tar -czf "dist/tint-$version-macos.tar.gz" -C "$work" tint
ditto -c -k --keepParent "$app" "dist/Tint-$version-macos.zip"
echo "==> dist/"
ls -lh dist
