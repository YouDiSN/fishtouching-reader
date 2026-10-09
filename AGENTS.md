# FishTouching Reader 项目约定

- 这是 YouDiSN 的个人 macOS 项目，不属于公司项目。提交和发布只使用个人 GitHub 仓库，不加入公司组织、账号、依赖或配置。
- 项目采用 MIT License，版权声明为 `Copyright (c) 2026 YouDiSN`。源码和下载包均须保留项目 LICENSE、第三方许可文件及声明；不要把 SwiftSoup 或 libsodium 的版权归到本项目名下。
- 源码在 `Sources/LocalLibrary/`，界面在 `Resources/`，构建脚本在 `scripts/`。目标最低系统版本为 macOS 13；当前构建依赖 Homebrew 的 arm64 `libsodium` 静态库。该依赖目前包含针对 macOS 26 构建的对象文件，旧系统兼容性需要实机验证。
- Windows 版位于 `windows/`，复用由 `windows/scripts/prepare-assets.js` 转换的阅读界面。其书库格式和路径与 macOS 版分开；不要声称两个平台自动同步或直接兼容。`npm test --prefix windows` 验证数据层；Windows Actions 还需通过 Electron smoke 和打包后才能发布 ZIP。
- 默认应用名称是「FishTouching Reader」，默认图标是 `fish`。用户可在应用内修改名称和图标；本机已改名的 `.app` 目录不代表发行包的默认名称。
- 书库数据位于 `~/Library/Application Support/LocalLibrary/`。不要将该目录、个人阅读清单、源书籍、密码、密钥、备份、日志或用户自定义图标加入 Git、测试样本或发行包。
- README 截图、GIF 和测试演示只使用 `demo/fixtures/` 中虚构素材；`demo/render-media.py` 不得读取真实书库。生成媒体后人工检查画面再公开。
- 加密书库内容及目录必须保持加密存储。修改导入、加密、解锁、失焦切换或进度逻辑时，先检查对现有书库和阅读进度的兼容性；测试优先使用临时目录，不对真实书库做破坏性测试。
- 书库列表的“移除”只处理应用管理的目录记录、副本和进度。不要删除 Finder 中用户最初选择的原始文件；移除操作需有确认弹窗，并同时更新最近阅读与全部书籍。
- 常规验证：`swift build -c release`、`.build/release/LocalLibrary --self-test`。在线导入验证 `--verify-live` 依赖外部网站，仅在需要检查导入逻辑时运行。
- 用 `./scripts/package-release.sh` 生成 GitHub Release 下载包。此脚本将应用复制到临时目录并固定命名为「FishTouching Reader.app」，不会覆盖本机改名后的应用。发布前核对压缩包只含可执行文件、界面、图标和签名，不含书库数据。
- 当前应用采用临时签名，未公证。README 和 Release 必须如实写明构建架构、最低系统版本及首次打开时可能遇到的 macOS 安全提示。
