#!/usr/bin/env python3
"""Publish fixture-only captures from record-media.py as README media."""
import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'docs/media'
def run(*args):
    subprocess.run(args, check=True)

def make_gif():
    frames = [
        ("01-reading", 1.8), ("02-cover", 2.2),
        ("03-locked", 1.4), ("05-resumed", 1.8),
    ]
    with tempfile.TemporaryDirectory(prefix="fishtouching-gif-") as folder:
        temporary = Path(folder)
        playlist = temporary / "frames.txt"
        rows = []
        for name, seconds in frames:
            rows.extend([f"file '{OUTPUT / (name + '.png')}'", f"duration {seconds}"])
        rows.append(f"file '{OUTPUT / (frames[-1][0] + '.png')}'")
        playlist.write_text("\n".join(rows) + "\n", encoding="utf-8")
        palette = temporary / "palette.png"
        filters = "fps=6,scale=820:-1:flags=lanczos"
        run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0",
            "-i", str(playlist), "-vf", filters + ",palettegen=stats_mode=diff", str(palette))
        target = OUTPUT / "focus-switch-demo.gif"
        run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0",
            "-i", str(playlist), "-i", str(palette), "-lavfi",
            filters + " [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=5", "-loop", "0", str(target))
        print(target)



def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('captures', type=Path, help='Output directory from record-media.py')
    args = parser.parse_args()
    proof = json.loads((args.captures/'proof.json').read_text())
    if not proof.get('fixturesOnly') or not proof.get('temporaryLibrary'):
        raise RuntimeError('Only isolated fictional fixture captures may be published')
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name in ['01-reading', '02-cover', '03-locked', '04-library', '05-resumed', '06-themes']:
        shutil.copy2(args.captures / (name + '.png'), OUTPUT / (name + '.png'))
    make_gif()

if __name__ == '__main__':
    main()
