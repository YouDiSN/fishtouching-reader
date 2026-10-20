# README 与视频演示素材

`fixtures/` 是专门编写的虚构短篇和工作文档。禁止读取真实书库、密码、阅读清单或个人文件生成媒体。

当前 README 功能截图和 GIF 来自 v1.0.12 的 Electron 桌面实现，在 macOS 上运行，使用共享的当前阅读/设置界面。这不是原生 macOS App 或 Windows 系统桌面的录像。截图直接捕获应用内容；宣传片外框、标题和字幕属于后期排版。

## 重新录制

需要 Node.js、FFmpeg、Electron，以及已安装依赖的 `windows/node_modules`。传入本机 Electron 可执行文件路径，例如 macOS 的 `windows/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron`：

```sh
python3 demo/record-media.py /tmp/ftr-demo-captures \
  --electron windows/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron
python3 demo/render-media.py /tmp/ftr-demo-captures
swiftc demo/capture-font.swift -framework AppKit -framework WebKit -o /tmp/ftr-capture-font
/tmp/ftr-capture-font "$PWD/Resources" "$PWD/docs/media/07-fonts.png"
```

录制时请让演示窗口保持前台。脚本将当前桌面实现复制到临时目录，仅替换 smoke 测试入口，不修改产品界面或注入界面状态；自动创建两个演示书库，使用虚构素材验证实际失焦锁定、工作 PDF 切换、解锁续读、不同密码打开不同书库，以及重启后名称图标持久化。密码仅供临时演示，不对应用户书库。结束后删除临时书库。

输出包括应用片段、七张原始截图（其中字体截图在 macOS 上运行 Windows 实现时不用于 README）和验证记录。`render-media.py` 将截图复制到 `docs/media/`，按阅读→切走→解锁→续读的顺序生成 GIF。生成后必须人工检查所有截图、GIF 和视频关键帧，再提交公开仓库。

宣传片保持已确认的 32 秒结构：开场问题 4.5 秒、介绍 3.5 秒、切屏续读 6.5 秒、双书库 7 秒、名称图标设置 4 秒、重启验证 3 秒、结尾 3.5 秒。更新画面时保留原旁白、字幕、时长及转场；不添加网址、二维码或下载引导。

字体截图单独使用 macOS WKWebView 加载当前 Resources，并读取 NSFontManager 系统字体列表。它只注入空演示书库和外观偏好，不访问用户书库。这样不会把在 macOS 上运行 Windows 实现时的字体不可用提示用于产品截图。
