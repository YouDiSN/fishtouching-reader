v1.0.6：修复 Windows 大型 PDF 打开失败。

- 修复大型 PDF 在显示前因字符串转换占用大量内存、导致阅读页面崩溃的问题；改用二进制传输。
- 已在本地 Electron 环境验证约 249 MiB、360 页 PDF 的普通及加密书库打开和跨页跳转。该私人文件不包含在源码、测试样本或发行包中。
- 保留书库格式、阅读进度和既有导入能力；社区功能入口继续隐藏。
- 发布流程在 Windows 上验证数据层、阅读及失焦切换，并对打包后的应用再次进行 smoke 检查。

Personal Developer ID signing, Apple notarization, and macOS automatic updates.

- macOS: Apple Silicon (arm64), macOS 13 deployment target. Open the DMG and drag FishTouching Reader to Applications, or install from the notarized ZIP. The app and disk image carry stapled Apple notarization tickets and use Tengjiao Ji's personal Developer ID (DR4WPFLXBN). macOS may still ask for normal first-open confirmation.
- Sparkle checks for updates and verifies signed downloads. Use Check for Updates… in the app menu. Existing versions without Sparkle require one manual installation; a full old-to-new update installation has not yet been independently verified.
- Homebrew libsodium may target a newer macOS version. Older macOS compatibility has not been verified on real hardware.
- Windows: x64 portable ZIP, unsigned. Extract completely before running the executable. SmartScreen may warn about an unknown publisher. Windows updates remain manual.
- Libraries and reading progress remain in their existing platform-specific locations. macOS and Windows libraries are independent and do not automatically synchronize.
- Both packages preserve project and third-party license notices. SHA256SUMS.txt provides checksums.
