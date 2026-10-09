# README 演示素材

这里的 `fixtures/` 是专门编写的虚构素材：`摸鱼.txt` 是短篇故事，`正式.txt`、`正式-会议纪要.txt` 和 `工作汇报.pdf` 是虚构工作文档。它们可供手动导入应用体验失焦切换，也用于生成仓库 README 的示意画面。不要用真实个人书库内容替换这些文件。

截图由脚本读取当前 `Resources/index.html`，注入演示书籍状态；工作 PDF 画面使用演示 PDF。窗口外框与 PDF 工具栏是示意绘制，故画面不是对正在运行的原生应用录屏。

在装有 macOS、Google Chrome、Poppler 和 FFmpeg 的机器上重新生成：

```sh
swift demo/generate-cover.swift
python3 demo/render-media.py
```

脚本仅读取本目录的虚构 TXT/PDF 与仓库界面源码，输出到 `docs/media/`。运行后请人工检查画面、GIF 和内容，再提交到公开仓库。
