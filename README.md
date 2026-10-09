# 摸鱼阅读

macOS 本地阅读器，提供「我的书库」和锁图标入口的加密书库。首次打开时设置应用名称、可选 Dock 图标，以及两次输入的书库密码。已有旧版加密小说会在首次设置密码时迁移，保留阅读进度。

这是个人项目，不含小说、PDF 或用户书库数据。

## 下载和安装

从 [GitHub Releases](https://github.com/YouDiSN/moyu-reader/releases) 下载 `摸鱼阅读-macos-arm64-v0.3.0.zip`，解压后将「摸鱼阅读.app」拖入“应用程序”文件夹，或放在自己选择的位置运行。当前下载包适用于 Apple Silicon、macOS 13 或更新版本。

下载包为临时签名，尚未进行 Apple 公证。macOS 首次拦截时，可在“系统设置 → 隐私与安全性”中确认打开。只从本仓库的 Release 页面下载，并核对 Release 中列出的 SHA-256。当前应用没有自动更新功能。

## 构建和运行

需要 macOS、Swift 5.9+、SwiftSoup 包依赖，以及通过 Homebrew 安装的 `libsodium`（本机路径 `/opt/homebrew/lib/libsodium.a`）。

```sh
brew install libsodium
./scripts/build-app.sh
open dist/*.app
```

这份构建使用本机静态 libsodium；如果将应用发给其他 macOS 版本或架构，还需要为目标系统重新构建和签名。当前包只有临时签名。

生成默认名称的发行压缩包：

```sh
./scripts/package-release.sh
```

发行脚本会复制构建结果，再将副本命名为「摸鱼阅读.app」。本机在设置中修改过的应用名称不会进入下载包。压缩包写入 `release/`，该目录和本机 `dist/` 均不提交到 Git。

## 使用

- 两个书库的「＋ 添加本地文件」默认打开文件选择器，支持 TXT、PDF。「我的书库」的文件可由 Finder 直接查看；加密书库的 TXT 和 PDF 均加密保存。
- 加密书库的「从网址导入」提供单篇预览和目录批量导入。WordPress 和 Cool18 的已知结构有适配，其他文章页尝试常见正文选择器。遇到分页、动态渲染或特殊模板时会报错或需要单独适配；预览时请确认正文完整。
- 加密内容失焦时会清除当前内容并显示「我的书库」第一本 PDF，解锁后回到先前的阅读位置。「我的书库」失焦不锁定。
- `Control + Option + H` 显示或隐藏窗口，`Command + ,` 打开设置。菜单栏书本图标提供单行“显示／隐藏”切换和设置，快捷键显示在菜单项右侧。
- 书库提供最近阅读列表、阅读进度、搜索和按字数排序。新安装默认名称为「摸鱼阅读」，默认使用内置摸鱼图标；设置窗口可从 10 个内置图标中选择，也可使用自己的图片，还能修改名称和密码。名称留空保存会恢复默认名称。自定义图标推荐至少 1024×1024 像素的正方形 PNG 原图；删除自定义图标只移除应用保存的副本，不删除原始图片。
- 保存应用名称后可选择“立即重启”或“下次重启”。应用会在退出后重命名自身的 `.app` 文件夹，无需重新编译；图标选择后立即更新。

## 存储和备份

数据位于 `~/Library/Application Support/LocalLibrary/`。加密书库的文件名为 UUID，书名、来源网址和内容存放于 AES-GCM 加密文件，主密钥由用户密码通过 Argon2id（随机 salt、64 MiB 内存、3 次计算）派生的密钥包装。目录中不再保存 `vault.key`。「我的书库」保存在 `public-pdfs` 和 `public-texts`，不加密。

旧版迁移前应备份整个 `LocalLibrary` 目录。**旧版备份仍包含原始密钥和带标题的路径**；确认新库可打开、书籍和进度无误后，需自行处理旧备份。密码丢失后无法从新书库恢复内容。操作系统的交换空间、应用内存和用户自行导入的源文件不在应用存储加密范围内。

## 验证

```sh
.build/release/LocalLibrary --self-test
.build/release/LocalLibrary --verify-live
.build/release/LocalLibrary --verify-migration "/path/to/old/LocalLibrary-backup"
```

迁移验证只使用临时副本，不修改指定的备份或正式书库。
