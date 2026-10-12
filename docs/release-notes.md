v1.0.3: The app can hold two separate encrypted libraries, each opened by its own password. Existing libraries keep their original paths and data. Books and reading progress can be moved after the destination password is entered; the source is removed after verification. Password changes affect only the selected library. macOS uses the existing personal Developer ID notarized release flow; Windows remains unsigned.

Personal Developer ID signing, Apple notarization, and macOS automatic updates.

- macOS: Apple Silicon (arm64), macOS 13 deployment target. Open the DMG and drag FishTouching Reader to Applications, or install from the notarized ZIP. The app and disk image carry stapled Apple notarization tickets and use Tengjiao Ji's personal Developer ID (DR4WPFLXBN). macOS may still ask for normal first-open confirmation.
- Sparkle checks for updates and verifies signed downloads. Use Check for Updates… in the app menu. Existing versions without Sparkle require one manual installation; a full old-to-new update installation has not yet been independently verified.
- Homebrew libsodium may target a newer macOS version. Older macOS compatibility has not been verified on real hardware.
- Windows: x64 portable ZIP, unsigned. Extract completely before running the executable. SmartScreen may warn about an unknown publisher. Windows updates remain manual.
- Libraries and reading progress remain in their existing platform-specific locations. macOS and Windows libraries are independent and do not automatically synchronize.
- Both packages preserve project and third-party license notices. SHA256SUMS.txt provides checksums.
