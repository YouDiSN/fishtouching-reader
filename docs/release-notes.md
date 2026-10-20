v1.0.8：简洁的单页面设置。

- 设置与书库共用同一个页面，不再新建设置窗口，不使用 iframe；反复打开复用已有视图。
- 左侧独立划分「主题」「字体」「应用标识」「密码与隐私」。
- 五套主题使用配色缩略预览卡展示，点击即可使用。
- 字体页面统一调整系统字体和字号，提供正文预览；与阅读页快捷设置共享配置，保留阅读位置。
- 从加密阅读进入设置先保存进度并锁定书库；失焦清空密码输入。
- 保留大型 PDF 修复、现有书库格式和进度，社区入口继续隐藏。所有演示和测试均使用虚构素材，发行包不含书库数据。

Personal Developer ID signing, Apple notarization, and macOS automatic updates.

- macOS: Apple Silicon (arm64), macOS 13 deployment target. Open the DMG and drag FishTouching Reader to Applications, or install from the notarized ZIP. The app and disk image carry stapled Apple notarization tickets and use Tengjiao Ji's personal Developer ID (DR4WPFLXBN). macOS may still ask for normal first-open confirmation.
- Sparkle checks for updates and verifies signed downloads. Use Check for Updates… in the app menu. Existing versions without Sparkle require one manual installation; a full old-to-new update installation has not yet been independently verified.
- Homebrew libsodium may target a newer macOS version. Older macOS compatibility has not been verified on real hardware.
- Windows: x64 portable ZIP, unsigned. Extract completely before running the executable. SmartScreen may warn about an unknown publisher. Windows updates remain manual.
- Libraries and reading progress remain in their existing platform-specific locations. macOS and Windows libraries are independent and do not automatically synchronize.
- Both packages preserve project and third-party license notices. SHA256SUMS.txt provides checksums.
