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
- Find in page (⌘F): a glass bar at the top right of the page highlights every match,
  with how many there are; ↩ and ⌘G go to the next one, ⇧↩ and ⇧⌘G to the previous one.
- Zoom (⌘+, ⌘-, ⌘0), remembered per site, with a toast showing the level.
- Print (⌘P), with the Mac's print dialog.
- View Source (⌥⌘U) opens the page's source in a new tab.
- Chord offers to save a password after you sign in, and to update it when it changed
  ("Save password?" from the address field, like a site's question). Saved passwords
  fill the sign-in forms, and the list under the field offers them, also on sign-ins
  that ask for the email first and the password on the next page.
- Fields offer again what you typed in them before (emails, names), like Chrome and
  Arc; importing from Arc brings over what you typed in Arc's forms.
- A speaker shows on tabs and favorites playing sound; click it, or use Mute Tab in the
  Tabs menu or the tab's menu, to mute the tab.

### Changed

- Sleeping tabs keep their place: back on a tab put to sleep, its page comes back with
  its history, where it was scrolled and what was typed in its forms. Tabs playing
  sound or on a call (camera, microphone, screen sharing) no longer go to sleep.
- English is the default language of the interface, the documentation and the scripts
  (it was French).
- The home page greets with the time of day: morning, afternoon or evening.
- The address bar's place (on top of the page or in the sidebar, ⇧⌘D) belongs to the
  Space's profile: moving it changes only the Spaces on that profile. The setting in
  Settings › Appearance is the default for profiles that have not chosen.
- Pinned tabs and favorites remember the page they were pinned on, like Arc: browse
  away from it, close the tab, and it opens again on that page rather than the last one
  visited.

### Fixed

- The traffic lights sometimes moved back above the sidebar's first row (macOS lays
  the title bar out again when a page's title changes): they now stay level with it.
- Chord could crash when a site's question was open and the sidebar or the address bar
  moved just as its page left the window.
- A link opened in a new tab in the background (middle click, "Open Link in New Tab")
  stayed blank once its tab was selected.
- Some site icons stayed blank or wrong: an icon drawn with an emoji (a Figma file's),
  or one the page changes after loading. Chord now takes the icon Chromium renders, and
  a tab keeps its page's own icon (two Figma files, two icons).
- Searching shortcuts for the space bar ("ctrl space") found nothing.
- A tab selected in two windows left one of them blank for good. It now shows in the
  window you use, and the other window says it is open elsewhere and takes it back on
  a click.
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
