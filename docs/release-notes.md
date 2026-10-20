v1.0.7：阅读主题与系统字体。

- 新增森林绿、暖纸、浅色、午夜蓝、石墨灰五套内置主题。
- 在正文右上角「阅读设置」，或「设置 → 外观 → 阅读外观」中切换主题、搜索和选择本机已安装字体，并即时预览。
- 外观设置自动保存，阅读窗口和设置窗口同步更新；切换字体和主题保留当前阅读位置。
- 字体设置用于 TXT、EPUB 正文，PDF 保留原始页面排版；不下载字体，缺失字符使用系统备用字体。
- 已验证 macOS 字体读取、五套主题和进度保持；Windows CI 验证系统字体、进度保持、数据层及打包后阅读与失焦切换。
- 包含 v1.0.6 大型 PDF 修复。保留现有书库与进度，社区功能入口继续隐藏。

Personal Developer ID signing, Apple notarization, and macOS automatic updates.

- macOS: Apple Silicon (arm64), macOS 13 deployment target. Open the DMG and drag FishTouching Reader to Applications, or install from the notarized ZIP. The app and disk image carry stapled Apple notarization tickets and use Tengjiao Ji's personal Developer ID (DR4WPFLXBN). macOS may still ask for normal first-open confirmation.
- Sparkle checks for updates and verifies signed downloads. Use Check for Updates… in the app menu. Existing versions without Sparkle require one manual installation; a full old-to-new update installation has not yet been independently verified.
- Homebrew libsodium may target a newer macOS version. Older macOS compatibility has not been verified on real hardware.
- Windows: x64 portable ZIP, unsigned. Extract completely before running the executable. SmartScreen may warn about an unknown publisher. Windows updates remain manual.
- Libraries and reading progress remain in their existing platform-specific locations. macOS and Windows libraries are independent and do not automatically synchronize.
- Both packages preserve project and third-party license notices. SHA256SUMS.txt provides checksums.
