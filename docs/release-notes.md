v1.0.12：优化字体选择框。

- 增加字体下拉框内边距与高度，文字不再贴近边框。
- 统一圆角和下拉箭头间距，保留系统字体菜单及键盘操作。

Personal Developer ID signing, Apple notarization, and macOS automatic updates.

- macOS: Apple Silicon (arm64), macOS 13 deployment target. Open the DMG and drag FishTouching Reader to Applications, or install from the notarized ZIP. The app and disk image carry stapled Apple notarization tickets and use Tengjiao Ji's personal Developer ID (DR4WPFLXBN). macOS may still ask for normal first-open confirmation.
- Sparkle checks for updates and verifies signed downloads. Use Check for Updates… in the app menu. Existing versions without Sparkle require one manual installation; a full old-to-new update installation has not yet been independently verified.
- Homebrew libsodium may target a newer macOS version. Older macOS compatibility has not been verified on real hardware.
- Windows: x64 NSIS Setup.exe installer with in-app updates, plus portable ZIP; both unsigned. Extract completely before running the executable. SmartScreen may warn about an unknown publisher. Existing ZIP users must install Setup.exe once to enable updates. Updates use HTTPS and SHA-512 integrity checks, without Windows publisher signature verification.
- Libraries and reading progress remain in their existing platform-specific locations. macOS and Windows libraries are independent and do not automatically synchronize.
- Both packages preserve project and third-party license notices. SHA256SUMS.txt provides checksums.
