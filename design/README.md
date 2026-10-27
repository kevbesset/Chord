# Design

## Mockups

`mockups/` holds the source of the interface mockups, one per screen.
They are HTML files from a design tool: they don't open as they are in a browser (they
lack their rendering engine), but they are the exact reference for colors, spacing,
radii, font sizes and shadows.

The visual, editable version is on the "Chord — Main window" canvas, in the artifact
gallery of Kevin's Claude account.

| File | Screen |
| --- | --- |
| `Main.dc.html` | Main window, command bar open |
| `TopBar.dc.html` | Variant: address bar on top, built into the page (32 px) |
| `Collapsed.dc.html` | Sidebar collapsed (⌘S): only the frame and the page |
| `CollapsedHover.dc.html` | Collapsed, hovering the left edge: floating sidebar |
| `Edgeless.dc.html` | Edgeless mode (setting) |
| `Peek.dc.html` | Peek: a link previewed over the page |
| `Split.dc.html` | Split view (⇧⌘D) |
| `Dark.dc.html` | Dark mode |
| `Desktop.dc.html` | On a wallpaper: glass test with a colorful page |
| `Little.dc.html` | Little floating window (⌥⌘N) |
| `LogoConcepts.dc.html` | The three brand directions explored |
| `AppIcon.dc.html` | App icon at every size |
| `Wordmark.dc.html` | Logo light, dark, monochrome, tagline |

## Brand

`brand/chord-mark.svg` (the symbol) and `brand/chord-app-icon.svg` (the app icon at
1024 px): the arc and its chord. The arc takes the text color, the chord the accent
(`#5B6CFF` by default, or the active Space's color in the app).

## Reference values

| Element | Value |
| --- | --- |
| Sidebar width | 256 px |
| Margin around the content card | 10 px (0 in edgeless) |
| Card radius | 10 to 12 px |
| Space tint on the glass | 7% of the Space's color |
| Tab row height | 32 px |
| Command bar | 680 px wide, radius 16, 44 px results |
| Space palette | `#5B6CFF` `#2E7D4F` `#B4530A` `#6E56CF` `#0E7490` `#C2410C` |
| Font | SF Pro (system) |
