# Accessibility

Chord is used from the keyboard first, like Arc, and must read well with VoiceOver.
Pages are Chromium's, with its own accessibility; this is about ChordUI.

## Rules

- Every control has a name (`setAccessibilityLabel`), in the interface's language, and
  its shortcut as help when it has one (`setAccessibilityHelp("⌘T")`).
- A row or a tile is one element: its title, with the rest as help or value. Its inner
  views are hidden (`setAccessibilityChildren([])`): VoiceOver would read the site's
  initial, the count and the shortcut one by one. An ignored view hands its children to
  its parent, so hiding a view means emptying its children too (`FaviconTileView`).
- What is decorative (the site tile, the mark) is not an element.
- State is a value, not a different label: the current Space says "Current Space".
- When the focus stays in a field while the result changes (the command bar's arrows),
  the change is announced (`NSAccessibility.post(… .announcementRequested …)`). So are
  the toasts.
- Custom views that act on a click answer `accessibilityPerformPress()`.

## The audit

`app/scripts/ax-audit.swift` walks the accessibility tree of a running Chord as
VoiceOver reads it, and lists controls without a name, images that say nothing and
single characters read on their own:

```bash
swift app/scripts/ax-audit.swift            # the running Chord
swift app/scripts/ax-audit.swift <pid> --tree
```

Only what is on screen is in the tree: open the command bar, a panel, a Peek, the
settings, then run it again. The terminal needs the Accessibility permission.

## Status (October 27, 2026)

Audited on a fresh profile: the welcome, the sidebar (tabs, folders, favorites, Spaces,
downloads, archive), the command bar and its cheat sheet, a Peek, the downloads panel and
a site's question. Fixed: site tiles read as their initial ("1" for 127.0.0.1), section
headers read in pieces ("TODAY", "2"), the New Tab row and command bar results read
three times (title, then each label inside), the current Space not told apart.

Still to check by hand with VoiceOver on: the order in which the window's parts are
reached with VO-arrows (sidebar, page, overlays), the Settings window (SwiftUI) and the
drag and drop of tabs, which has no keyboard equivalent yet besides ⌘D (pin) and the
tab's menu.
