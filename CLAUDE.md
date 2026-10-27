# Chord — context for Claude Code

Chord is an open source macOS browser, a successor to Arc, for developers.
A Chromium fork (based on ungoogled-chromium) whose interface is replaced by a native
Swift / AppKit interface. Kevin's solo project, developed with AI.

Read before any significant task:
- `docs/VISION.md`: product vision, priorities, v1 Arc parity, what we don't do
- `docs/ARCHITECTURE.md`: ChordUI / engine split, architecture rules
- `docs/PERFORMANCE.md`: latency budgets
- `docs/decisions/`: decisions already made and their reasons
- `design/`: reference mockups (exact values) and brand
- `engine/README.md`: spike 0 plan (Chromium integration)

## Build and run

Chord is Chromium (ungoogled-chromium) with ChordUI loaded into it. Once:

```bash
engine/scripts/bootstrap.sh && engine/scripts/prepare.sh
engine/scripts/build.sh          # several hours the first time; run again
                                 # when //chord or engine/patches change
```

Day to day, for the interface (a few seconds, without recompiling Chromium):

```bash
engine/scripts/run.sh            # recompiles ChordUI, puts it back into Chord.app, relaunches
```

To share: `build.sh --release`, `package.sh`, `release.sh` (`docs/RELEASING.md`).

In Xcode, the **Chord** scheme does the same: Build (⌘B) or Run (⌘R) compiles
ChordUI, installs it into Chord.app and relaunches Chord (log: `app/build/run-chord.log`).

`Chord.xcodeproj` is generated from `app/project.yml` and ignored by git: edit
`project.yml`, never the project. After a code change, always recompile and fix the
errors before handing back.

## Rules

- **ChordUI knows no engine.** Never a Chromium header (nor `import WebKit`) in
  `app/ChordUI`: everything goes through the `@objc` protocols in
  `app/ChordUI/Engine/ChordWebEngine.swift`, which `engine/chord` implements. Chromium
  is the only engine, development included (`docs/decisions/0004`).
- **ChordUI never creates `NSApplication`**: in the real browser, Chromium owns it.
- **AppKit, not SwiftUI**, for everything on the critical path (window, sidebar,
  command bar). SwiftUI is tolerated for settings.
- **Smoothness is measured.** Every significant new interaction opens a
  `Perf.begin(...)` interval and has a budget in `Perf.budgets`. Don't exceed the
  budgets.
- **Beautiful and smooth first.** No big new feature until the foundation is flawless.
  No AI added to the interface.
- **Faithful to Arc for UX** (shortcuts included), with its own visual personality:
  calm, premium, native, in the spirit of Safari. Glass (NSVisualEffectView) rather
  than flat colors.
- **Shortcuts**: all declared in `app/ChordUI/Menu/MainMenu.swift`.
- **Concurrency**: Swift 5, `SWIFT_STRICT_CONCURRENCY = minimal`. No explicit
  `@MainActor` annotations on ChordUI types for now.
- Code, comments and documentation in English. The interface is localized in English,
  French and Spanish: every visible string goes through
  `String(localized: "…", bundle: .chordUI)` and gets its French and Spanish in
  `app/ChordUI/Localizable.xcstrings` (Xcode's string catalog editor, or by hand). A
  new string without its translations is not done.
- **Changelog**: every change visible to users (feature, fix, behavior, language) adds
  a line under "Unreleased" in `CHANGELOG.md`, in the same commit.
- On the Chromium side: Chord's code lives in `//chord`, patches stay tiny and isolated
  (`engine/patches/README.md`), to absorb a major version every four weeks.

## Current state

- Complete native interface (ChordUI), on Chromium: translucent glass window (inactive
  too), draggable from all the empty space of the sidebar, resizable sidebar, profiles
  like Arc (each profile is a real Chromium profile: separate session, cookies,
  extensions and favorites; a new Space gets its own), pinned tabs with folders, real
  site icons (disk cache, taken from Arc on import), drag and drop of tabs and folders
  (order, folders, pin, favorites, another Space, links from other apps), Spaces
  (color, name, ⌃1…⌃9, two-finger swipe that follows the fingers like Arc), favorites in
  a grid with full rows, command bar (compact over the address field on click or ⌘L,
  like Arc), Peek (⇧-click, links leaving a pinned tab), split view (⌃⇧=, 2 to 4
  panes), little window (⌥⌘N, links from other apps), address bar on top or in the
  sidebar (⇧⌘D, copy the URL on hover with confirmation), light/dark mode, edgeless,
  settings (⌘,) with remappable shortcuts, Arc import (sidebar, then logins, passwords,
  history and site data of each Arc profile into the Chord profile of its Spaces), home
  page (when no tab is open: closing a tab goes back to the last tab still active, never
  to a sleeping tab), downloads (Arc-style panel, ⇧⌘J), session.
- **Chord on Chromium** (spike 0, `engine/`): ChordUI runs in Chromium 155
  (ungoogled-chromium), built by `engine/scripts/build.sh`. Verified: pages show in
  Chord's windows, extensions work (content scripts, `chrome.tabs`, tabs opened by an
  extension adopted by ChordUI), DevTools (⌥⌘I) docked in the window on the right, left
  or bottom, or in their own window.
- Multiple windows (⌘N) on the same Spaces, each with its own Space and selected tabs
  (`WindowSelection`); private browsing (⇧⌘N) on Chromium's incognito profile, dark
  window, nothing saved; ⌘← / ⌘→ for history (except while typing text).
- Picture in picture like Arc: a playing video moves into Chromium's PiP window
  (floating, movable, resizable) when its tab leaves the screen, and comes back when it
  returns; "back to tab" selects the tab in ChordUI; ⌃⌘P by hand; "Automatic picture in
  picture" setting.
- Page permission requests: a small discreet bubble at the top of the page, like Arc
  (Block / Allow), which doesn't block the page; double-click on the PiP video or "back
  to tab": the tab comes back, Space included.
- Site settings like Arc (button in the address field, sidebar or top bar): a card with
  share, copy, developer tools, the extensions (tiles with badges; click = popup, right
  click = pin, options, manage, remove), the permissions chosen for the site and a link
  to all of the site's settings. Pinned extensions have their button in the address
  field; their popups open in a native bubble (//chord hosts the `ExtensionViewHost`).
- `chord://` for Chromium's internal pages (`chord://settings`, `chord://extensions`,
  also in the command bar).
- After a crash, the next launch writes a readable report to
  `~/Library/Logs/Chord/latest-crash.md` (stack of the faulting thread, Chromium's error
  message if there is one, caught by //chord in `last-fatal.txt`) and offers it.
- Find in page (⌘F, a glass bar at the top right of the page, Chromium's search), zoom
  per site (⌘+ / ⌘- / ⌘0), the Mac's print dialog (⌘P), view source (⌥⌘U).
- Passwords: "Save password?" and "Update password?" in Chord's prompt (routed from
  `ManagePasswordsUIController`, chord-password-prompt.patch); saving and form
  autocomplete are on by default (ungoogled-chromium turns them off); Chromium's
  suggestion list fills the fields; email-first sign-ins get the saved usernames
  without Google's server (chord-username-first.patch). The Arc import also brings
  the values typed in forms.
- Translation with Apple's on-device Translation framework (macOS 26), in ChordUI
  (`PageTranslator`), paragraph by paragraph with tagged pieces, on-screen content
  first, the rest on scroll (it takes seconds per paragraph): a page in a language the
  Mac does not list is offered a
  translation; View › Translate Page / Show Original, and a switch in the site settings
  card. No Google service.
- Sleeping tabs keep their history, scroll position and forms (Chromium's tab
  discarding, woken when shown); tabs playing sound or using the camera, microphone or
  screen stay awake. A speaker in the sidebar mutes a tab playing sound.
- Not yet on the Chromium side: Peek on ⇧-click, downloads in Chord's panel, video full
  screen in the interface.
- Sharing: Chord signed with the Mac's best certificate (`engine/scripts/sign.sh`), data
  in `~/Library/Application Support/Chord` (older builds' data is moved there and
  re-encrypted with the keychain key), Chord's name and icon everywhere, Chrome Web
  Store and components (Widevine) restored, Sparkle updates, `package.sh` (disk image)
  and `release.sh` (GitHub release), see `docs/RELEASING.md`. No Developer ID yet: no
  notarization. Version 0.1.0 is published.
- Interface in English, French and Spanish, following the Mac's languages (or the
  per-app language in System Settings). Chromium's own parts (internal pages, page
  context menus, permission wording) follow the same setting with Chromium's own
  translations.
- License: GPL-3.0 (`LICENSE`, decision 0005).
