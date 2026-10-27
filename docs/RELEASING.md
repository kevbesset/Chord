# Publishing a version

A version is a signed disk image on the GitHub releases page, with the `appcast.xml`
that installed Chords read (decision 0005).

## Once

- The update key: `engine/scripts/sparkle-tool.sh generate_keys` creates it in the
  keychain (already done; the public key is in `engine/scripts/package.sh`). Back it up
  off the Mac: `engine/scripts/sparkle-tool.sh generate_keys -x sparkle-key` (ignored by
  git), then store the file somewhere safe (a password manager) and delete it.
- `gh auth login` with an account that can publish on `kevbesset/Chord`.
- Later, with an Apple Developer account: a "Developer ID Application" certificate in
  the keychain, and `xcrun notarytool store-credentials chord-notary --apple-id …
  --team-id …`. `package.sh` then notarizes on its own.

## For each version

```bash
# 1. the number in VERSION (0.1.0 → 0.2.0), commit, push
engine/scripts/build.sh --release   # optimized Chromium (LTO): long the first time
engine/scripts/package.sh           # dist/Chord-<version>.dmg, signed (notarized when possible)
engine/scripts/release.sh           # signed appcast, then asks before publishing
```

`package.sh --dev` packages the development build, to try the chain without waiting
for a release build.

Before publishing, open the image, install Chord alongside and check that it launches,
that sites you were logged into still are, and that an extension installs.
