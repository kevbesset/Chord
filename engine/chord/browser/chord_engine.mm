// Copyright 2026 The Chord Authors

#import "chord/browser/chord_engine.h"

#include <map>
#include <memory>
#include <set>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/devtools/devtools_toggle_action.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/lifetime/browser_shutdown.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_active_state_manager/browser_active_state_manager.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/reload_type.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "net/base/apple/url_conversions.h"
#include "third_party/blink/public/mojom/favicon/favicon_url.mojom.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"

@class ChordPage;

namespace {

ChordEngine* __weak g_engine = nil;

// The page wrapping each WebContents, so that a tab Chromium opens or closes is
// matched with what ChordUI knows. Weak: ChordUI owns the pages.
std::map<content::WebContents*, ChordPage* __weak>& Pages() {
  static base::NoDestructor<std::map<content::WebContents*, ChordPage* __weak>>
      pages;
  return *pages;
}

ChordPage* PageFor(content::WebContents* contents) {
  auto it = Pages().find(contents);
  return it == Pages().end() ? nil : it->second;
}

// Quitting closes every tab: ChordUI must not see that as the user closing them.
bool IsQuitting() {
  return browser_shutdown::IsTryingToQuit() ||
         browser_shutdown::HasShutdownStarted();
}

}  // namespace

// MARK: - ChordPage

@interface ChordPage : NSObject <ChordWebPage>
- (instancetype)initWithWebContents:(content::WebContents*)contents;
@property(nonatomic, readonly) content::WebContents* webContents;
- (void)notifyUpdate;
- (void)updateFavicon:(const std::vector<blink::mojom::FaviconURLPtr>&)candidates;
// The tab is gone (closed by Chromium, or replaced): forget its WebContents.
- (void)detach;
- (void)replaceWebContents:(content::WebContents*)contents;
@end

namespace {

// Forwards what changes on a page to ChordUI.
class PageObserver : public content::WebContentsObserver {
 public:
  PageObserver(content::WebContents* contents, ChordPage* page)
      : content::WebContentsObserver(contents), page_(page) {}

  // content::WebContentsObserver:
  void DidStartLoading() override { [page_ notifyUpdate]; }
  void DidStopLoading() override { [page_ notifyUpdate]; }
  void DidFinishNavigation(content::NavigationHandle* handle) override {
    [page_ notifyUpdate];
  }
  void NavigationEntryCommitted(
      const content::LoadCommittedDetails& details) override {
    [page_ notifyUpdate];
  }
  void TitleWasSet(content::NavigationEntry* entry) override {
    [page_ notifyUpdate];
  }
  void DidUpdateFaviconURL(
      content::RenderFrameHost* frame,
      const std::vector<blink::mojom::FaviconURLPtr>& candidates,
      blink::mojom::FaviconUpdateReason reason) override {
    [page_ updateFavicon:candidates];
  }
  void WebContentsDestroyed() override { [page_ detach]; }

 private:
  ChordPage* __weak page_;
};

}  // namespace

@implementation ChordPage {
  raw_ptr<content::WebContents> _webContents;
  std::unique_ptr<PageObserver> _observer;
  NSURL* _faviconURL;
  id<ChordWebPageDelegate> __weak _delegate;
}

- (instancetype)initWithWebContents:(content::WebContents*)contents {
  if ((self = [super init])) {
    _webContents = contents;
    _observer = std::make_unique<PageObserver>(contents, self);
    Pages()[contents] = self;
  }
  return self;
}

- (void)dealloc {
  // ChordUI let go of the page (a closed tab, or one put to sleep): close the tab.
  content::WebContents* contents = _webContents;
  [self detach];
  if (!contents || IsQuitting()) {
    return;
  }
  tabs::TabInterface* tab = tabs::TabInterface::MaybeGetFromContents(contents);
  BrowserWindowInterface* browser =
      tab ? tab->GetBrowserWindowInterface() : nullptr;
  if (!browser) {
    return;
  }
  TabStripModel* strip = browser->GetTabStripModel();
  int index = strip->GetIndexOfWebContents(contents);
  if (index != TabStripModel::kNoTab) {
    strip->CloseWebContentsAt(index, TabCloseTypes::CLOSE_NONE);
  }
}

- (content::WebContents*)webContents {
  return _webContents;
}

- (void)detach {
  if (!_webContents) {
    return;
  }
  auto it = Pages().find(_webContents);
  if (it != Pages().end() && (it->second == self || !it->second)) {
    Pages().erase(it);
  }
  _observer.reset();
  _webContents = nullptr;
}

- (void)replaceWebContents:(content::WebContents*)contents {
  [self detach];
  _webContents = contents;
  _observer = std::make_unique<PageObserver>(contents, self);
  Pages()[contents] = self;
  [self notifyUpdate];
}

- (void)notifyUpdate {
  [_delegate pageDidUpdate:self];
}

// Keeps the largest icon the page declares: the sidebar shows them at 16 pt, at 2x.
- (void)updateFavicon:(const std::vector<blink::mojom::FaviconURLPtr>&)candidates {
  const blink::mojom::FaviconURL* best = nullptr;
  int bestSize = -1;
  for (const auto& candidate : candidates) {
    if (candidate->icon_type != blink::mojom::FaviconIconType::kFavicon ||
        !candidate->icon_url.is_valid()) {
      continue;
    }
    int size = 0;
    for (const auto& icon_size : candidate->icon_sizes) {
      size = std::max(size, icon_size.width());
    }
    if (size > bestSize) {
      best = candidate.get();
      bestSize = size;
    }
  }
  if (!best) {
    return;
  }
  _faviconURL = net::NSURLWithGURL(best->icon_url);
  [self notifyUpdate];
}

// MARK: ChordWebPage

- (NSView*)view {
  if (!_webContents) {
    return [[NSView alloc] init];
  }
  return _webContents->GetNativeView().GetNativeNSView();
}

- (NSURL*)url {
  if (!_webContents) {
    return nil;
  }
  const GURL& url = _webContents->GetVisibleURL();
  return url.is_empty() ? nil : net::NSURLWithGURL(url);
}

- (NSString*)title {
  return _webContents ? base::SysUTF16ToNSString(_webContents->GetTitle())
                      : nil;
}

- (BOOL)isLoading {
  return _webContents && _webContents->IsLoading();
}

- (BOOL)canGoBack {
  return _webContents && _webContents->GetController().CanGoBack();
}

- (BOOL)canGoForward {
  return _webContents && _webContents->GetController().CanGoForward();
}

- (NSURL*)faviconURL {
  return _faviconURL;
}

- (id<ChordWebPageDelegate>)delegate {
  return _delegate;
}

- (void)setDelegate:(id<ChordWebPageDelegate>)delegate {
  _delegate = delegate;
}

- (void)load:(NSURL*)url {
  if (!_webContents) {
    return;
  }
  content::NavigationController::LoadURLParams params(net::GURLWithNSURL(url));
  params.transition_type = ui::PageTransitionFromInt(
      ui::PAGE_TRANSITION_TYPED | ui::PAGE_TRANSITION_FROM_ADDRESS_BAR);
  _webContents->GetController().LoadURLWithParams(params);
}

- (void)goBack {
  if (_webContents && _webContents->GetController().CanGoBack()) {
    _webContents->GetController().GoBack();
  }
}

- (void)goForward {
  if (_webContents && _webContents->GetController().CanGoForward()) {
    _webContents->GetController().GoForward();
  }
}

- (void)reload {
  if (_webContents) {
    _webContents->GetController().Reload(content::ReloadType::NORMAL, true);
  }
}

- (void)reloadIgnoringCache {
  if (_webContents) {
    _webContents->GetController().Reload(content::ReloadType::BYPASSING_CACHE,
                                         true);
  }
}

- (void)stopLoading {
  if (_webContents) {
    _webContents->Stop();
  }
}

// The selected tab is Chromium's active one: extensions, DevTools and the browser
// commands act on it.
- (void)didBecomeActive {
  tabs::TabInterface* tab =
      _webContents ? tabs::TabInterface::MaybeGetFromContents(_webContents)
                   : nullptr;
  BrowserWindowInterface* browser =
      tab ? tab->GetBrowserWindowInterface() : nullptr;
  if (!browser) {
    return;
  }
  TabStripModel* strip = browser->GetTabStripModel();
  int index = strip->GetIndexOfWebContents(_webContents);
  if (index != TabStripModel::kNoTab && index != strip->active_index()) {
    strip->ActivateTabAt(index);
  }
  BrowserActiveStateManager::From(browser)->DidBecomeActive();
}

- (void)toggleDevTools {
  if (_webContents) {
    DevToolsWindow::OpenDevToolsWindow(
        _webContents, DevToolsToggleAction::Toggle(),
        DevToolsOpenedByAction::kMainMenuOrMainShortcut);
  }
}

@end

// MARK: - Tabs Chromium opens or closes by itself

@interface ChordEngine ()
- (void)announcePage:(ChordPage*)page
              opener:(ChordPage*)opener
        inBackground:(BOOL)inBackground;
- (void)announceClosedPage:(ChordPage*)page;
@end

namespace {

class TabWatcher : public TabStripModelObserver {
 public:
  static TabWatcher& Get() {
    static base::NoDestructor<TabWatcher> watcher;
    return *watcher;
  }

  void Watch(TabStripModel* strip) { strip->AddObserver(this); }
  void Unwatch(TabStripModel* strip) { strip->RemoveObserver(this); }

  // TabStripModelObserver:
  void OnTabStripModelChanged(TabStripModel* strip,
                              const TabStripModelChange& change,
                              const TabStripSelectionChange& selection) override {
    switch (change.type()) {
      case TabStripModelChange::kInserted:
        for (const auto& inserted : change.GetInsert()->contents) {
          TabOpened(strip, inserted.contents, inserted.index,
                    selection.new_contents == inserted.contents);
        }
        break;
      case TabStripModelChange::kRemoved:
        for (const auto& removed : change.GetRemove()->contents) {
          if (removed.remove_reason !=
              TabRemovedReason::kInsertedIntoOtherTabStrip) {
            TabClosed(removed.contents);
          }
        }
        break;
      case TabStripModelChange::kReplaced: {
        const auto* replace = change.GetReplace();
        if (ChordPage* page = PageFor(replace->old_contents)) {
          [page replaceWebContents:replace->new_contents];
        }
        break;
      }
      default:
        break;
    }
  }

 private:
  // A tab ChordUI did not ask for: a link opened in a new tab, `window.open`, an
  // extension's tab. ChordUI adopts it.
  void TabOpened(TabStripModel* strip,
                 content::WebContents* contents,
                 int index,
                 bool foreground) {
    ChordEngine* engine = g_engine;
    if (!engine || PageFor(contents)) {
      return;
    }
    ChordPage* page = [[ChordPage alloc] initWithWebContents:contents];
    tabs::TabInterface* opener_tab = strip->GetOpenerOfTabAt(index);
    ChordPage* opener =
        opener_tab ? PageFor(opener_tab->GetContents()) : nil;
    // After the tab strip finishes its own work.
    dispatch_async(dispatch_get_main_queue(), ^{
      [engine announcePage:page opener:opener inBackground:!foreground];
    });
  }

  // A tab closed by Chromium (`window.close()`, an extension). A tab ChordUI closed
  // has already let go of its page, which is then gone from Pages().
  void TabClosed(content::WebContents* contents) {
    ChordPage* page = PageFor(contents);
    if (!page) {
      return;
    }
    [page detach];
    ChordEngine* engine = g_engine;
    if (!engine || IsQuitting()) {
      return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      [engine announceClosedPage:page];
    });
  }
};

}  // namespace

// MARK: - ChordEngine

@implementation ChordEngine {
  raw_ptr<Profile> _profile;
  raw_ptr<BrowserWindowInterface> _browser;
  base::CallbackListSubscription _browserDidClose;
  id<ChordWebEngineDelegate> __weak _delegate;
}

- (instancetype)initWithProfile:(Profile*)profile {
  if ((self = [super init])) {
    _profile = profile;
  }
  return self;
}

// The browser that holds ChordUI's pages. Created on first use, and again if
// Chromium closed it (its last tab closed).
- (BrowserWindowInterface*)browser {
  if (_browser && !_browser->IsDeleteScheduled()) {
    return _browser;
  }
  BrowserWindowCreateParams params(BrowserWindowInterface::TYPE_NORMAL,
                                   _profile.get(),
                                   /*from_user_gesture=*/true);
  params.omit_from_session_restore = true;
  params.should_trigger_session_restore = false;
  _browser = CreateBrowserWindow(std::move(params));
  ChordEngine* __weak weakSelf = self;
  _browserDidClose = _browser->RegisterBrowserDidClose(
      base::BindRepeating(^(BrowserWindowInterface* closed) {
        ChordEngine* engine = weakSelf;
        if (engine && engine->_browser == closed) {
          engine->_browser = nullptr;
        }
      }));
  return _browser;
}

- (id<ChordWebPage>)makePage {
  content::WebContents::CreateParams params(_profile.get());
  std::unique_ptr<content::WebContents> contents =
      content::WebContents::Create(params);
  // Known before the tab strip announces it, so it is not taken for a new tab.
  ChordPage* page = [[ChordPage alloc] initWithWebContents:contents.get()];
  [self browser]->GetTabStripModel()->AppendWebContents(std::move(contents),
                                                        /*foreground=*/false);
  return page;
}

- (void)setDelegate:(id<ChordWebEngineDelegate>)delegate {
  _delegate = delegate;
}

- (void)announcePage:(ChordPage*)page
              opener:(ChordPage*)opener
        inBackground:(BOOL)inBackground {
  if (!page.webContents) {
    return;
  }
  [_delegate engine:self didOpen:page opener:opener inBackground:inBackground];
}

- (void)announceClosedPage:(ChordPage*)page {
  [_delegate engine:self didClose:page];
}

@end

namespace chord {

ChordEngine* SharedEngine() {
  return g_engine;
}

void SetSharedEngine(ChordEngine* engine) {
  g_engine = engine;
}

void WatchBrowser(BrowserWindowInterface* browser) {
  TabWatcher::Get().Watch(browser->GetTabStripModel());
}

void UnwatchBrowser(BrowserWindowInterface* browser) {
  TabWatcher::Get().Unwatch(browser->GetTabStripModel());
}

}  // namespace chord
