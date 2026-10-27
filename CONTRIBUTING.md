# Contributing to Chord

Thank you for wanting to help. Chord is made by one person, Kevin Besset, who keeps the
final say on what goes in: this keeps the browser coherent, calm and fast. Contributions
are welcome within that frame, and this page says how to make one that gets merged.

## What is welcome

| | |
|---|---|
| **Bug reports** | Always. Use the bug template; attach `~/Library/Logs/Chord/latest-crash.md` after a crash. |
| **Bug fixes** | A pull request directly, with the issue it fixes if there is one. |
| **Translations** | Corrections to the French and Spanish strings, directly. A new language: open an issue first. |
| **Performance** | Anything that brings an interaction back under its budget ([`docs/PERFORMANCE.md`](docs/PERFORMANCE.md)). |
| **Features** | **An issue first, and wait for a yes** before writing code. Chord follows a deliberate plan ([`docs/VISION.md`](docs/VISION.md)): "beautiful and smooth first", Arc parity before anything new, no AI in the interface. A feature pull request without an agreed issue will likely be closed, however good it is. |

Not sure? Ask in [Discussions](https://github.com/kevbesset/Chord/discussions).

Security issues never go in a public issue: see [`SECURITY.md`](SECURITY.md).

## Before your first pull request: the CLA

Every contributor signs the [Contributor License Agreement](CLA.md) once. You keep the
copyright on your work; you allow Kevin to distribute it, under GPL-3.0 and, if the
project ever needs it, under other licenses. A bot asks you to sign it in your first
pull request: you reply with one sentence in a comment.

## Getting set up

Requirements: an Apple Silicon Mac, Xcode 16 or later, Homebrew, and
`brew install xcodegen`.

### Working on the interface (most contributions)

ChordUI, the whole interface, is a Swift framework loaded into Chord at run time. You
don't need to build Chromium to work on it:

```bash
engine/scripts/run.sh
```

Without a Chromium build of your own, `run.sh` downloads the latest Chord release once
(about 180 MB, into `app/build/prebuilt/`), puts your ChordUI build into that copy and
launches it. Your copy has its own data folder (`app/build/prebuilt/data`), so it never
touches the Chord you browse with; ChordUI's settings (shortcuts, appearance) are shared
with it. Run it again after each change: a few seconds. In Xcode, the **Chord** scheme
does the same (⌘R).

This works as long as your change needs nothing newer on the Chromium side than the
latest release. If Chord crashes on launch with an "unrecognized selector" in
`latest-crash.md`, `main` has moved past the release on the engine side: build Chromium
(below), or work from the release's tag. `engine/scripts/run.sh --update-prebuilt`
fetches a newer release.

### Working on the engine

Changes to `engine/chord` or `engine/patches` need a full Chromium build: about 120 GB
of free space and several hours the first time.

```bash
engine/scripts/bootstrap.sh && engine/scripts/prepare.sh
engine/scripts/build.sh
engine/scripts/run.sh
```

Details in [`engine/README.md`](engine/README.md).

## The rules of the code

Read [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) before a significant change; the
decisions already made and their reasons are in [`docs/decisions/`](docs/decisions/).
In short:

- **ChordUI knows no engine.** No Chromium header and no `import WebKit` in
  `app/ChordUI`: everything goes through the `@objc` protocols in
  `app/ChordUI/Engine/ChordWebEngine.swift`, which `engine/chord` implements.
- **AppKit, not SwiftUI**, for everything on the critical path (window, sidebar,
  command bar). SwiftUI is tolerated for settings.
- **Smoothness is measured.** A significant new interaction opens a `Perf.begin(...)`
  interval and has a budget in `Perf.budgets`. A change that goes over a budget doesn't
  ship.
- **Faithful to Arc for UX**, shortcuts included, with Chord's own look: glass
  (`NSVisualEffectView`) rather than flat colors. All shortcuts are declared in
  `app/ChordUI/Menu/MainMenu.swift`.
- **Swift 5**, `SWIFT_STRICT_CONCURRENCY = minimal`, no `@MainActor` annotations on
  ChordUI types for now.
- **Edit `app/project.yml`, never `Chord.xcodeproj`**: the project is generated from it
  (and ignored by git).
- **Chromium patches stay tiny and isolated** ([`engine/patches/README.md`](engine/patches/README.md)):
  Chord absorbs a new Chromium major version every four weeks. Code goes in `//chord`
  whenever it can.
- Write code that reads like the code around it: same naming, same comment density.

## Every pull request

- **English** for code, comments, documentation and commit messages.
- **Every visible string is localized**: `String(localized: "…", bundle: .chordUI)`, with
  its French and Spanish in `app/ChordUI/Localizable.xcstrings` (Xcode's string catalog
  editor, or by hand). Building adds new strings to the catalog: commit it with your
  change. A string without its translations is not done; CI checks it.
- **A line in [`CHANGELOG.md`](CHANGELOG.md)** under "Unreleased" for every change users
  can see (feature, fix, behavior, wording), in the same commit.
- **It builds, and you tried it**: `engine/scripts/run.sh`, then the interaction you
  changed, in light and dark mode. Say in the pull request what you checked.
- **One subject per pull request**, small enough to review in one sitting. A short
  commit message in the style of the history (`git log --oneline`): what changes, from
  the user's point of view when there is one.
- Screenshots or a short video for any visual change.

Pull requests are squashed when merged. Kevin reviews every one; it can take a few days.
A pull request that isn't merged isn't a judgment on you: it may simply not fit the plan
right now.

## Working with AI

Chord is developed with AI, and so can your contribution be. [`CLAUDE.md`](CLAUDE.md)
gives coding assistants the project's context and rules. You remain responsible for
what you submit: read it, build it, try it.

## Conduct

Be kind and assume good faith. See the [Code of Conduct](CODE_OF_CONDUCT.md).
