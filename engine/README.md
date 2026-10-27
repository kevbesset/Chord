# Engine: Chromium

Chord builds on [ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium)
(BSD-3 license), a version of Chromium without Google services. The version is pinned
in `UPSTREAM`.

## Spike 0 — the first technical milestone

**Nothing else is built on the engine side until it holds.**
Done when, in a ChordUI window:

1. a web page shows, rendered by Chromium;
2. DevTools open (⌥⌘I);
3. an extension loaded from `chrome://extensions` (developer mode) works.

### Building

```bash
engine/scripts/bootstrap.sh    # prerequisites (Homebrew: ninja, coreutils, go, esbuild,
                               # typescript, python@3.13) + ungoogled-chromium-macos
engine/scripts/prepare.sh      # Chromium sources (archive), ungoogled patches, tools
engine/scripts/build.sh        # ChordUI.framework, then Chromium with //chord
engine/scripts/run.sh          # day to day: ChordUI alone, put back into Chord.app
```

`build.sh` produces `engine/vendor/ungoogled-chromium-macos/build/src/out/Chord/Chord.app`,
with ChordUI.framework in `Contents/Frameworks`. `run.sh` only recompiles ChordUI (a
few seconds), replaces it in the app and relaunches Chord; without a Chromium build, it
uses a copy of the latest release instead (`CONTRIBUTING.md`). Development settings
(`engine/chord.gn`): no LTO, no PGO, no symbols. The first build takes several hours;
the next ones only recompile what changed.

Good to know:

- **macOS SDK 26.5.** The linker that ships with Chromium 155 can't read Xcode 27's
  macOS 27 SDK. The scripts use the Command Line Tools one
  (`/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`), linked into the output
  folder for GN.
- **No precompiled headers**: they fail with ungoogled-chromium's clang.
- `prepare.sh` picks up where it stopped (`.chord-step-*` markers in the sources).

### How Chord plugs in (steps 2 to 5)

- **`//chord`** (`engine/chord`, linked as `src/chord`): GN target `//chord:browser`,
  linked into the browser by a patch (see `patches/`).
- **Startup**: `ChordBrowserMainExtraParts` stops Chromium from opening its window
  (`--no-startup-window`), then, once the browser has started, loads
  `ChordUI.framework` and calls `ChordUIHost.start(engine:…)`. Chromium keeps
  `NSApplication` and its delegate; the installed menu is ChordUI's.
- **Window**: the `BrowserWindow::CreateBrowserWindow` factory gives normal browsers a
  `ChordBrowserWindow`, with no Views view, modeled on `WebUIBrowserWindow`. We keep
  `Browser` and `TabStripModel`, which extensions, DevTools and tab features depend on;
  DevTools, popups and apps keep their Chromium windows.
- **Bridge**: `ChordEngine` (conforming to `ChordWebEngine`) creates each page as a tab
  of its `Browser`; `ChordPage` (conforming to `ChordWebPage`) wraps the `WebContents`
  and hands its native view to ChordUI. Tabs that Chromium opens or closes itself (link
  in a new tab, `window.open`, extension, `window.close()`) go up to ChordUI through
  `ChordWebEngineDelegate`. The tab selected in ChordUI becomes Chromium's active tab.
- **ChordUI is not linked into Chromium**: it is loaded at runtime and reached through
  the Objective-C runtime (`NSClassFromString(@"ChordUIHost")`). The protocols have
  fixed Objective-C names, mirrored in `engine/chord/browser/chord_ui.h`.

## Status (October 24, 2026)

Chord runs on Chromium 155. Verified through the DevTools protocol: pages show in
ChordUI's windows (little window included); an unpacked extension injects its content
scripts into Chord's pages; `chrome.tabs` sees Chord's tabs; a tab created by an
extension appears in today's tabs. DevTools (⌥⌘I) dock into Chord's window: they fill
the page area (`PageHostView` in ChordUI) and the page takes the space their layout
leaves it, as in Chromium's `DevtoolsUIController`.

In a development build signed ad hoc, the cookie encryption key is in a mock keychain:
otherwise macOS asks for keychain access on every build (the signature changes) and
every page load waits for the answer.

## Known items to handle

- **Not wired yet**: Peek on ⇧-click and links leaving a pinned tab (a
  `NavigationThrottle` in `//chord`), downloads into ChordUI's panel, video full screen
  in the interface (hide the sidebar).
- **Main menu**: Chromium builds its own. Choose between replacing it with ChordUI's
  and wiring its commands to ChordUI's.
- **Updates**: a major Chromium version every four weeks. `UPSTREAM` changes, the
  patches in `patches/` are reapplied.

Done since: Chord's icon, the Chrome Web Store and Widevine (see `patches/README.md`).
