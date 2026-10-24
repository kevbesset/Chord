// Copyright 2026 The Chord Authors
// The few places where Chromium hands over to Chord. Each is called from a small,
// isolated patch (engine/patches/), so that a new Chromium version only has to keep
// these call sites.

#ifndef CHORD_BROWSER_CHORD_HOOKS_H_
#define CHORD_BROWSER_CHORD_HOOKS_H_

#include <memory>

#include "chrome/browser/ui/browser_window_deleter.h"

class BrowserWindow;
class BrowserWindowInterface;
class ChromeBrowserMainExtraParts;

#if defined(__OBJC__)
#import <Foundation/Foundation.h>
#endif

namespace chord {

// chrome/browser/chrome_browser_main.cc: starts ChordUI once the browser has started.
std::unique_ptr<ChromeBrowserMainExtraParts> CreateBrowserMainExtraParts();

// chrome/browser/ui/views/frame/browser_window_factory.cc: the window of a normal
// browser is Chord's, whose tabs ChordUI shows. Returns nullptr for the other types
// (DevTools, popups, apps), which keep Chromium's windows.
std::unique_ptr<BrowserWindow, BrowserWindowDeleter> MaybeCreateBrowserWindow(
    BrowserWindowInterface* browser);

// Whether Chord's interface replaces Chromium's for this process.
bool IsEnabled();

#if defined(__OBJC__)
// chrome/browser/app_controller_mac.mm: the Dock icon was clicked. Returns true when
// Chord brought its window back.
bool HandleReopen();

// chrome/browser/app_controller_mac.mm: links opened from other apps. Returns true
// when Chord took them (into a little window, like Little Arc).
bool OpenURLs(NSArray<NSURL*>* urls);
#endif

}  // namespace chord

#endif  // CHORD_BROWSER_CHORD_HOOKS_H_
