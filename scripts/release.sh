#!/bin/bash
# Sets the version, builds and signs Paravent, and packs it into dist/Paravent.dmg with its checksum in dist/Paravent.dmg.sha256.
# Usage: scripts/release.sh <version>
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?Usage: scripts/release.sh <version>, for example 0.1.0}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "The version must look like 1.2.3." >&2; exit 1; }
# Without the certificate every release would be a different app to macOS and lose its permissions.
security find-identity -p codesigning | grep -qF '"Paravent Self-Signed"' || { echo "\"Paravent Self-Signed\" is not in the keychain (see scripts/make-certificate.sh)." >&2; exit 1; }

plist=Resources/Info.plist
build_number=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist") + 1 ))
perl -pi -e "s{(<key>CFBundleShortVersionString</key><string>)[^<]*}{\${1}$version}; s{(<key>CFBundleVersion</key><string>)[^<]*}{\${1}$build_number}" "$plist"
PARAVENT_SIGN_IDENTITY="Paravent Self-Signed" bash scripts/build.sh

# No version in the name: the README and the website link releases/latest/download/Paravent.dmg,
# and the update check looks for the assets Paravent.dmg and Paravent.dmg.sha256.
dmg="dist/Paravent.dmg"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto dist/Paravent.app "$staging/Paravent.app"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -ov -volname "Paravent" -srcfolder "$staging" -fs HFS+ -format UDZO "$dmg"
hdiutil verify -quiet "$dmg"
(cd dist && shasum -a 256 Paravent.dmg > Paravent.dmg.sha256)
printf 'Release %s (build %s), attach both files to the v%s release:\n%s  %s\n%s  SHA-256 %s\n' "$version" "$build_number" "$version" \
    "$dmg" "$(du -h "$dmg" | cut -f1)" "$dmg.sha256" "$(cut -d' ' -f1 "$dmg.sha256")"
