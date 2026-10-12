# macOS signing, notarization, and updates

FishTouching Reader uses only the personal identity
`Developer ID Application: Tengjiao Ji (DR4WPFLXBN)` associated with the owner's
Apple account `397879704@qq.com`. The signing script rejects other identities and
verifies the final application's authority and Team ID. Company certificates,
organization repositories, and company distribution infrastructure are not used.

## Deploy workflow

Run **Deploy** on `main` in the personal `YouDiSN/fishtouching-reader` repository.
Increment `windows/package.json` and its lockfile's root version before each
release. The macOS bundle, Windows artifact, and GitHub Release use that shared
version. Released versions are immutable; use a new version instead of replacing
an existing release.

The workflow builds macOS on an Apple Silicon runner, runs the signed app's
self-tests, signs all Sparkle helpers with hardened runtime and a secure timestamp,
notarizes the app and DMG, staples and validates both tickets, and checks Gatekeeper.
The Windows job runs storage tests and Electron smoke tests before and after
packaging. Publication waits for both jobs, uploads both platform packages and the
signed update feed to a draft, then publishes it as the latest release.

Required GitHub Actions secrets:

| Secret | Purpose |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Base64-encoded personal Developer ID Application identity |
| `MACOS_CERTIFICATE_PASSWORD` | Password protecting that P12 |
| `APPLE_NOTARY_KEY` | Personal team's App Store Connect API private key |
| `APPLE_NOTARY_KEY_ID` | ID of that API key |
| `APPLE_NOTARY_ISSUER` | Issuer of that API key |
| `SPARKLE_PRIVATE_KEY` | Dedicated FishTouching Reader Ed25519 update-signing key |

Credentials are stored as encrypted Actions secrets, imported into a temporary
runner Keychain, and removed in an always-run cleanup step. Never commit secrets,
certificate exports, user libraries, or private keys. Keep separate secure backups.
The public update key is committed in `Resources/sparkle-public-key.txt`.

## Local release

Store personal notarization credentials in a Keychain profile using Apple's
`notarytool store-credentials`. API-key authentication avoids Apple account
passwords. Then run:

```sh
./scripts/package-notarized-release.sh \
  'Developer ID Application: Tengjiao Ji (DR4WPFLXBN)' fishtouching-reader
./scripts/generate-appcast.sh
```

`SIGNING_KEYCHAIN` optionally selects a dedicated signing/notarization Keychain.
`SPARKLE_PRIVATE_KEY_FILE` optionally selects a protected update-key file; otherwise
Sparkle uses the `fishtouching-reader` account in the login Keychain.
The release script stages a default-named copy without renaming the local app.
`package-release.sh` remains available for ad-hoc development ZIPs; these are not
notarized release artifacts.

## Installation and updates

Open the DMG and drag the app to Applications. ZIP installation is also supported.
A notarized download may still show macOS's normal first-open confirmation.
The app checks the HTTPS feed in the latest personal GitHub Release using Sparkle
and exposes **Check for Updates…** in its application menu. Update archives carry
Ed25519 signatures in addition to Apple's code signature. Install/relaunch follows
Sparkle's user interface; updates do not change the library's storage location.

Versions before 1.0.2 do not contain an updater. Install the first updater-enabled
release manually. Windows still uses manual updates. App-name and icon preferences
remain outside the signed bundle; only the local app directory is renamed.

The macOS build is arm64 with a macOS 13 deployment target. Homebrew libsodium
may have a newer deployment target, so older macOS compatibility remains unverified.
A passing build or notarization does not establish older-system compatibility or
prove the complete old-to-new automatic-update installation flow.

References: [Apple Developer ID](https://developer.apple.com/developer-id/),
[Sparkle integration](https://sparkle-project.org/documentation/).
