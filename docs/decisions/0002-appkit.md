# 0002 — AppKit for the main interface

**Status:** accepted, October 23, 2026

## Context

Chord's interface has strict latency budgets (`docs/PERFORMANCE.md`) and potentially
long lists (more than a hundred tabs in the sidebar).

## Decision

The window, the sidebar, the command bar and everything on the critical path are
written in AppKit: `NSTableView` for lists (reused cells), Core Animation layers for
glass and shadows, explicit Auto Layout.
SwiftUI is still allowed for secondary screens (settings, about).

## Consequences

- More code than SwiftUI for the same interface.
- Direct control over what is recomputed and redrawn on each interaction.
- No dependency on SwiftUI's update machinery in the measured paths.
