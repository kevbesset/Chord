# Changelog

What changes in Chord, version by version. Each change adds a line under
"Unreleased"; publishing a version renames that section after it
(`docs/RELEASING.md`). The format follows [Keep a Changelog](https://keepachangelog.com).

## Unreleased

### Added

- The interface is in English, French and Spanish, following the Mac's language (or
  the language chosen for Chord in System Settings › General › Language & Region).
- Shortcut search in the settings understands French and Spanish key names ("maj",
  "espace", "mayús", "izquierda"…).
- Settings › General › Reset Chord: deletes everything Chord keeps on the Mac (Spaces,
  logins, history, extensions, settings, caches) and restarts it as on its first launch.

### Changed

- English is the default language of the interface, the documentation and the scripts
  (it was French).
- The home page greets with the time of day: morning, afternoon or evening.
- The address bar's place (on top of the page or in the sidebar, ⇧⌘D) belongs to the
  Space's profile: moving it changes only the Spaces on that profile. The setting in
  Settings › Appearance is the default for profiles that have not chosen.

### Fixed

- Searching shortcuts for the space bar ("ctrl space") found nothing.
- A long address no longer wraps onto several lines in the address bar: it stays on one
  line, cut at the end, and scrolls with the cursor while you edit it.

## 0.1.0 — 2026-10-27

First public preview, Apple Silicon, macOS 14 or later.

- Arc-style sidebar: favorites, pinned tabs with folders, today's tabs, Spaces (each on
  its own Chromium profile, two-finger swipe between them)
- Command bar (⌘T, ⌘L), Peek, split view (2 to 4 panes), little window for links from
  other apps
- Import from Arc: sidebar, logins, passwords, history, site data, Chrome Web Store
  extensions
- Chrome extensions (Chrome Web Store restored), pinnable in the address bar; docked
  DevTools (⌥⌘I); Widevine
- Automatic picture in picture, discreet permission requests, site settings
- Private browsing, multiple windows, light / dark mode, edgeless, address bar on top or
  in the sidebar, remappable shortcuts, downloads panel
- Signed with an Apple Development certificate (not notarized), updates through Sparkle
