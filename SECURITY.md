# Security

Chord is a browser: a security issue in it can expose the people who use it. Thank you
for reporting one privately.

## Reporting a vulnerability

**Don't open a public issue.** Use GitHub's private reporting instead:
[Report a vulnerability](https://github.com/kevbesset/Chord/security/advisories/new)
(the repository's *Security* tab, then *Report a vulnerability*). Only Kevin sees it.

Say what is affected, the Chord version (Chord › About Chord) and the macOS version,
how to reproduce it, and what an attacker could do with it. You will get an answer
within a week. Once a fix is published, the advisory is made public, with your name if
you wish.

## What is in scope

- ChordUI, the native interface (`app/ChordUI`), and Chord's code in Chromium
  (`engine/chord`, `engine/patches`).
- The way Chord is built, signed, packaged and updated (`engine/scripts`, Sparkle's
  appcast).

A vulnerability in Chromium itself belongs to the [Chromium project](https://www.chromium.org/Home/chromium-security/reporting-security-bugs/),
and one in ungoogled-chromium's changes to [ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium).
Chord follows Chromium's major versions every four weeks. If you are unsure where an
issue belongs, report it here: it will be forwarded.

## Supported versions

Only the latest release receives fixes. Chord updates itself (Sparkle): stay on the
latest version.
