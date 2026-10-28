# Chord's Chromium patches

Rules, so that the update every four weeks stays a simple rebase:

- Chord's code lives in `//chord` (`engine/chord`), not in Google's files.
- A patch only plugs `//chord` in: redirect a factory, add a GN dependency, expose an
  entry point. A few lines each.
- One patch per intent, named after what it does.
- Applied on top of ungoogled-chromium's patches, in `series` order, by
  `engine/scripts/build.sh` (once each: a `.chord-patch-<name>` marker stays in the
  source tree).

| Patch | What it plugs in |
| --- | --- |
| `chord-link-build.patch` | `//chord:browser` is linked into the browser (`chrome/BUILD.gn`, `dependencies` group, macOS only) |
| `chord-start-ui.patch` | Chord's "extra parts": no Chromium window at startup, then ChordUI starts (`chrome_browser_main.cc`) |
| `chord-browser-window-factory.patch` | A normal browser gets Chord's window, `ChordBrowserWindow` (`browser_window_factory.cc`) |
| `chord-devtools-dock.patch` | DevTools can dock into Chord's windows (right, left, bottom), which lay them out themselves; Chord is told when they open, close, change side or size (`devtools_window.cc`, `devtools_window_views.cc`) |
| `chord-windows-without-views.patch` | Chord's windows have no side panel, no toast anchor and no Views "crashed tab" view: Chromium treats them like `WebUIBrowserWindow` instead of stopping on a test check (closing the active tab, toasts) (`read_anything_side_panel_controller.cc`, `toast_controller.cc`, `tab_features.cc`) |
| `chord-second-launch.patch` | Launching Chord again while it runs brings its window back (and opens the links passed as arguments) instead of opening an empty tab (`startup_browser_creator.cc`) |
| `chord-permission-prompts.patch` | Permission requests (camera, microphone, location, notifications…) from Chord's pages go through Chord's prompt, a small bubble at the top of the page; Chromium's bubble, which looks for its Views window, crashed Chord (YouTube) (`permission_prompt_factory.cc`) |
| `chord-branding.patch` | The app is called Chord (`app.chord.Chord`); the data folder stays `~/Library/Application Support/Chromium` (`chrome/app/theme/chromium/BRANDING`) |
| `chord-fix-development-link.patch` | Build fix: in a development build, a call to a test helper that ungoogled-chromium removes broke linking (`profile_management_disclaimer_service.cc`) |
| `chord-app-controller.patch` | The Dock icon reopens Chord's window; links from other apps go to a little window; Chromium's Bookmarks and History menus are no longer kept up to date, since the menu is ChordUI's (`app_controller_mac.mm`) |
| `chord-context-menus.patch` | Right-clicking a page shows its menu in Chord's windows, which have no Views widget; Chord removes the entries whose interface needs one (Cast, translate, QR code, Lens…) (`render_view_context_menu_mac_cocoa.mm`) |
| `chord-product-icon.patch` | The product icon in internal pages ("About" in the settings menu, help pages) is Chord's symbol; the header logo comes from `engine/branding` (`settings/icons.html.ts`, `cr_elements/icons.html.ts`) |
| `chord-own-data.patch` | Chord has its own data folder (`~/Library/Application Support/Chord`) and its own keychain key ("Chord Safe Storage"), apart from a Chromium installed on the same Mac (`app-Info.plist`, `keychain_password_mac.mm`) |
| `chord-web-store.patch` | The real Chrome Web Store: its pages can install extensions, which update from it; ungoogled-chromium's domain substitution had cut it off (`extension_urls.cc`, `_api_features.json`), and its patches had emptied the download and install (`webstore_installer.cc`) |
| `chord-components.patch` | Chromium's update client checks again and reaches Google, for the Widevine module (protected videos), Chromium's lists and Web Store extension updates (`component_updater_url_constants.cc`, `update_checker.cc`) |
| `chord-password-prompt.patch` | The password manager's "Save password?" and "Update password?" go through Chord's prompt, like a site's permission; Chromium's bubble hangs from Chrome's toolbar, which Chord's windows do not have, and never showed (`manage_passwords_ui_controller.cc`) |
| `chord-links.patch` | A ⇧-clicked link opens in a Peek instead of a new window, and a link leaving the site of a pinned tab or a favorite goes to a Peek too: ChordUI decides, through a navigation throttle and `OpenURLFromTab` (`chrome_content_browser_client.cc`, `browser_web_contents_delegate.cc`) |
| `chord-autofill-bubbles.patch` | Autofill's "Save address?" and "Update address?" find Chord's bubble handler (`chord_autofill_bubbles.mm`) through the page's browser: Chromium looked for a Views `BrowserView` and crashed in Chord's windows when an address form was submitted (`address_bubbles_controller.cc`) |
| `chord-username-first.patch` | A sign-in whose first page only asks for an email (`autocomplete="email"`, the password on the next page) offers the saved usernames and remembers the one typed: Chrome learns such forms from its crowdsourcing server, which ungoogled-chromium leaves out (`password_manager_util.cc`, `form_data_parser.cc`) |

The call sites are declared in `engine/chord/browser/chord_hooks.h`.
`--disable-chord-ui` at launch gives Chromium its interface back, for debugging.
