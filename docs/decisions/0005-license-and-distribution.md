# 0005 — GPL-3.0, releases on GitHub, updates through Sparkle

**Status:** accepted, October 26, 2026.

## Context

Chord must be shareable: a built, signed app that updates itself. The repository is
becoming public, so it needs a license before the first outside contributor. There is
no paid Apple Developer account yet, so no Developer ID certificate and no
notarization.

## Decision

- **License: GPL-3.0.** Chord's code stays free, derivatives included. It is compatible
  with the licenses of Chromium (BSD and similar) and Sparkle (MIT), which remain those
  of their own code.
- **Distribution: the repository's GitHub releases** (`engine/scripts/release.sh`), one
  disk image per version, Apple Silicon only.
- **Updates: Sparkle 2**, an `appcast.xml` feed attached to each release and read from
  the latest one (`releases/latest/download/appcast.xml`), signed with EdDSA. Daily
  check, silent install at the next launch, like Arc.
- **Version**: `VERSION` holds the displayed number; the build number counts commits,
  which makes it grow from one version to the next.
- **Signing**: `engine/scripts/sign.sh` takes the best certificate available
  (Developer ID, else Apple Development, else ad hoc). Signed with a certificate, Chord
  keeps the same identity from one build to the next and stores its encryption key in
  the real keychain ("Chord Safe Storage"); ad hoc, in Chromium's mock keychain.

## Consequences

- Without a Developer ID, macOS asks to allow Chord the first time it opens (Privacy &
  Security). `package.sh` notarizes as soon as a certificate and notarytool credentials
  exist, with no other change.
- Sparkle's private key is in Kevin's login keychain: losing it means no longer being
  able to publish an update that installed Chords accept. It is backed up with
  `sparkle-tool.sh generate_keys -x <file>`.
- Chrome Web Store extensions and components (Widevine…) go through Google's servers,
  which ungoogled-chromium cut off: they are the only ones.
