# FishTouching Reader for Windows

Windows 版复用仓库的阅读页面，桌面程序使用 Electron。当前目标是 Windows 10/11 x64，提供便携 ZIP，解压后运行 `FishTouching Reader.exe`。应用使用系统托盘；`Ctrl + Alt + H` 显示或隐藏窗口，`Ctrl + ,` 打开设置。

加密书库与「我的书库」分别保存在 `%APPDATA%\FishTouching Reader\vault` 和 `%APPDATA%\FishTouching Reader\public`。Windows 书库格式与 macOS 版分开，当前没有自动迁移或同步。加密书库使用随机主密钥、scrypt（128 MiB）和 AES-256-GCM；目录、标题、正文和阅读进度都存放在加密文件中。普通书库副本与目录不加密。删除书籍会移除应用管理的副本和进度，不删除你原先导入的文件。

正在阅读加密内容时，应用失去焦点会清除正文、锁定加密书库，并打开「我的书库」最近导入的普通 PDF。解锁后恢复上次阅读的书籍及进度。普通内容失焦不会切换；若没有普通 PDF，切换到「我的书库」列表。

用户可以修改窗口和任务栏中显示的名称、任务栏/Alt+Tab 图标；名称在重启应用后生效。Windows 可执行文件的文件名和“任务管理器”进程名仍是发行包的默认名称，设置不会改写这两个系统字段。自定义图标、10 个内置图标与 macOS 版采用同一套图案。

## 本地开发

需要 Node.js 24+：

```sh
npm ci --prefix windows
npm test --prefix windows
npm start --prefix windows
```

在 Windows 上构建便携版：

```sh
npm run package:win --prefix windows
```

CI 使用 `.github/workflows/windows.yml` 在 Windows runner 上运行数据层测试、界面失焦流程 smoke test，并打包 ZIP。ZIP 不含任何个人书库数据。当前构建未进行 Windows 代码签名。

## 第三方组件

桌面外壳采用 [Electron](https://www.electronjs.org/)（MIT），网页解析采用 [Cheerio](https://github.com/cheeriojs/cheerio)（MIT），PDF 渲染采用 [PDF.js](https://mozilla.github.io/pdf.js/)（Apache-2.0）。完整许可见发行包 `LICENSES` 和相关依赖文件。
