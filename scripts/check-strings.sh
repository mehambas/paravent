#!/bin/bash
# Lists the strings the compiler marks as localizable that Resources/tr.lproj/Localizable.strings lacks,
# and the translations no longer used. Run it after changing any text in the app.
set -euo pipefail
cd "$(dirname "$0")/.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
touch Sources/Paravent/*.swift
swift build --disable-sandbox -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$work" >/dev/null
plutil -convert json -o "$work/tr.json" Resources/tr.lproj/Localizable.strings
python3 - "$work" <<'PY'
import glob, json, sys
work = sys.argv[1]
used = {e["key"] for f in glob.glob(f"{work}/*.stringsdata") for entries in json.load(open(f)).get("tables", {}).values() for e in entries}
translated = set(json.load(open(f"{work}/tr.json")))
# Strings that read the same in Turkish need no entry.
same = {"Paravent %@"}
missing, unused = sorted(used - translated - same), sorted(translated - used)
for key in missing: print("missing:", key)
for key in unused: print("unused: ", key)
sys.exit(1 if missing or unused else 0)
PY
echo "Turkish strings are complete."
