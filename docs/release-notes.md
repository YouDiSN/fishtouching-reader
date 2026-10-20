v1.0.12：简化密码管理，优化字体选择框。

- 公开书库设置只提供「添加加密书库」；先打开加密书库后，才显示「修改当前书库密码」标签。
- 各加密书库没有主副之分，新增时无需其他书库密码；密码提示统一为「至少 4 个字符」。
- 改密与添加表单分开，明确操作范围；达到 2 个书库时提示数量上限。
- 字体选择框增加内边距与高度，统一圆角及下拉箭头间距。

Personal Developer ID signing, Apple notarization, and macOS automatic updates.

- macOS: Apple Silicon (arm64), macOS 13 deployment target. Open the DMG and drag FishTouching Reader to Applications, or install from the notarized ZIP. The app and disk image carry stapled Apple notarization tickets and use Tengjiao Ji's personal Developer ID (DR4WPFLXBN). macOS may still ask for normal first-open confirmation.
- Sparkle checks for updates and verifies signed downloads. Use Check for Updates… in the app menu. Existing versions without Sparkle require one manual installation; a full old-to-new update installation has not yet been independently verified.
- Homebrew libsodium may target a newer macOS version. Older macOS compatibility has not been verified on real hardware.
- Windows: x64 NSIS Setup.exe installer with in-app updates, plus portable ZIP; both unsigned. Extract completely before running the executable. SmartScreen may warn about an unknown publisher. Existing ZIP users must install Setup.exe once to enable updates. Updates use HTTPS and SHA-512 integrity checks, without Windows publisher signature verification.
- Libraries and reading progress remain in their existing platform-specific locations. macOS and Windows libraries are independent and do not automatically synchronize.
- Both packages preserve project and third-party license notices. SHA256SUMS.txt provides checksums.
