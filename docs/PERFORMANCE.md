# Performance budgets

Smoothness is a measured rule. Every interaction has a budget; a feature that exceeds
it does not ship.

| Interaction | Signpost | Budget |
| --- | --- | --- |
| Open the command bar | `commandbar.open` | 50 ms |
| Collapse or expand the sidebar | `sidebar.toggle` | 50 ms |
| Select a tab | `tab.select` | 100 ms |
| Switch Spaces | `space.switch` | 100 ms |
| Follow the swipe between Spaces (one step) | `space.swipe` | 8 ms |
| Open a Peek | `peek.open` | 100 ms |
| Enter or exit split view | `split.toggle` | 100 ms |
| Open a little window | `littlewindow.open` | 100 ms |
| Open the site settings | `sitecontrols.open` | 50 ms |
| Show a site's permission request | `permission.prompt` | 50 ms |
| Show an extension's popup, once loaded | `extension.popup` | 50 ms |
| Open the find bar (⌘F) | `find.open` | 50 ms |
| Show ⌘Q's question | `quit.confirm` | 50 ms |
| Launch to the first window | `app.launch` | 1,000 ms |
| Scrolling and animations | — | 120 fps on ProMotion, no dropped frames |

The budgets also live in the code, in `app/ChordUI/Support/Perf.swift`.
They measure up to the first display after the action, not just the code that runs.

## Measuring

Each interaction opens an `OSSignposter` interval (subsystem `app.chord`).

- **Instruments**: "Time Profiler" or "Animation Hitches" template, "Points of
  Interest" instrument. Each interval shows with its duration.
- **Terminal**: a budget overrun is logged as a warning.

```bash
log stream --predicate 'subsystem == "app.chord"' --level debug
```

## The gate

`engine/scripts/perf-gate.sh` launches Chord on a fresh data folder with
`CHORD_PERF_REPORT` set: ChordUI then replays the interactions above several times
(`BrowserWindowController+PerfReplay.swift`), writes every duration to a report and
quits. The script prints each interaction's median, 90th percentile and maximum next to
its budget, and fails when a median is over budget. Chromium is too big to build in
continuous integration, so the gate runs on a Mac: before each release
(`docs/RELEASING.md`) and after a change to an interaction. The swipe and the
permission, site controls and extension popup intervals need a person's gestures or a
site's question: they are measured in use, not replayed.

## Later

- The same measurements on Chromium's side (`WebContents` creation, first paint)
