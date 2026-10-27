# 0003 — Temporary WebKit engine to develop the interface

**Status:** superseded by 0004 (October 24, 2026). Accepted on October 23, 2026

## Context

Compiling Chromium takes several hours and about a hundred gigabytes. Iterating on the
interface (an animation, a spacing) cannot depend on that cycle.

## Decision

ChordUI only talks to the `ChordWebEngine` / `ChordWebPage` protocols. The ChordDev app
implements them with WebKit (`WKWebView`), the engine that ships with macOS. It is only
used to develop the interface and is never distributed.

## Consequences

- Iterating on the interface in a few seconds.
- Everything specific to an engine stays out of ChordUI; the rule can be checked: no
  `import WebKit` in `app/ChordUI`.
- Web behavior (extensions, DevTools, rendering) can only be judged on the Chromium
  version.
- This split also prepares the multi-engine horizon: WebKit could become a real engine
  to choose, later.
