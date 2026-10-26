// Copyright 2026 The Chord Authors

#import "chord/browser/chord_engine.h"

#include "chord/browser/chord_hooks.h"

#include <map>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/content_settings/core/common/content_settings.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "chrome/browser/devtools/devtools_contents_resizing_strategy.h"
#include "chrome/browser/devtools/devtools_toggle_action.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/lifetime/browser_shutdown.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_window_manager.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_active_state_manager/browser_active_state_manager.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/media_session.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/render_frame_host.h"
#include "chrome/common/chrome_isolated_world_ids.h"
#include "third_party/blink/public/mojom/frame/media_player_action.mojom.h"
#include "ui/gfx/geometry/point.h"
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

// Every engine: the normal one, and those of private browsing windows.
NSHashTable<ChordEngine*>* Engines() {
  static NSHashTable<ChordEngine*>* engines = [NSHashTable weakObjectsHashTable];
  return engines;
}

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

// The tab ChordUI is making active, so that the tab watcher tells it apart from a
// tab Chromium activates by itself (the picture-in-picture "back to tab" button).
content::WebContents* g_activating = nullptr;

bool IsInPictureInPicture(content::WebContents* contents) {
  return contents &&
         PictureInPictureWindowManager::GetInstance()->GetWebContents() ==
             contents;
}

// Finds the largest playing video of the page, in the page's own world (the page's
// scripts cannot see it run), and returns its centre in CSS pixels with the
// viewport's width, or null.
constexpr char16_t kFindPlayingVideo[] = uR"((() => {
  let best = null, area = 0;
  for (const video of document.querySelectorAll('video')) {
    if (video.paused || video.ended || video.readyState < 2 || video.disablePictureInPicture) continue;
    const r = video.getBoundingClientRect();
    if (r.width * r.height > area) { area = r.width * r.height; best = r; }
  }
  return best ? [best.left + best.width / 2, best.top + best.height / 2, window.innerWidth] : null;
})())";

// Puts the page's playing video in picture-in-picture, the way the context menu's
// "Picture in picture" item does: an action on the video under a point. It works for
// any video, muted ones included. A video the script cannot reach (inside another
// site's frame) goes through the media session instead, for the ones it knows.
void EnterPictureInPicture(content::WebContents* contents) {
  base::WeakPtr<content::WebContents> weak = contents->GetWeakPtr();
  contents->GetPrimaryMainFrame()->ExecuteJavaScriptInIsolatedWorld(
      kFindPlayingVideo,
      base::BindOnce(
          [](base::WeakPtr<content::WebContents> weak, base::Value result) {
            content::WebContents* contents = weak.get();
            if (!contents || IsInPictureInPicture(contents)) {
              return;
            }
            const base::ListValue* list = result.GetIfList();
            if (!list || list->size() != 3) {
              content::MediaSession::Get(contents)->EnterPictureInPicture();
              return;
            }
            // CSS pixels to the view's DIPs: the page zoom, read from the viewport.
            double viewport = (*list)[2].GetIfDouble().value_or(
                (*list)[2].GetIfInt().value_or(0));
            int width = contents->GetContainerBounds().width();
            double scale = viewport > 0 && width > 0 ? width / viewport : 1;
            auto coordinate = [&](const base::Value& value) {
              return static_cast<int>(
                  value.GetIfDouble().value_or(value.GetIfInt().value_or(0)) *
                  scale);
            };
            contents->GetPrimaryMainFrame()->ExecuteMediaPlayerActionAtLocation(
                gfx::Point(coordinate((*list)[0]), coordinate((*list)[1])),
                blink::mojom::MediaPlayerAction(
                    blink::mojom::MediaPlayerActionType::kPictureInPicture,
                    /*enable=*/true));
          },
          weak),
      ISOLATED_WORLD_ID_CHROME_INTERNAL);
}

// Quitting closes every tab: ChordUI must not see that as the user closing them.
bool IsQuitting() {
  return browser_shutdown::IsTryingToQuit() ||
         browser_shutdown::HasShutdownStarted();
}

}  // namespace

// MARK: - ChordPage

namespace {

// The permissions ChordUI's site controls show, by the names it gives them.
std::optional<ContentSettingsType> PermissionType(NSString* permission) {
  static const auto* types = new std::map<std::string, ContentSettingsType>{
      {"notifications", ContentSettingsType::NOTIFICATIONS},
      {"geolocation", ContentSettingsType::GEOLOCATION},
      {"camera", ContentSettingsType::MEDIASTREAM_CAMERA},
      {"microphone", ContentSettingsType::MEDIASTREAM_MIC},
      {"popups", ContentSettingsType::POPUPS},
      {"sound", ContentSettingsType::SOUND},
      {"autoPictureInPicture", ContentSettingsType::AUTO_PICTURE_IN_PICTURE},
  };
  auto found = types->find(base::SysNSStringToUTF8(permission));
  if (found == types->end()) {
    return std::nullopt;
  }
  return found->second;
}

// The site's content settings, for pages of a web site only.
HostContentSettingsMap* SettingsFor(content::WebContents* contents, GURL* url) {
  if (!contents) {
    return nullptr;
  }
  *url = contents->GetLastCommittedURL();
  if (!url->SchemeIsHTTPOrHTTPS()) {
    return nullptr;
  }
  return HostContentSettingsMapFactory::GetForProfile(
      contents->GetBrowserContext());
}

}  // namespace

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
    g_activating = _webContents;
    strip->ActivateTabAt(index);
    g_activating = nullptr;
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

// Picture-in-picture, as in Arc: the playing video floats in Chromium's own
// picture-in-picture window (always on top, movable, resizable) while the page is off
// screen, and comes back when it returns.
- (void)enterPictureInPictureIfPlaying {
  if (_webContents && !IsInPictureInPicture(_webContents)) {
    EnterPictureInPicture(_webContents);
  }
}

- (void)exitPictureInPicture {
  if (IsInPictureInPicture(_webContents)) {
    PictureInPictureWindowManager::GetInstance()->ExitPictureInPicture();
  }
}

- (void)togglePictureInPicture {
  if (!_webContents) {
    return;
  }
  if (IsInPictureInPicture(_webContents)) {
    PictureInPictureWindowManager::GetInstance()->ExitPictureInPicture();
  } else {
    EnterPictureInPicture(_webContents);
  }
}

// Site controls: what the page's site may do, as Chromium's content settings keep it
// (the same ones its permission prompts and chrome://settings/content change).
- (NSString*)permissionState:(NSString*)permission {
  GURL url;
  HostContentSettingsMap* settings = SettingsFor(_webContents, &url);
  std::optional<ContentSettingsType> type = PermissionType(permission);
  if (!settings || !type) {
    return nil;
  }
  switch (settings->GetContentSetting(url, url, *type)) {
    case CONTENT_SETTING_ALLOW:
      return @"allow";
    case CONTENT_SETTING_BLOCK:
      return @"block";
    default:
      return @"ask";
  }
}

- (void)setPermission:(NSString*)permission state:(NSString*)state {
  GURL url;
  HostContentSettingsMap* settings = SettingsFor(_webContents, &url);
  std::optional<ContentSettingsType> type = PermissionType(permission);
  if (!settings || !type) {
    return;
  }
  ContentSetting setting = CONTENT_SETTING_DEFAULT;
  if ([state isEqualToString:@"allow"]) {
    setting = CONTENT_SETTING_ALLOW;
  } else if ([state isEqualToString:@"block"]) {
    setting = CONTENT_SETTING_BLOCK;
  } else if ([state isEqualToString:@"ask"]) {
    setting = CONTENT_SETTING_ASK;
  }
  settings->SetContentSettingDefaultScope(url, url, *type, setting);
}

- (BOOL)permissionIsSiteSpecific:(NSString*)permission {
  GURL url;
  HostContentSettingsMap* settings = SettingsFor(_webContents, &url);
  std::optional<ContentSettingsType> type = PermissionType(permission);
  if (!settings || !type) {
    return NO;
  }
  content_settings::SettingInfo info;
  settings->GetContentSetting(url, url, *type, &info);
  return info.source == content_settings::SettingSource::kUser &&
         !info.primary_pattern.MatchesAllHosts();
}

// Docked DevTools: their WebContents fills the page's area, the page sits where the
// DevTools' layout leaves room (the same strategy as Chromium's DevtoolsUIController).
- (NSView*)devToolsView {
  content::WebContents* devtools =
      _webContents ? DevToolsWindow::GetInTabWebContents(_webContents, nullptr)
                   : nullptr;
  return devtools ? devtools->GetNativeView().GetNativeNSView() : nil;
}

- (NSRect)pageFrameWithDevToolsIn:(NSSize)size {
  gfx::Rect container(0, 0, size.width, size.height);
  DevToolsContentsResizingStrategy strategy;
  if (!_webContents ||
      !DevToolsWindow::GetInTabWebContents(_webContents, &strategy)) {
    return container.ToCGRect();
  }
  gfx::Rect devtools_bounds;
  gfx::Rect contents_bounds;
  ApplyDevToolsContentsResizingStrategy(strategy, container, &devtools_bounds,
                                        &contents_bounds);
  return contents_bounds.ToCGRect();
}

@end

// MARK: - Tabs Chromium opens or closes by itself

@interface ChordEngine ()
- (void)announcePage:(ChordPage*)page
              opener:(ChordPage*)opener
        inBackground:(BOOL)inBackground;
- (void)announceClosedPage:(ChordPage*)page;
- (void)announceShowPage:(ChordPage*)page;
- (BOOL)ownsProfile:(Profile*)profile;
@end

namespace {

// The engine of the profile a page belongs to, so that a link opened from a private
// window stays in private browsing.
ChordEngine* EngineFor(content::WebContents* contents) {
  Profile* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
  ChordEngine* found = nil;
  for (ChordEngine* engine in Engines()) {
    if ([engine ownsProfile:profile]) {
      found = engine;
    }
  }
  return found;
}

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
      case TabStripModelChange::kSelectionOnly:
        // Chromium made a tab active by itself: ChordUI shows it.
        if (selection.active_tab_changed() && selection.new_contents &&
            selection.new_contents != g_activating) {
          TabActivated(selection.new_contents);
        }
        break;
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
    ChordEngine* engine = EngineFor(contents);
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

  void TabActivated(content::WebContents* contents) {
    chord::ShowPage(contents);
  }

  // A tab closed by Chromium (`window.close()`, an extension). A tab ChordUI closed
  // has already let go of its page, which is then gone from Pages().
  void TabClosed(content::WebContents* contents) {
    ChordPage* page = PageFor(contents);
    if (!page) {
      return;
    }
    ChordEngine* engine = EngineFor(contents);
    [page detach];
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
  // The user's profile. A private engine uses its off-the-record profile, asked for
  // each time: Chromium destroys it when its last private page closes.
  raw_ptr<Profile> _profile;
  // Chromium destroys a profile when its last browser closes, and ChordUI's browser
  // closes with its last page (all tabs closed or asleep): the engine keeps its
  // profile alive, as an open window would.
  std::unique_ptr<ScopedProfileKeepAlive> _profileKeepAlive;
  BOOL _private;
  raw_ptr<BrowserWindowInterface> _browser;
  base::CallbackListSubscription _browserDidClose;
  id<ChordWebEngineDelegate> __weak _delegate;
}

- (instancetype)initWithProfile:(Profile*)profile {
  return [self initWithProfile:profile private:NO];
}

- (instancetype)initWithProfile:(Profile*)profile private:(BOOL)isPrivate {
  if ((self = [super init])) {
    _profile = profile;
    _profileKeepAlive = std::make_unique<ScopedProfileKeepAlive>(
        profile, ProfileKeepAliveOrigin::kBrowserWindow);
    _private = isPrivate;
    [Engines() addObject:self];
  }
  return self;
}

- (Profile*)profile {
  return _private ? _profile->GetPrimaryOTRProfile(/*create_if_needed=*/true)
                  : _profile.get();
}

- (BOOL)ownsProfile:(Profile*)profile {
  if (_private) {
    return profile->IsOffTheRecord() &&
           profile->GetOriginalProfile() == _profile.get();
  }
  return profile == _profile.get();
}

// Private browsing (⇧⌘N): Chromium's incognito profile, its own browser and tabs.
- (id<ChordWebEngine>)makePrivateEngine {
  return [[ChordEngine alloc] initWithProfile:_profile private:YES];
}

// The browser that holds ChordUI's pages. Created on first use, and again if
// Chromium closed it (its last tab closed).
- (BrowserWindowInterface*)browser {
  if (_browser && !_browser->IsDeleteScheduled()) {
    return _browser;
  }
  BrowserWindowCreateParams params(BrowserWindowInterface::TYPE_NORMAL,
                                   [self profile],
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
  content::WebContents::CreateParams params([self profile]);
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

- (void)announceShowPage:(ChordPage*)page {
  if (page.webContents &&
      [_delegate respondsToSelector:@selector(engine:wantsToShow:)]) {
    [_delegate engine:self wantsToShow:page];
  }
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

void ShowPage(content::WebContents* contents) {
  ChordPage* page = contents ? PageFor(contents) : nil;
  ChordEngine* engine = contents ? EngineFor(contents) : nil;
  if (!page || !engine) {
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    [engine announceShowPage:page];
  });
}

bool CanDockDevTools(BrowserWindowInterface* browser) {
  return IsEnabled() && browser &&
         browser->GetType() == BrowserWindowInterface::Type::TYPE_NORMAL;
}

// Later, outside DevTools' own update (it may be tearing down).
void UpdateDevTools(content::WebContents* inspected) {
  if (ChordPage* page = PageFor(inspected)) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [page notifyUpdate];
    });
  }
}

}  // namespace chord
