#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache"
build=(swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c release --arch arm64 --arch x86_64)
"${build[@]}"
binary_dir="$("${build[@]}" --show-bin-path)"
app_path="$PWD/dist/Paravent.app"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/Paravent" "$app_path/Contents/MacOS/Paravent"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/Assets.car Resources/MenuBar*Template*.png "$app_path/Contents/Resources/"
cp -R Resources/en.lproj Resources/tr.lproj "$app_path/Contents/Resources/"
# Accessibility and Screen Recording permissions are tied to the signature, and an ad hoc one changes with every build.
# The self-signed certificate from scripts/make-certificate.sh keeps the identity stable;
# PARAVENT_SIGN_IDENTITY picks another one, - forces ad hoc signing.
identity="${PARAVENT_SIGN_IDENTITY:-$(security find-identity -p codesigning | awk -F'"' '$2 == "Paravent Self-Signed" { print $2; exit }')}"
codesign --force --sign "${identity:--}" --identifier com.hamzabasaran.paravent --timestamp=none "$app_path"
codesign --verify --strict "$app_path"
printf 'Built: %s (%s, signed: %s)\n' "$app_path" "$(lipo -archs "$app_path/Contents/MacOS/Paravent")" "${identity:-ad hoc}"
