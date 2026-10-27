<!-- Thank you! A feature needs an agreed issue first (CONTRIBUTING.md). -->

## What changes

<!-- From the user's point of view when there is one. "Fixes #123" closes the issue. -->

## How I checked it

<!-- engine/scripts/run.sh, then what you tried, in light and dark mode.
     Screenshots or a short video for any visual change. -->

## Checklist

- [ ] Visible strings go through `String(localized:bundle: .chordUI)`, with French and Spanish in `Localizable.xcstrings`
- [ ] A line under "Unreleased" in `CHANGELOG.md`, if users can see the change
- [ ] No Chromium header or `import WebKit` in `app/ChordUI`
- [ ] A significant new interaction has a `Perf.begin(...)` interval and a budget, and stays under it
