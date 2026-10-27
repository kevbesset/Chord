// Copyright 2026 The Chord Authors
// ChordUI's engine on Chromium.
//
// Every page ChordUI shows is a tab of a Chromium browser whose window is Chord's
// (ChordBrowserWindow): Chromium keeps its tab model, which extensions, DevTools and
// the tab features rely on, while ChordUI decides where each page's view goes.

#ifndef CHORD_BROWSER_CHORD_ENGINE_H_
#define CHORD_BROWSER_CHORD_ENGINE_H_

#import "chord/browser/chord_ui.h"

class BrowserWindowInterface;
class Profile;

namespace content {
class BrowserContext;
class WebContents;
}

@interface ChordEngine : NSObject <ChordWebEngine>

- (instancetype)initWithProfile:(Profile*)profile;
- (instancetype)init NS_UNAVAILABLE;

@end

namespace chord {

// The engine ChordUI runs on, once started.
ChordEngine* SharedEngine();
void SetSharedEngine(ChordEngine* engine);

// Follows the tabs of a browser with Chord's window, so that the pages Chromium opens
// by itself (a link to a new tab, an extension's tab) reach ChordUI.
void WatchBrowser(BrowserWindowInterface* browser);

// ChordUI shows the page: Chromium wants it on screen (the picture-in-picture "back
// to tab", a window brought forward), whatever Space it is in.
void ShowPage(content::WebContents* contents);
void UnwatchBrowser(BrowserWindowInterface* browser);

// The page ChordUI knows for `contents`, nil for one it does not show.
id<ChordWebPage> PageForContents(content::WebContents* contents);

// The active page of the profile's browser (the tab ChordUI selected last), nil when
// it has none.
id<ChordWebPage> ActivePageForProfile(content::BrowserContext* context);

// Hands a permission request of `contents` to ChordUI, through the engine of its
// profile. Returns false when ChordUI does not know the page.
bool RequestPermission(content::WebContents* contents,
                       id<ChordPermissionRequest> request);

}  // namespace chord

#endif  // CHORD_BROWSER_CHORD_ENGINE_H_
