// Copyright 2026 The Chord Authors
// Starts ChordUI in Chromium's browser process, and the hooks of chord_hooks.h.

#include "chord/browser/chord_hooks.h"

#import <AppKit/AppKit.h>

#include <fcntl.h>
#include <unistd.h>

#include <string>

#include "base/apple/bundle_locations.h"
#include "base/command_line.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/strings/stringprintf.h"
#include "base/strings/sys_string_conversions.h"
#include "net/base/apple/url_conversions.h"
#include "url/gurl.h"
#import "chord/browser/chord_browser_window.h"
#import "chord/browser/chord_engine.h"
#import "chord/browser/chord_ui.h"
#include "base/values.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/chrome_browser_main_extra_parts.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/common/chrome_switches.h"
#include "chrome/common/pref_names.h"
#include "components/prefs/pref_service.h"
#include "components/os_crypt/common/os_crypt_switches.h"

namespace chord {
namespace {

// For debugging Chromium itself: `--disable-chord-ui` brings back its interface.
constexpr char kDisableChordUI[] = "disable-chord-ui";

bool g_started = false;

// A fatal error (a failed CHECK) stops the browser with a message that the macOS crash
// report lacks: it goes to ~/Library/Logs/Chord/last-fatal.txt, which ChordUI's crash
// report picks up on the next launch.
std::string& FatalLogPath() {
  static base::NoDestructor<std::string> path;
  return *path;
}

logging::LogMessageHandlerFunction g_previous_log_handler = nullptr;

bool HandleLogMessage(int severity,
                      const char* file,
                      int line,
                      size_t message_start,
                      const std::string& message) {
  if (severity == logging::LOGGING_FATAL && !FatalLogPath().empty()) {
    int fd = open(FatalLogPath().c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
      std::string text = base::StringPrintf("%.0f\n%s:%d\n%s",
          [NSDate date].timeIntervalSince1970, file, line, message.c_str());
      ssize_t written = write(fd, text.data(), text.size());
      (void)written;
      close(fd);
    }
  }
  return g_previous_log_handler &&
         g_previous_log_handler(severity, file, line, message_start, message);
}

void RecordFatalErrors() {
  NSString* directory = [NSHomeDirectory()
      stringByAppendingPathComponent:@"Library/Logs/Chord"];
  [NSFileManager.defaultManager createDirectoryAtPath:directory
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:nil];
  FatalLogPath() = base::SysNSStringToUTF8(
      [directory stringByAppendingPathComponent:@"last-fatal.txt"]);
  g_previous_log_handler = logging::GetLogMessageHandler();
  logging::SetLogMessageHandler(&HandleLogMessage);
}

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
    // ⌘Q quits at once, like Arc: no "hold ⌘Q to quit" panel, whose own event loop
    // held up the whole interface.
    g_browser_process->local_state()->SetDefaultPrefValue(
        prefs::kConfirmToQuitEnabled, base::Value(false));
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
  RecordFatalErrors();
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
