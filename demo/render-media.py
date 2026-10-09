#!/usr/bin/env python3
"""Render README media from fictional fixtures; never reads the user's library."""

import json
import os
import re
import signal
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DEMO = ROOT / "demo"
FIXTURES = DEMO / "fixtures"
OUTPUT = ROOT / "docs" / "media"
CHROME = Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
SIZE = "1024,768"


def run(*args):
    subprocess.run(args, check=True)


def capture(name: str, html: str, temporary: Path):
    page = temporary / f"{name}.html"
    screenshot = OUTPUT / f"{name}.png"
    page.write_text(html, encoding="utf-8")
    command = [
        str(CHROME), "--headless=new", "--no-first-run", "--disable-extensions",
        "--disable-background-networking", "--disable-gpu", "--hide-scrollbars",
        "--force-device-scale-factor=1", f"--window-size={SIZE}",
        "--virtual-time-budget=800", f"--user-data-dir={temporary / (name + '-profile')}",
        f"--screenshot={screenshot}", page.as_uri(),
    ]
    process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               start_new_session=True)
    try:
        process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=5)
    if not screenshot.exists() or screenshot.stat().st_size < 10_000:
        raise RuntimeError(f"Chrome did not render {screenshot}")
    print(screenshot)


def application_frame(view: str, label: str, payload: dict) -> str:
    source = (ROOT / "Resources" / "index.html").read_text(encoding="utf-8")
    source = re.sub(r"let indexURL = '[^']*';", "let indexURL = '';", source)
    style = """
    body { background: #0a1110; }
    .demo-window { width: 1024px; height: 768px; overflow: hidden; background: #101716; }
    .demo-titlebar { height: 38px; background: #1d2925; border-bottom: 1px solid #35463e;
      display: flex; align-items: center; padding: 0 17px; color: #d8e6dc; font-size: 12px; }
    .demo-dots { display: flex; gap: 7px; margin-right: 16px; }
    .demo-dots i { width: 11px; height: 11px; border-radius: 50%; background: #fa6058; }
    .demo-dots i:nth-child(2) { background: #f7bf49; }
    .demo-dots i:nth-child(3) { background: #37c85a; }
    .demo-name { font-weight: 600; }
    .demo-step { margin-left: auto; border: 1px solid #41634d; border-radius: 999px;
      padding: 4px 11px; background: #253b2c; color: #bce9c4; }
    #app { height: 730px; overflow: auto; }
    """
    source = source.replace("</style>", style + "</style>")
    source = source.replace('<body><main id="app"></main>',
                            f'<body><div class="demo-window"><div class="demo-titlebar"><span class="demo-dots"><i></i><i></i><i></i></span><span class="demo-name">FishTouching Reader</span><span class="demo-step">{label}</span></div><main id="app"></main></div>')
    state = json.dumps(payload, ensure_ascii=False).replace("</", "<\\/")
    source = source.replace("</body>", f"<script>receive({state});</script></body>")
    return source


def cover_frame() -> str:
    return """<!doctype html><html lang="zh-CN"><meta charset="utf-8"><style>
      *{box-sizing:border-box}body{margin:0;font-family:-apple-system,'PingFang SC',sans-serif;background:#0a1110;color:#d8e6dc}
      .window{width:1024px;height:768px;background:#101716;overflow:hidden}
      .titlebar{height:38px;background:#1d2925;border-bottom:1px solid #35463e;display:flex;align-items:center;padding:0 17px;font-size:12px}
      .dots{display:flex;gap:7px;margin-right:16px}.dots i{width:11px;height:11px;border-radius:50%;background:#fa6058}.dots i:nth-child(2){background:#f7bf49}.dots i:nth-child(3){background:#37c85a}
      .step{margin-left:auto;border:1px solid #41634d;border-radius:999px;padding:4px 11px;background:#253b2c;color:#bce9c4}
      .toolbar{height:52px;display:flex;align-items:center;padding:0 22px;gap:22px;border-bottom:1px solid #34483d;background:#101716;font-size:20px}
      .toolbar .grow{flex:1}.viewer{height:678px;background:#171d1b;display:flex;justify-content:center;align-items:flex-start;overflow:hidden;padding:20px}
      .viewer img{width:505px;box-shadow:0 10px 35px #0009;background:white}
      </style><body><div class="window"><div class="titlebar"><span class="dots"><i></i><i></i><i></i></span><strong>FishTouching Reader</strong><span class="step">② 切走后自动显示工作 PDF</span></div>
      <div class="toolbar"><span>←</span><span class="grow"></span><span>♙</span><span>⚙</span></div>
      <div class="viewer"><img src="cover-1.png" alt="虚构项目周报 PDF"></div></div></body></html>"""


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
    if not CHROME.exists():
        raise RuntimeError("Google Chrome is needed to render the app HTML")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="fishtouching-demo-", ignore_cleanup_errors=True) as folder:
        temporary = Path(folder)
        cover = FIXTURES / "工作汇报.pdf"
        run("pdftoppm", "-f", "1", "-l", "1", "-png", "-r", "120", str(cover), str(temporary / "cover"))
        paragraphs = [line for line in (FIXTURES / "摸鱼.txt").read_text(encoding="utf-8").splitlines() if line.strip()]
        reading = {"type": "book", "tab": "secure", "id": "demo-book", "encodedTitle": "摸鱼",
                   "paragraphs": paragraphs, "paragraph": 0, "fraction": 0}
        resumed = {**reading, "paragraph": 2}
        normal = {"type": "normal", "pdfs": [
            {"id": "demo-pdf", "title": "工作汇报", "kind": "pdf", "pageCount": 1,
             "pageIndex": 0, "pageFraction": 0, "updatedAt": 0},
            {"id": "demo-text", "title": "正式-会议纪要", "kind": "text", "pageCount": 9,
             "pageIndex": 0, "pageFraction": 0, "updatedAt": 0},
        ]}
        capture("01-reading", application_frame("reading", "① 正在阅读虚构短篇", reading), temporary)
        capture("02-cover", cover_frame(), temporary)
        capture("03-locked", application_frame("locked", "③ 返回后解锁", {"type": "locked"}), temporary)
        capture("04-library", application_frame("library", "演示书库 · 全部虚构素材", normal), temporary)
        capture("05-resumed", application_frame("resumed", "④ 解锁后继续阅读", resumed), temporary)
    make_gif()


if __name__ == "__main__":
    main()
