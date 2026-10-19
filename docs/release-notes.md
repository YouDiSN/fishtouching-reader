v1.0.4：阅读导航更新。

- 常驻上一页、下一页和阅读进度，支持输入页码跳转、返回跳转前的位置。
- TXT 自动识别章节，支持按章号或名称搜索并跳转；PDF 支持自带书签跳转。
- 字号和排版收进“阅读设置”，精简顶部操作；移除手动锁定按钮，保留失焦自动锁定。
- 按原文位置分页，保留现有书库格式和阅读进度。

Personal Developer ID signing, Apple notarization, and macOS automatic updates.

- macOS: Apple Silicon (arm64), macOS 13 deployment target. Open the DMG and drag FishTouching Reader to Applications, or install from the notarized ZIP. The app and disk image carry stapled Apple notarization tickets and use Tengjiao Ji's personal Developer ID (DR4WPFLXBN). macOS may still ask for normal first-open confirmation.
- Sparkle checks for updates and verifies signed downloads. Use Check for Updates… in the app menu. Existing versions without Sparkle require one manual installation; a full old-to-new update installation has not yet been independently verified.
- Homebrew libsodium may target a newer macOS version. Older macOS compatibility has not been verified on real hardware.
- Windows: x64 portable ZIP, unsigned. Extract completely before running the executable. SmartScreen may warn about an unknown publisher. Windows updates remain manual.
- Libraries and reading progress remain in their existing platform-specific locations. macOS and Windows libraries are independent and do not automatically synchronize.
- Both packages preserve project and third-party license notices. SHA256SUMS.txt provides checksums.
