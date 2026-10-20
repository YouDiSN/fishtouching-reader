#!/usr/bin/env python3
"""Package data-only community manifests. Never reads library or book files."""
import json
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
source = root / 'docs/plugins/sources'
output = root / 'docs/plugins/packages'
output.mkdir(exist_ok=True)
plugins = []
for file in sorted(source.glob('*.json')):
    data = file.read_bytes()
    plugin = json.loads(data)
    assert len(data) <= 65536 and plugin['id'].startswith('community.')
    plugins.append(plugin)
    info = ZipInfo('manifest.json', date_time=(2026, 1, 1, 0, 0, 0))
    info.compress_type = ZIP_DEFLATED
    info.external_attr = 0o100644 << 16
    with ZipFile(output / (file.stem + '.zip'), 'w') as archive:
        archive.writestr(info, data)
(root / 'Resources/community-plugins.json').write_text(
    json.dumps(plugins, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('Packaged', len(plugins), 'community manifests; no book content included.')
