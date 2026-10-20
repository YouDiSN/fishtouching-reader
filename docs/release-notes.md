v1.0.5：官方导入插件与 EPUB 支持。

- TXT、PDF、EPUB 作为官方插件默认启用，可在管理导入插件中启停。
- EPUB 按阅读顺序提取文字；加密书库保存原始 EPUB 并支持导出。
- 增加关于页面与个人 GitHub 链接，完善最近阅读移除操作。
- 补充社区插件 JSON 规范、ZIP/地址安装和开发验证文档。社区插件列表、安装及网址导入入口暂时隐藏，网站适配仍属实验功能，不作为本版可用功能承诺。
- 保留现有书库、阅读进度、常驻导航和自动更新能力。

Personal Developer ID signing, Apple notarization, and macOS automatic updates.

- macOS: Apple Silicon (arm64), macOS 13 deployment target. Open the DMG and drag FishTouching Reader to Applications, or install from the notarized ZIP. The app and disk image carry stapled Apple notarization tickets and use Tengjiao Ji's personal Developer ID (DR4WPFLXBN). macOS may still ask for normal first-open confirmation.
- Sparkle checks for updates and verifies signed downloads. Use Check for Updates… in the app menu. Existing versions without Sparkle require one manual installation; a full old-to-new update installation has not yet been independently verified.
- Homebrew libsodium may target a newer macOS version. Older macOS compatibility has not been verified on real hardware.
- Windows: x64 portable ZIP, unsigned. Extract completely before running the executable. SmartScreen may warn about an unknown publisher. Windows updates remain manual.
- Libraries and reading progress remain in their existing platform-specific locations. macOS and Windows libraries are independent and do not automatically synchronize.
- Both packages preserve project and third-party license notices. SHA256SUMS.txt provides checksums.
