// Copyright 2026 The Chord Authors
// Starts ChordUI in Chromium's browser process, and the hooks of chord_hooks.h.

#include "chord/browser/chord_hooks.h"

#import <AppKit/AppKit.h>

#include "base/apple/bundle_locations.h"
#include "base/command_line.h"
#include "base/logging.h"
#include "base/strings/sys_string_conversions.h"
#include "net/base/apple/url_conversions.h"
#include "url/gurl.h"
#import "chord/browser/chord_browser_window.h"
#import "chord/browser/chord_engine.h"
#import "chord/browser/chord_ui.h"
#include "chrome/browser/chrome_browser_main_extra_parts.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/common/chrome_switches.h"
#include "components/os_crypt/common/os_crypt_switches.h"

namespace chord {
namespace {

// For debugging Chromium itself: `--disable-chord-ui` brings back its interface.
constexpr char kDisableChordUI[] = "disable-chord-ui";

bool g_started = false;

Class<ChordUIHostInterface> Host() {
  return (Class<ChordUIHostInterface>)NSClassFromString(@"ChordUIHost");
}

// ChordUI.framework sits in the app's Frameworks folder (engine/scripts/build.sh puts
// it there). Only the browser process loads it: helpers never see Swift.
bool LoadChordUI() {
  if (Host()) {
    return true;
  }
  NSString* path = [base::apple::OuterBundle().privateFrameworksPath
      stringByAppendingPathComponent:@"ChordUI.framework"];
  NSBundle* bundle = [NSBundle bundleWithPath:path];
  NSError* error = nil;
  if (!bundle || ![bundle loadAndReturnError:&error]) {
    LOG(ERROR) << "Chord: cannot load " << base::SysNSStringToUTF8(path) << ": "
               << base::SysNSStringToUTF8(error.localizedDescription ?: @"");
    return false;
  }
  return Host() != nil;
}

void StartChordUI() {
  if (g_started || !LoadChordUI()) {
    return;
  }
  Profile* profile = ProfileManager::GetLastUsedProfileAllowedByPolicy();
  if (!profile) {
    LOG(ERROR) << "Chord: no profile to start with";
    return;
  }
  g_started = true;
  ChordEngine* engine = [[ChordEngine alloc] initWithProfile:profile];
  SetSharedEngine(engine);
  // ChordUI's session (Spaces, tabs, folders). A separate `--user-data-dir`
  // (tests, a second profile folder) gets its own, inside it.
  NSURL* support = [[NSFileManager.defaultManager
      URLsForDirectory:NSApplicationSupportDirectory
             inDomains:NSUserDomainMask].firstObject
      URLByAppendingPathComponent:@"Chord"
                      isDirectory:YES];
  const base::CommandLine& command_line = *base::CommandLine::ForCurrentProcess();
  if (command_line.HasSwitch(switches::kUserDataDir)) {
    support = [NSURL
        fileURLWithPath:base::SysUTF8ToNSString(
                            command_line.GetSwitchValuePath(switches::kUserDataDir)
                                .Append("ChordUI")
                                .value())
            isDirectory:YES];
  }
  [Host() startWithEngine:engine appName:@"Chord" supportDirectory:support];
}

class ChordBrowserMainExtraParts : public ChromeBrowserMainExtraParts {
 public:
  // ChordUI opens the window: Chromium must not open its own at startup.
  void PostEarlyInitialization() override {
    base::CommandLine::ForCurrentProcess()->AppendSwitch(
        switches::kNoStartupWindow);
  }

  // On the next turn of the run loop, once AppKit has finished launching and
  // Chromium has built its menu, which ChordUI's replaces.
  void PostBrowserStart() override {
    dispatch_async(dispatch_get_main_queue(), ^{
      StartChordUI();
    });
  }
};

}  // namespace

bool IsEnabled() {
  return !base::CommandLine::ForCurrentProcess()->HasSwitch(kDisableChordUI);
}

std::unique_ptr<ChromeBrowserMainExtraParts> CreateBrowserMainExtraParts() {
#if !defined(OFFICIAL_BUILD)
  // A development build is signed anew at each build, so macOS would ask for the
  // keychain item that encrypts cookies every time, and every page load waits for
  // that answer. Development builds keep that key in a mock keychain instead.
  base::CommandLine::ForCurrentProcess()->AppendSwitch(
      os_crypt::switches::kUseMockKeychain);
#endif
  if (!IsEnabled()) {
    return nullptr;
  }
  return std::make_unique<ChordBrowserMainExtraParts>();
}

std::unique_ptr<BrowserWindow, BrowserWindowDeleter> MaybeCreateBrowserWindow(
    BrowserWindowInterface* browser) {
  if (!IsEnabled() ||
      browser->GetType() != BrowserWindowInterface::Type::TYPE_NORMAL) {
    return nullptr;
  }
  return std::unique_ptr<BrowserWindow, BrowserWindowDeleter>(
      new ChordBrowserWindow(browser));
}

bool HandleSecondLaunch(const base::CommandLine& command_line) {
  if (!g_started) {
    return false;
  }
  NSMutableArray<NSURL*>* urls = [NSMutableArray array];
  for (const auto& arg : command_line.GetArgs()) {
    GURL url(arg);
    if (url.is_valid() && (url.SchemeIsHTTPOrHTTPS() || url.SchemeIsFile())) {
      [urls addObject:net::NSURLWithGURL(url)];
    }
  }
  if (urls.count) {
    [Host() openURLs:urls];
  } else {
    [Host() reopen];
  }
  return true;
}

bool HandleReopen() {
  if (!g_started) {
    return false;
  }
  [Host() reopen];
  return true;
}

bool OpenURLs(NSArray<NSURL*>* urls) {
  if (!IsEnabled() || !LoadChordUI()) {
    return false;
  }
  // Before ChordUI starts, it keeps them for when its window opens.
  [Host() openURLs:urls];
  return true;
}

}  // namespace chord
