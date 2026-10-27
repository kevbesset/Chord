# Architecture

Chord is a Chromium fork whose interface is replaced by a native interface written in
Swift. We keep everything Chromium does well (engine, Chrome extensions, DevTools,
profiles, passwords) and replace what users see.

## Overview

```
┌──────────────────────────────── Chord.app ────────────────────────────────┐
│  Chromium's browser process (NSApplication = BrowserCrApplication)         │
│                                                                            │
│   ChordUI.framework  — Swift, AppKit                                       │
│   windows, sidebar, Spaces, command bar, shortcuts                         │
│              ▲                                                             │
│              │  @objc protocols ChordWebEngine / ChordWebPage              │
│              │                                                             │
│   //chord  — Objective-C++, in Chromium's tree                             │
│   ChordBrowserWindow : BrowserWindow   (replaces BrowserView)              │
│   ChordPage : ChordWebPage             (wraps a WebContents)               │
│              │                                                             │
│   //chrome/browser   Browser, TabStripModel, extensions, profiles, DevTools│
│   //content          WebContents, renderer processes, GPU                  │
└────────────────────────────────────────────────────────────────────────────┘

ChordUI.framework is not linked into Chromium: //chord loads it at runtime. To work on
the interface, `engine/scripts/run.sh` recompiles ChordUI alone and relaunches Chord
(a few seconds, without recompiling Chromium).
```

## Rules

1. **ChordUI knows no engine.** It depends only on the protocols in
   `app/ChordUI/Engine/ChordWebEngine.swift`, never on Chromium or WebKit headers.
   That is what lets the interface recompile without Chromium, and other engines plug
   in later.
2. **ChordUI never creates `NSApplication`.** In the real browser, Chromium owns the
   application and the event loop (`BrowserCrApplication`). ChordUI provides windows
   and a menu, through `ChordUIHost`; Chromium installs them.
3. **ChordUI is the source of truth for organization**: Spaces, pinned tabs, "Today".
   On Chromium's side, one `Browser` per window and its `TabStripModel` hold all of the
   window's tabs, so that extension APIs (`chrome.tabs`, `chrome.windows`) work. The
   bridge keeps both in sync (verified: `chrome.tabs` sees Chord's tabs, a tab created
   by an extension arrives in ChordUI).
4. **The protocols are `@objc`** so that Objective-C++ classes can conform to them
   without going through Swift's C++ interoperability.

## ChordUI modules

| Folder | Role |
| --- | --- |
| `Engine/` | Protocols every engine implements |
| `Model/` | Spaces, favorites, tabs, split, selection, sleeping tabs, session, Arc import |
| `Window/` | Window, page area (split view, address bar on top), Peek, little window |
| `Sidebar/` | Sidebar: navigation, address, favorites, tab list, Spaces |
| `Settings/` | Settings window (SwiftUI, off the critical path) |
| `CommandBar/` | Command bar (⌘T, ⌘L) |
| `Menu/` | Main menu and keyboard shortcuts |
| `Support/` | Theme, performance measurements, settings, shared components |

## Why AppKit rather than SwiftUI

See `docs/decisions/0002-appkit.md`. In short: the sidebar must stay smooth with more
than a hundred tabs, animations must be interruptible, and every interaction has a
latency budget. AppKit gives direct control over all of that (`NSTableView` cell reuse,
layers, layout). SwiftUI remains possible for secondary screens such as settings.
