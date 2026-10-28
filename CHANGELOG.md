# Changelog

What changes in Chord, version by version. Each change adds a line under
"Unreleased"; publishing a version renames that section after it
(`docs/RELEASING.md`). The format follows [Keep a Changelog](https://keepachangelog.com).

## Unreleased

### Added

- When a new version of Chord is downloaded, an "Update Chord" button shows above the
  Spaces, like Arc's: a click restarts Chord on it. Left alone, it installs at the
  next quit.
- ⌘Q asks before quitting, like Arc, on a glass card over the window: Quit (↩),
  Cancel (esc) or "Quit and Don't Ask Again" (Settings › General › Ask before quitting
  turns it back on). ⌘Q again quits.
- ⌘Y shows the browsing history (History › Show All History, or "History" in the
  command bar).

### Changed

- The archive no longer has a button at the bottom of the sidebar: it stays in
  File › Archived Tabs (⌥⌘A). The command bar's cheat sheet shows ⌘Y for the history
  in its place.

### Fixed

- Submitting a form with an address no longer crashes Chord: "Save address?" and
  "Update address?" now show in Chord's prompt at the top of the page, like a site's
  permission. Saving a card or an IBAN shows no prompt for now (it crashed too).

## 0.3.0 — 2026-10-27

Arc's archive, Peek and downloads wired to Chromium, imports from other browsers, a
welcome on first launch, and media controls in the sidebar.

### Added

- A welcome on first launch, on one glass panel: import from Arc or another browser,
  make Chord the default browser, and the shortcuts to know.
- Import from Google Chrome, Brave, Microsoft Edge, Vivaldi, Chromium and Safari
  (File › Import from Another Browser…, or Settings › General): each profile becomes a
  Space with its bookmarks bar as pinned tabs, and its logins, passwords, history and
  extensions come into that Space's profile. Safari gives its bookmarks and history
  once Chord has Full Disk Access.
- The archive, like Arc's: tabs closed with ⌘W, and today's tabs left unused for 12
  hours, go to the archive (⌥⌘A, or the box at the bottom of the sidebar), searchable,
  where a click opens them again. Settings › General › Archive today's tabs: 12 hours,
  24 hours, 7 days, 30 days or never. Archived tabs also show in the command bar.
- Media controls in the sidebar, like Arc's mini player: a tab playing sound or video
  out of sight shows above the Spaces, with play / pause and mute, and a click goes
  back to it.
- Each Space can have an emoji, shown in place of its dot (the Space's menu › Icon, or
  Settings › Spaces).
- A cheat sheet of the main shortcuts at the bottom of the command bar, as remapped in
  the settings.
- ⇧-click on a link opens it in a Peek, and a link leaving the site of a pinned tab or
  a favorite opens in a Peek too, so the tab stays on its page.
- Downloads appear in Chord's downloads panel as they run, saved to Downloads without
  asking where; a file the browser warns about waits there for "Keep".
- A video in full screen fills the window alone: no sidebar, toolbar or margins.

### Changed

- ⌘W in Chromium's own windows (developer tools in their own window, a site's popup)
  closes them: Chord's menu bar is the only one.
- VoiceOver reads the sidebar, the command bar and the welcome better: one element per
  row or tile, the current Space told apart, the result picked with the arrows read
  aloud, no more site initials read on their own.

### Fixed

- Pages show their true colors: they no longer blend with the window's glass, which
  washed them out (grey blacks, faded tints).
- Turning edgeless mode on or off no longer leaves the bottom of the page empty until
  a reload.

## 0.2.0 — 2026-10-27

The browser basics (find, zoom, print, passwords, autofill, muting), Chord as the
default browser, and an interface in English, French and Spanish.

### Added

- Chord can become the Mac's default browser: Settings › General › Default browser,
  or Chord › Make Chord the Default Browser (macOS asks to confirm).
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

- The home page sits in a landscape of misty blue ridges, with Chord's mark as its sun
  in light mode and its moon, among stars, in dark mode.
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
