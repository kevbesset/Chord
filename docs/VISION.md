# Chord — Product vision

October 23, 2026 · Kevin

## Why Chord

Arc is an undead browser, and the space it leaves is empty. The Browser Company froze its development on May 27, 2025 to focus on Dia; Atlassian bought the company for $610M on October 21, 2025. Arc still works and still receives Chromium's security fixes, but it will get no new features and has no announced end date.

The gap in the market is precise: in 2026, no open source Chromium-based browser takes up Arc's full model (sidebar, Spaces, command bar, Peek, split view). The closest open source alternative, Zen, is based on Firefox. Vivaldi covers part of the scope but its interface is closed. And developers, Arc's historical core audience, never had a Linux version.

Chord aims for that space: the open source Arc, on Chromium, built for the people who build the web.

The project does not reverse-engineer Arc's binary: Arc's value is in its UX, not its code, and a clean-room rebuild (observe, document, reimplement) avoids any legal risk with Atlassian.

## Vision

**Arc, faster, open forever, and built for the people who build the web.**

Three beliefs guide every decision:

1. **A new Arc, modernized, smooth and very fast.** We take Arc's UX as it is, because it was good, and make it more beautiful and more responsive. No reinvention.
2. **Discreet AI.** No AI injected everywhere. That is exactly what the community held against Dia. AI will come, later, where it truly helps, never in the foreground.
3. **The browser for development and productivity.** Developer tools are the horizon that justifies the positioning, but they only come once the foundation is flawless.

The order of priorities is strict: first a very beautiful and very smooth browser, only then the big features.

## Audience and story

**Audience:** front-end and full-stack developers who juggle all day between localhost, staging, production, documentation, dashboards, pull requests and, more and more, their coding agents. And, from day one, Arc refugees looking for their sidebar.

**Story:** Arc was frozen because a company decided so. Chord is open source: whatever happens to the project, its code outlives it, and anyone can take it over. Chord can never disappear the way Arc did.

This story holds with any open source license and does not rule out an acquisition; it promises the code's survival, not the absence of an owner.

## Design principles

Chord takes Arc's UX but not its look: where Arc was colorful and playful, Chord is calm, premium and native, in the spirit of Safari.

1. **Content first.** The interface steps back; the web page is the star. The page floats in a card with rounded corners, and the sidebar collapses with one gesture.
2. **Material rather than color.** Native macOS translucent materials (NSVisualEffectView, the Liquid Glass language) instead of large flat colors. The wallpaper shows through the sidebar and the window frame. Each Space keeps its color, as a subtle tint (about 7%) and accents: active tab, Space dot, selected result in the command bar.
3. **Physical motion.** Spring animations, short and interruptible: you can change your mind mid-gesture.
4. **Native down to the details.** Interface in Swift, SF Pro typography, SF Symbols icons, standard macOS shortcuts and gestures. No Electron.
5. **Controlled density.** A developer has 40 tabs open: the sidebar must stay legible and elegant even when full.

The command bar is the centerpiece: translucent glass, grouped results (open tabs, actions, search), visible shortcuts, a cheat sheet at the bottom. It must be the fastest element of the browser.

The reference mockups (main window, variants, states, glass test) are on the "Chord — Main window" canvas.

## Latency budgets

Smoothness is a measured rule, not a promise: every interaction has a budget, checked automatically in continuous integration. A feature that exceeds its budget does not ship. The benchmark is well known: under 100 ms, an action feels instant.

| Interaction | Target budget |
| --- | --- |
| Open the command bar | < 50 ms |
| Switch Spaces | < 100 ms, stutter-free animation |
| Open a new tab | < 100 ms |
| Collapse or expand the sidebar | < 50 ms |
| Open a Peek | < 100 ms |
| Cold start | < 1 s to a usable window |
| Scrolling and animations | 120 fps on ProMotion, no dropped frames |
| Inactive tabs | put to sleep automatically to free memory |

These numbers are starting targets, to be refined with the first measurements on Apple Silicon.

## Arc parity for v1

An Arc user must feel at home from the first minute. v1 takes six features; Boosts will wait.

| Feature | What we keep from Arc | The Chord touch |
| --- | --- | --- |
| Sidebar | Vertical tabs, favorites, pinned, today's tabs, "New Tab" at the top of today's tabs | Translucent material; compact row with traffic lights + navigation + collapse; Spaces and downloads at the bottom; when collapsed, it comes back as a floating panel when hovering the left edge |
| Spaces | Separate contexts, swipe to switch | Subtle tint, switch < 100 ms |
| Command bar | Everything from the keyboard (⌘L) | The centerpiece: glass, grouped results, visible shortcuts |
| Peek | Preview a link without leaving the page | Floating spring window, "Open as Tab", direct split view |
| Split view | Several pages side by side (⌃⇧=) | Each pane has its own address; active pane outlined in the Space's color; resizing at 120 fps |
| Little window (Little Arc) | Small floating window for a link opened from another app (⌥⌘N) | Glass, "Open in Chord"; final name still to find |

Two address bar layouts are planned from v1: in the sidebar (default, like Arc) or built into the top of the page, 32 px high, with the actions on the right (Safari style).

**One-click import from Arc, at first launch.** Arc stores its sidebar (Spaces, favorites, pinned tabs, folders) in a local JSON file. At first launch, Chord detects it and offers to bring everything over as it is, with history, passwords and cookies as the import from Chrome does. This is probably the project's most effective acquisition feature: the Arc refugee gets their browser back in one click.

## Customization and shortcuts

Customization and keyboard shortcuts are pillars, not options. v1 takes Arc's customization tools and adds two.

**Customization (v1)**

- Color and name of each Space
- Light, dark or automatic mode
- Edgeless: the page against the edges, without rounded corners or shadow (new)
- Address bar: in the sidebar or above the page (new)
- Sidebar width
- Pinned favorites (4 to 8)
- Command bar theme
- Remappable shortcuts

**Default shortcuts**

| Shortcut | Action |
| --- | --- |
| ⌘L | Command bar |
| ⌘T | New tab |
| ⌘S | Collapse / expand the sidebar |
| ⌃⇧= | Split view |
| ⇧⌘D | Address bar on top or in the sidebar |
| ⌥⌘N | Little window |
| ⇧⌘C | Copy URL |
| ⌃Tab | Next tab |
| ⌥⌘← / → | Previous / next Space |
| ⇧⌘J | Downloads |
| ⌘W | Close tab (archive) |
| ⌘1 to ⌘9 | Pinned tab n |

Shortcuts are Arc's wherever Arc has one, so that former users have nothing to relearn.

## Technical choices

**Engine: Chromium, via ungoogled-chromium.** It is the only choice that fits the audience: developers live in Chrome DevTools and Chrome extensions. ungoogled-chromium (BSD-3 license) removes Google services and already provides a Mac packaging repository, ungoogled-chromium-macos; Helium, considered for a while, is built on the same base but under GPL-3, which would have fixed Chord's license. Helium's good ideas (built-in blocker, cleaned-up interface) can be reimplemented without copying its code.

**Integration: a Chromium fork with the interface replaced.** This is Arc's approach. We keep all of Chromium's browser process (Chrome extensions, DevTools, profiles, passwords) and replace Chrome's macOS interface with native Swift windows that host the web content. CEF (Chromium Embedded Framework), quicker to get started with, is ruled out: it does not include Chrome's browser layer and only partially supports extensions. No Electron either. Translucent materials go through NSVisualEffectView, animations through interruptible springs (CASpringAnimation).

**First technical milestone: spike 0.** A Swift window that shows a Chromium page, with DevTools and a Chrome extension that work. Nothing else is built until it holds.

**Platform: macOS only, Apple Silicon first.** Windows and Linux will come later, if the project finds its community.

**A cost not to underestimate:** following Chromium means absorbing a new major version every four weeks. Solo, this is the project's biggest risk; v1 must stay deliberately small.

**Multiple engines, later.** The architecture isolates the engine behind a common layer (history, cookies, downloads) so that WebKit (shipped with macOS, Safari's real engine) can be plugged in for a v2, then Gecko explored. This is not a v1 goal.

**Customizable DevTools.** The DevTools interface is a separate open source project (devtools-frontend, BSD-3), written in TypeScript with web components, and bundled into Chromium. In a fork, it can be modified entirely: rework the responsive mode, add panels, emulation options. It can be developed without recompiling Chromium, by serving it to a browser launched with the `--custom-devtools-frontend` flag. Maintenance rule: add modules rather than rewrite existing panels, so that the update every four weeks stays a simple rebase.

## Open source, license and business model

Chord is open source. That is the answer to Arc's problem: the code belongs to the community and outlives the project.

**License: GPL-3.0** (decision 0005). Chord's code stays free, derivatives included; Chromium, ungoogled-chromium and Sparkle keep their licenses (BSD, MIT). As long as Kevin owns 100% of the code, he can still change the license. As soon as a contributor arrives, their contributions are under GPL-3.0 and their consent would be needed: a CLA (Contributor License Agreement) before the first outside contribution keeps the option to relicense, offer a commercial edition or accept an acquisition. What has been published stays open forever; only future versions can change.

**Business model:** free, funded by donations (GitHub Sponsors, Open Collective). If the project grows, the classic model for an open browser is to sell services, never the code: sync between devices, hosted Pro features, support for teams. No monetization of users or their data.

- [x] Choose the license: GPL-3.0
- [ ] Write the CLA, before the first outside contribution
- [ ] Check the name "Chord": domain, GitHub organization, trademarks (INPI, EUIPO)

## What we don't do, for now

- No intrusive Dia-style AI
- No required account
- No Windows or Linux
- No multiple engines in v1
- No Boosts in v1
- No big feature until the core experience is flawless

**Horizon, once the foundation is solid:** the developer tools that justify the positioning. Ideas already noted: a Space linked to a repo that detects dev servers and PR status; switching between local / staging / prod environments with one shortcut; sessions isolated per tab; a responsive split view with synchronized scrolling; a developer-oriented command bar (clear storage, copy as cURL, open the component in the editor); and a built-in MCP server so coding agents can drive the browser.

## Roadmap

Phases without dates: the order and the gates matter, not the calendar.

| Phase | Content |
| --- | --- |
| 0 · Foundations | Chromium build, Swift shell and window, engine and tabs, latency measured in CI |
| 1 · Arc parity | Sidebar and Spaces, command bar, Peek and split view, little window, dark mode and edgeless |
| *Gate* | *Latency budgets met* |
| 2 · Public beta | Public repository, license and CLA, donations enabled, import from Arc, Chrome extensions |
| *Gate* | *Community and donations in place* |
| 3 · Developer tools | Space linked to a repo, local / staging / prod, dev commands, MCP server |
| 4 · Horizon | WebKit engine, Boosts, Windows and Linux, sync |

Phase 1 is the only one that matters at first: nothing passes the first gate until the latency budgets are met. Developer tools only arrive in phase 3, once the community is in place.

## Identity

**Name: Chord.** In geometry, the chord is the segment that joins the two ends of an arc. The name states the lineage with Arc without copying it, it is short, pronounceable in every language, and no browser uses it. To check before any announcement: the domain, the GitHub organization and registered trademarks (INPI, EUIPO).

**Mark: the arc and its chord.** An open circular arc, closed by the chord that joins its two ends. It is literally the definition of the word, and the project's story in one shape: Chord is what comes to close the arc. The arc takes the text color (black on light, white on dark), the chord takes the accent, indigo by default or the active Space's color in the app. In monochrome, both share the same stroke.

**App icon:** a plain deep indigo background, no gradient, the arc in white and the chord in light indigo. The stroke gets thicker at small sizes to stay legible at 16 px; the menu bar uses the monochrome glyph.

**Logo:** the symbol followed by the word "Chord" in SF Pro Display Semibold, tight letter spacing, never in capitals. Tagline: "The browser that closes the arc."

The three directions explored, the icon at every size and the light, dark and monochrome versions of the logo are on the "Chord — Main window" canvas, "Identity" row.

## Sources

- [Is Arc Browser Dead? (SupaSidebar)](https://supasidebar.com/blog/is-arc-browser-dead)
- [Arc Browser Status 2026 (SuperchargeBrowser)](https://www.superchargebrowser.com/library/arc-browser-status-2026/)
- [Is There an Open-Source Arc Browser? (SupaSidebar)](https://supasidebar.com/blog/open-source-arc-browser)
- [Arc-Like Chromium Browsers Ranked (SuperchargeBrowser)](https://www.superchargebrowser.com/library/open-source-chromium-arc-like-browsers-2026/)
- [ungoogled-chromium (Wikipedia)](https://en.wikipedia.org/wiki/Ungoogled_Chromium)
- [ungoogled-chromium-macos (GitHub)](https://github.com/ungoogled-software/ungoogled-chromium-macos)
- [Helium (GitHub)](https://github.com/imputnet/helium)
