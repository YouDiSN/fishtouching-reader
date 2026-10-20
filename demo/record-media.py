#!/usr/bin/env python3
"""Record current Electron UI using only fictional fixtures and temporary libraries."""
import argparse, json, os, shutil, subprocess, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
p = argparse.ArgumentParser()
p.add_argument('output', type=Path)
p.add_argument('--electron', type=Path, required=True)
a = p.parse_args()
a.output = a.output.resolve(); a.output.mkdir(parents=True, exist_ok=True)
subprocess.run(['npm', 'run', 'prepare:assets', '--prefix', str(ROOT/'windows')], check=True)
with tempfile.TemporaryDirectory(prefix='ftr-media-') as temporary:
    work = Path(temporary)/'app'; work.mkdir()
    for f in (ROOT/'windows').iterdir():
        if f.is_file() and f.suffix in ('.js', '.json'): shutil.copy2(f, work/f.name)
    shutil.copytree(ROOT/'windows/assets',work/'assets')
    (work/'node_modules').symlink_to(ROOT/'windows/node_modules',target_is_directory=True)
    source=(work/'main.js').read_text()
    start=source.index('async function runSmoke() {')
    end=source.index('app.whenReady().then',start)
    source=source[:start]+(ROOT/'demo/record-scenes.js').read_text()+'\n'+source[end:]
    (work/'main.js').write_text(source)
    env={**os.environ,'FISHTOUCHING_SMOKE_ROOT':str(Path(temporary)/'library'),
         'FISHTOUCHING_SMOKE_FIXTURES':str(ROOT/'demo/fixtures'), 'FTR_MEDIA_OUTPUT':str(a.output)}
    for _ in range(2):
        result = subprocess.run([str(a.electron.resolve()), str(work)], env=env, timeout=60)
        if result.returncode:
            print((Path(temporary)/'library/startup.log').read_text())
            result.check_returncode()
    (a.output/'capture-version.json').write_text(json.dumps({'version':json.loads((work/'package.json').read_text())['version'],
        'commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
        'fixturesOnly':True,'temporaryLibraryDeleted':True},indent=2))
