# 0001 — Chromium fork, interface replaced

**Status:** accepted, October 23, 2026

## Context

Chord must keep Chrome extensions and DevTools: that is non-negotiable for developers.
Three ways to embed Chromium in a native app were compared.

| Option | Chrome extensions | DevTools | Effort |
| --- | --- | --- | --- |
| CEF (Chromium Embedded Framework) | Partial | Less integrated | Low |
| Electron | Partial | Yes | Low, but at odds with smoothness |
| Chromium fork, interface replaced | Complete | Complete | High |

## Decision

Fork Chromium (base: ungoogled-chromium), keeping the whole browser process
(`//chrome/browser`) and replacing Chrome's macOS interface with ChordUI.
In practice, a `ChordBrowserWindow` class implements Chromium's `BrowserWindow`
interface in place of `BrowserView`.

## Consequences

- Follow a major Chromium version every four weeks: patches must stay small and
  isolated in `//chord`.
- A first technical milestone, spike 0, before any other feature: a Chromium page in a
  ChordUI window, with DevTools and an extension that work.
- ungoogled-chromium disables installing from the Chrome Web Store and Widevine: they
  will have to be restored for extensions to install normally.
