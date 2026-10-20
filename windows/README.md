# FishTouching Reader for Windows

Windows 版复用仓库的阅读页面，桌面程序使用 Electron。当前目标是 Windows 10/11 x64，提供支持应用内更新的 Setup.exe 安装版，以及便携 ZIP；ZIP 解压后运行 `FishTouching Reader.exe`。应用使用系统托盘；`Ctrl + Alt + H` 显示或隐藏窗口，`Ctrl + ,` 打开设置。

加密书库与「我的书库」分别保存在 `%APPDATA%\FishTouching Reader\vault` 和 `%APPDATA%\FishTouching Reader\public`。设置中可添加加密书库，最多 2 个；第二个的数据位于 `vault-spaces\2`，两者各有独立密码、加密密钥、书目和阅读进度，没有主副之分。锁定后输入相应密码进入对应书库；从公开书库进入设置只显示「添加加密书库」，无需其他书库密码；先解锁一个加密书库再进入设置，才显示「修改当前书库密码」标签，修改只影响那个书库。密码均至少 4 个字符。可在解锁后输入另一书库密码移动书籍，复制并验证书籍与进度后再移除原副本。Windows 书库格式与 macOS 版分开，当前没有自动迁移或同步。加密书库使用随机主密钥、scrypt（128 MiB）和 AES-256-GCM；目录、标题、正文和阅读进度都存放在加密文件中。普通书库副本与目录不加密。删除书籍会移除应用管理的副本和进度，不删除你原先导入的文件。

正在阅读加密内容时，应用失去焦点会清除正文、锁定加密书库，并打开「我的书库」最近导入的普通 PDF。解锁后恢复上次阅读的书籍及进度。普通内容失焦不会切换；若没有普通 PDF，切换到「我的书库」列表。

用户可以修改窗口和任务栏中显示的名称、任务栏/Alt+Tab 图标；名称在重启应用后生效。Windows 可执行文件的文件名和“任务管理器”进程名仍是发行包的默认名称，设置不会改写这两个系统字段。自定义图标、10 个内置图标与 macOS 版采用同一套图案。

## 安装与更新

推荐下载安装 GitHub Release 中的 `FishTouching-Reader-Windows-x64-v版本-Setup.exe`。首次从 ZIP 转为安装版时，先退出旧程序，再运行安装包；两者使用同一 `%APPDATA%\FishTouching Reader` 数据目录，不需要重新导入书籍。不要同时运行两份程序。

右键系统托盘图标 →「检查更新…」，或按 Alt 打开「文件」菜单 →「检查更新…」。确认下载后显示任务栏下载进度，完成后选择「重启并安装」或「稍后」；稍后可再次点击菜单完成安装。普通退出不会擅自安装更新。更新前保存阅读位置，并保留书库、密码和设置。

安装版使用 electron-updater/NSIS，从固定 HTTPS 地址 `https://github.com/YouDiSN/fishtouching-reader/releases/latest/download/latest.yml` 比较版本；清单包含安装包地址、版本和 SHA-512 校验值。Windows 当前没有代码签名证书，因此有下载完整性校验，但没有发布者签名验证；SmartScreen 仍可能提示未知发布者。ZIP 入口会提示前往官方发布页安装一次安装版，不会自动替换便携文件。

CI 在临时目录建立低版本测试安装，使用虚构的普通书、加密书和进度，实际执行新版下载、NSIS 替换和自动重启，再核验数据保留；测试源是本机 HTTP 服务，正式包固定使用 GitHub HTTPS，测试入口不提供正式更新源覆盖。

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

安装版构建命令：`npm run package:installer --prefix windows`。

CI 使用 `.github/workflows/windows.yml` 在 Windows runner 上运行数据层测试、界面失焦流程 smoke test，并打包 ZIP。ZIP 不含任何个人书库数据。当前构建未进行 Windows 代码签名。

## 第三方组件

桌面外壳采用 [Electron](https://www.electronjs.org/)（MIT），PDF 渲染采用 [PDF.js](https://mozilla.github.io/pdf.js/)（Apache-2.0）。EPUB 正文提取使用 fflate 和 xmldom（均为 MIT）。完整许可见发行包 `LICENSES` 和相关依赖文件。
