# Publishing a version

A version is a signed disk image on the GitHub releases page, with the `appcast.xml`
that installed Chords read (decision 0005).

## Once

- The update key: `engine/scripts/sparkle-tool.sh generate_keys` creates it in the
  keychain (already done; the public key is in `engine/scripts/package.sh`). Back it up
  off the Mac: `engine/scripts/sparkle-tool.sh generate_keys -x sparkle-key` (ignored by
  git), then store the file somewhere safe (a password manager) and delete it.
- `gh auth login` with an account that can publish on `kevbesset/Chord`.
- Notarization (already done, team FK3PG5SKWL): a "Developer ID Application"
  certificate in the keychain (Xcode › Settings › Accounts › Manage Certificates), and
  `xcrun notarytool store-credentials chord-notary --apple-id … --team-id …` with an
  app-specific password from account.apple.com. `package.sh` then signs the image with
  the Developer ID and notarizes it on its own; builds made on the Mac keep the Apple
  Development certificate. The Developer ID certificate expires on February 1, 2027:
  versions signed before stay valid (secure timestamp), a new one is needed to sign
  after.
- Passkeys kept on the Mac (Touch ID, "Your Chord profile"), done on October 28,
  2026: the App ID `app.chord.Chord` and two provisioning profiles, made by Xcode
  (`xcodebuild -allowProvisioningUpdates`, the Apple account in Xcode › Settings ›
  Accounts): `engine/signing/DeveloperID.provisionprofile` ("Mac Team Direct
  Provisioning Profile: app.chord.Chord", until 2044) and
  `engine/signing/Development.provisionprofile` ("Mac Team Provisioning Profile: *",
  this Mac only, until October 2027). They are ignored by git: on another Mac, build
  and export (Developer ID) any app with that bundle id and team once, and copy the
  profiles from `~/Library/Developer/Xcode/UserData/Provisioning Profiles`. `sign.sh`
  embeds the profile and claims the keychain group
  `FK3PG5SKWL.app.chord.Chord.webauthn` that Chromium looks for; without a profile it
  leaves passkeys to phones and security keys. Passkeys from iCloud Keychain also need
  Apple to grant the "Web Browser Public Key Credential Requests" capability
  (developer.apple.com › Identifiers › app.chord.Chord › Capability Requests),
  requested on October 28, 2026 (request 5G4Q8J6C8K, Apple answers by email); once
  granted, make the profiles again and `sign.sh` passes it on.

## For each version

```bash
# 1. the number in VERSION (0.1.0 → 0.2.0), "Unreleased" in CHANGELOG.md renamed
#    "<version> — <date>" (with a new empty "Unreleased" above), commit, push
engine/scripts/build.sh --release   # optimized Chromium (LTO): long the first time
engine/scripts/perf-gate.sh engine/vendor/ungoogled-chromium-macos/build/src/out/Release/Chord.app
                                    # every interaction within its latency budget
engine/scripts/package.sh           # dist/Chord-<version>.dmg, signed (notarized when possible)
engine/scripts/release.sh           # signed appcast, then asks before publishing
```

The release notes are that version's section of `CHANGELOG.md`: save it to a file and
pass it with `release.sh --notes <file>`.

`package.sh --dev` packages the development build, to try the chain without waiting
for a release build.

Before publishing, open the image, install Chord alongside and check that it launches,
that sites you were logged into still are, and that an extension installs.
