# Chord

The browser for the people who build the web: a successor to Arc, native to the Mac,
on Chromium. The interface is written in Swift / AppKit; the engine is
[ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium).

> **Status: preview.** Chord is used every day by its author, but anything can still
> change. Apple Silicon Mac, macOS 14 or later.

## Install

Download `Chord-<version>.dmg` from the
[releases](https://github.com/kevbesset/Chord/releases/latest), open the image and drag
Chord into Applications. Chord then updates itself (it checks once a day and installs
at the next launch; "Check for Updates…" in the Chord menu checks right away).

Until Chord is notarized by Apple, macOS refuses to open it the first time: System
Settings › Privacy & Security › "Open Anyway". Or, in a terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Chord.app
```

## What it does

- Arc-style sidebar: favorites, pinned tabs with folders, today's tabs, Spaces (each on
  its own profile, two-finger swipe to go from one to the next)
- Command bar (⌘T, ⌘L), Peek, split view, little window for links from other apps
- Import from Arc: sidebar, logins, passwords, history, site data, Chrome Web Store
  extensions
- Chrome extensions, pinnable in the address bar; docked DevTools (⌥⌘I)
- Automatic picture in picture, discreet permission requests, site settings
- Private browsing, multiple windows, light / dark mode, remappable shortcuts
- In English, French and Spanish, following the Mac's language

## Build

Requirements: Apple Silicon Mac, Xcode 16 or later, Homebrew, about 100 GB of free
space. The first Chromium build takes several hours.

```bash
brew install xcodegen
engine/scripts/bootstrap.sh && engine/scripts/prepare.sh
engine/scripts/build.sh          # Chromium and ChordUI: out/Chord/Chord.app
engine/scripts/run.sh            # day to day: the interface alone, in a few seconds
```

Details in `engine/README.md`. Publishing a version: `docs/RELEASING.md`.

## Structure

```
app/                Native interface (Swift, AppKit)
  ChordUI/          framework: window, sidebar, Spaces, command bar.
                    Knows no engine, only the ChordWebEngine protocol.
  project.yml       Xcode project definition (XcodeGen)
engine/             Chromium: pinned version, //chord, patches, brand, scripts
docs/               Product vision, architecture, performance budgets, decisions
design/             Reference mockups and brand (logo, icon)
CLAUDE.md           Project context for Claude Code
```

## License

Chord is distributed under the GNU General Public License, version 3 (`LICENSE`).
Chromium and ungoogled-chromium, which it builds on, keep their own licenses (mostly
BSD); Chord lists them in `chord://credits`. Sparkle (updates) is under the MIT
license.
