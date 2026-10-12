#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
version=$(python3 -c 'import json; print(json.load(open("windows/package.json"))["version"])')
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp "release/fishtouching-reader-macos-arm64-v$version.dmg" "$stage/"
args=(--account fishtouching-reader)
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  args=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
fi
.build/artifacts/sparkle/Sparkle/bin/generate_appcast "${args[@]}" \
  --maximum-deltas 0 \
  --download-url-prefix "https://github.com/YouDiSN/fishtouching-reader/releases/download/v$version/" "$stage"
cp "$stage/appcast.xml" release/appcast.xml
python3 - "$version" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse('release/appcast.xml')
items = root.findall('./channel/item')
assert len(items) == 1
item = items[0]
ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
assert item.findtext(ns + 'shortVersionString') == sys.argv[1]
enclosure = item.find('enclosure')
assert enclosure.get(ns + 'edSignature')
assert int(enclosure.get('length')) > 0
assert enclosure.get('url').startswith('https://github.com/YouDiSN/fishtouching-reader/releases/download/v' + sys.argv[1] + '/')
print('Verified signed appcast for', sys.argv[1])
PY
