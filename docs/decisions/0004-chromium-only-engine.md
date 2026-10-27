# 0004 — Chromium, the only engine, development included

**Status:** accepted, October 24, 2026. Supersedes 0003.

## Context

Decision 0003 gave the interface a development app on WebKit (ChordDev), because every
change would otherwise have required recompiling Chromium. Spike 0 showed that this is
not the case: ChordUI.framework is not linked into Chromium, `//chord` loads it at
runtime. Recompiling the interface and putting it back into Chord.app takes a few
seconds. Two engines meant two behaviors to understand (the keychain, DevTools and
extensions only existed on one side).

## Decision

Chord runs only on Chromium, during development too. ChordDev and its WebKit engine are
removed. The daily loop is `engine/scripts/run.sh` (ChordUI alone);
`engine/scripts/build.sh` rebuilds Chromium when `//chord` or the patches change.

## Consequences

- What you see in development is what ships: extensions, DevTools, `chrome://`,
  rendering.
- Chromium must have been built once (several hours) before touching the interface.
- The architecture rule stays: ChordUI depends only on the `ChordWebEngine` /
  `ChordWebPage` protocols, which keeps the door open to other engines.
