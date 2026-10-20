#!/usr/bin/env python3
"""Build a checked Unicode mapping by exact glyph-outline matching.
Developer-only dependency: fonttools. Inputs are fonts, never books or library data.
The original Source Han Sans font is SIL OFL 1.1; preserve its notice and license.
"""
import argparse
import hashlib
import json
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import DecomposingRecordingPen

parser = argparse.ArgumentParser()
parser.add_argument('--original', required=True, type=Path)
parser.add_argument('--web-font', required=True, type=Path)
parser.add_argument('--family', required=True)
parser.add_argument('--asset', required=True)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
original, web = TTFont(args.original), TTFont(args.web_font)

def outlines(font):
    glyphs = font.getGlyphSet()
    result = {}
    for code, name in font.getBestCmap().items():
        pen = DecomposingRecordingPen(glyphs)
        glyphs[name].draw(pen)
        result[code] = repr(pen.value)
    return result

reference = {}
for code, outline in outlines(original).items():
    if 0x4e00 <= code <= 0x9fff or 32 <= code < 127:
        reference.setdefault(outline, []).append(chr(code))
mapping = {}
for code, outline in outlines(web).items():
    candidates = reference.get(outline, [])
    if len(candidates) != 1:
        raise SystemExit(f'Ambiguous or unknown outline: U+{code:04X}; refusing partial mapping')
    mapping[str(code)] = candidates[0]
args.output.write_text(json.dumps({
    'family': args.family, 'asset': args.asset,
    'sha256': hashlib.sha256(args.web_font.read_bytes()).hexdigest(),
    'mapping': mapping,
}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'Validated {len(mapping)} glyphs by exact outline matching')
