# 0006 — One menu bar: ChordUI's

**Status:** accepted, October 27, 2026.

## Context

Chromium builds its own main menu at startup (`chrome::BuildMainMenu`), with its
commands (`IDC_*` tags dispatched through `commandDispatch:`) and bridges that keep it up
to date (bookmarks, history, tabs, profiles). ChordUI builds another one
(`app/ChordUI/Menu/MainMenu.swift`) and installs it once it starts. Two choices were
open: wire Chromium's menu to ChordUI's commands, or let ChordUI's replace it.

## Decision

ChordUI's menu is the only one. Every shortcut is declared in `MainMenu.swift`, can be
remapped in the settings, and travels the responder chain to ChordUI's windows.
Chromium still builds its menu at startup (its app controller and profile menu expect
the items to exist), but it is replaced before the first window shows, and its
bookmarks and history bridges are off (`chord-app-controller.patch`).

The windows that stay Chromium's (undocked developer tools, a site's popup, the
picture-in-picture window) get the standard commands from the menu's own selectors
(copy, paste, minimize, close window), and ⌘W closes them, through a fallback on
`NSApplication` (`closeTab:`) that only answers when no Chord window took the command.

## Consequences

- One place for shortcuts, in the same order as Arc's menus; nothing of Chromium's menu
  shows, and its commands are reached only from Chord's own code.
- Keys a page does not use go back to ChordUI's menu (`ChordBrowserWindow::HandleKeyboardEvent`).
- Chromium's menu-only features (its Bookmarks and History menus, the profile menu) are
  not shown: Chord has its own sidebar, command bar and Spaces for them.
