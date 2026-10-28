// Copyright 2026 The Chord Authors

#import "chord/browser/chord_engine.h"

#include "chord/browser/chord_arc_import.h"
#include "chord/browser/chord_data_migration.h"
#include "chord/browser/chord_downloads.h"
#include "chord/browser/chord_extensions.h"
#include "chord/browser/chord_hooks.h"
#include "chord/browser/chord_suggester.h"

#include <map>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "base/files/file_path.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "components/content_settings/core/browser/content_settings_registry.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/content_settings/core/browser/website_settings_info.h"
#include "components/content_settings/core/browser/website_settings_registry.h"
#include "components/content_settings/core/common/content_settings.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "chrome/browser/devtools/devtools_contents_resizing_strategy.h"
#include "chrome/browser/devtools/devtools_toggle_action.h"
#include "chrome/browser/devtools/devtools_ui_bindings.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/lifetime/application_lifetime.h"
#include "chrome/browser/lifetime/browser_shutdown.h"
#include "chrome/browser/media/webrtc/media_capture_devices_dispatcher.h"
#include "chrome/browser/media/webrtc/media_stream_capture_indicator.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_window_manager.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "chrome/browser/profiles/delete_profile_helper.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_attributes_entry.h"
#include "chrome/browser/profiles/profile_attributes_storage.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/profile_metrics.h"
#include "chrome/browser/resource_coordinator/tab_lifecycle_unit_external.h"
#include "chrome/browser/ssl/chrome_security_state_util.h"
#include "components/security_state/core/security_state.h"
#include "chrome/common/pref_names.h"
#include "chrome/browser/ui/browser_active_state_manager/browser_active_state_manager.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "components/find_in_page/find_result_observer.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/find_in_page/find_types.h"
#include "components/page_info/page_info_ui.h"
#include "components/autofill/core/common/autofill_prefs.h"
#include "components/password_manager/core/common/password_manager_pref_names.h"
#include "components/prefs/pref_service.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/media_session.h"
#include "chrome/browser/history/history_service_factory.h"
#include "components/history/core/browser/history_service.h"
#include "components/history/core/browser/url_row.h"
#include "components/keyed_service/core/service_access_type.h"
#include "services/media_session/public/mojom/media_session.mojom.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "chrome/common/chrome_isolated_world_ids.h"
#include "third_party/blink/public/mojom/frame/media_player_action.mojom.h"
#include "ui/gfx/geometry/point.h"
#include "content/public/browser/reload_type.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/common/page_zoom.h"
#include "components/zoom/page_zoom.h"
#include "components/zoom/zoom_controller.h"
#include "printing/buildflags/buildflags.h"
#include "net/base/apple/url_conversions.h"
#include "third_party/blink/public/mojom/favicon/favicon_url.mojom.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "ui/gfx/codec/png_codec.h"
#include "ui/gfx/geometry/size.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"

#if BUILDFLAG(ENABLE_PRINTING)
#include "chrome/browser/printing/print_view_manager_common.h"
#endif

@class ChordPage;

@interface ChordEngine ()
// The profile's extensions, for its pages; nullptr for a private engine.
- (chord::ExtensionsWatcher*)extensionsWatcher;
@end

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

// Tells a page when it starts or stops sharing a screen, a window or a tab, or when
// it is the tab being shared: the sidebar shows it, with a way to stop.
class CaptureWatcher : public MediaStreamCaptureIndicator::Observer {
 public:
  static void Ensure() { static base::NoDestructor<CaptureWatcher> watcher; }

  CaptureWatcher()
      : indicator_(MediaCaptureDevicesDispatcher::GetInstance()
                       ->GetMediaStreamCaptureIndicator()) {
    indicator_->AddObserver(this);
  }

  // MediaStreamCaptureIndicator::Observer:
  void OnIsCapturingVideoChanged(content::WebContents* contents,
                                 bool capturing) override {
    Update(contents);
  }
  void OnIsCapturingAudioChanged(content::WebContents* contents,
                                 bool capturing) override {
    Update(contents);
  }
  void OnIsBeingMirroredChanged(content::WebContents* contents,
                                bool mirrored) override {
    Update(contents);
  }
  void OnIsCapturingTabChanged(content::WebContents* contents,
                               bool capturing) override {
    Update(contents);
  }
  void OnIsCapturingWindowChanged(content::WebContents* contents,
                                  bool capturing) override {
    Update(contents);
  }
  void OnIsCapturingDisplayChanged(content::WebContents* contents,
                                   bool capturing) override {
    Update(contents);
  }

 private:
  void Update(content::WebContents* contents);

  scoped_refptr<MediaStreamCaptureIndicator> indicator_;
};

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

// A WebContents made hidden (a tab opened in the background, the one a sleeping
// tab gets) has its view hidden until Chrome's Views show it: in Chord, ChordUI
// shows it by placing it in a window.
void UnhideView(content::WebContents* contents) {
  contents->GetNativeView().GetNativeNSView().hidden = NO;
}

// Quitting closes every tab: ChordUI must not see that as the user closing them.
bool IsQuitting() {
  return browser_shutdown::IsTryingToQuit() ||
         browser_shutdown::HasShutdownStarted();
}

}  // namespace

// MARK: - ChordPage

namespace {

// What a site may be given, as Chromium's own page info lists it on the Mac:
// notifications first, as they always show.
constexpr ContentSettingsType kSitePermissions[] = {
    ContentSettingsType::NOTIFICATIONS,
    ContentSettingsType::GEOLOCATION,
    ContentSettingsType::MEDIASTREAM_CAMERA,
    ContentSettingsType::CAMERA_PAN_TILT_ZOOM,
    ContentSettingsType::MEDIASTREAM_MIC,
    ContentSettingsType::SENSORS,
    ContentSettingsType::JAVASCRIPT,
    ContentSettingsType::IMAGES,
    ContentSettingsType::POPUPS,
    ContentSettingsType::WINDOW_MANAGEMENT,
    ContentSettingsType::BACKGROUND_SYNC,
    ContentSettingsType::SOUND,
    ContentSettingsType::AUTOMATIC_DOWNLOADS,
    ContentSettingsType::MIDI_SYSEX,
    ContentSettingsType::CLIPBOARD_READ_WRITE,
    ContentSettingsType::USB_GUARD,
    ContentSettingsType::HID_GUARD,
    ContentSettingsType::SERIAL_GUARD,
    ContentSettingsType::FILE_SYSTEM_WRITE_GUARD,
    ContentSettingsType::LOCAL_FONTS,
    ContentSettingsType::BLUETOOTH_GUARD,
    ContentSettingsType::BLUETOOTH_SCANNING,
    ContentSettingsType::HAND_TRACKING,
    ContentSettingsType::VR,
    ContentSettingsType::AR,
    ContentSettingsType::IDLE_DETECTION,
    ContentSettingsType::AUTO_PICTURE_IN_PICTURE,
    ContentSettingsType::CAPTURED_SURFACE_CONTROL,
    ContentSettingsType::AUTOMATIC_FULLSCREEN,
    ContentSettingsType::KEYBOARD_LOCK,
    ContentSettingsType::POINTER_LOCK,
    ContentSettingsType::WEB_APP_INSTALLATION,
    ContentSettingsType::LOCAL_NETWORK,
    ContentSettingsType::LOOPBACK_NETWORK,
};

// A permission by the name Chromium's registry gives it ("notifications",
// "media_stream_camera"…), which is how ChordUI names them. Content settings only.
std::optional<ContentSettingsType> PermissionType(NSString* permission) {
  const content_settings::WebsiteSettingsInfo* info =
      content_settings::WebsiteSettingsRegistry::GetInstance()->GetByName(
          base::SysNSStringToUTF8(permission));
  if (!info ||
      !content_settings::ContentSettingsRegistry::GetInstance()->Get(
          info->type())) {
    return std::nullopt;
  }
  return info->type();
}

NSString* StateName(ContentSetting setting) {
  switch (setting) {
    case CONTENT_SETTING_ALLOW:
      return @"allow";
    case CONTENT_SETTING_BLOCK:
      return @"block";
    default:
      return @"ask";
  }
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
// A page whose profile is still loading: it gets its WebContents once the profile
// is ready, and loads then what it was asked to.
- (instancetype)initWaitingForProfile;
@property(nonatomic, readonly) content::WebContents* webContents;
// The engine that made or adopted the page.
@property(nonatomic, weak) ChordEngine* engine;
// The profile is ready: the page takes `contents`, then loads what it was asked to
// once the tab is in its browser.
- (void)attachWebContents:(content::WebContents*)contents;
- (void)loadPendingURL;
- (void)notifyUpdate;
- (void)updateFavicon:(const std::vector<blink::mojom::FaviconURLPtr>&)candidates;
- (void)resetFavicon;
// The tab is gone (closed by Chromium, or replaced): forget its WebContents.
- (void)detach;
- (void)replaceWebContents:(content::WebContents*)contents;
- (void)didFindMatches:(int)count active:(int)active final:(BOOL)final;
// Media started or stopped playing in the page (a pause included).
- (void)mediaDidChange:(BOOL)playing;
// A new document: its media is not the previous one's.
- (void)resetMedia;
@end

void CaptureWatcher::Update(content::WebContents* contents) {
  [PageFor(contents) notifyUpdate];
}

namespace {

// Forwards what changes on a page to ChordUI.
class PageObserver : public content::WebContentsObserver,
                     public find_in_page::FindResultObserver {
 public:
  PageObserver(content::WebContents* contents, ChordPage* page)
      : content::WebContentsObserver(contents), page_(page) {}

  // The page's searches, from the first one (the tab's helpers are attached once the
  // page is in its browser, after this observer is made).
  void ObserveFind(find_in_page::FindTabHelper* helper) {
    if (!find_observation_.IsObserving()) {
      find_observation_.Observe(helper);
    }
  }

  // find_in_page::FindResultObserver:
  void OnFindResultAvailable(content::WebContents* contents) override {
    const find_in_page::FindNotificationDetails& result =
        find_in_page::FindTabHelper::FromWebContents(contents)->find_result();
    [page_ didFindMatches:result.number_of_matches()
                   active:result.active_match_ordinal()
                    final:result.final_update()];
  }
  void OnFindTabHelperDestroyed(find_in_page::FindTabHelper* helper) override {
    find_observation_.Reset();
  }

  // content::WebContentsObserver:
  void DidStartLoading() override { [page_ notifyUpdate]; }
  void DidStopLoading() override { [page_ notifyUpdate]; }
  // Before the commit, which ChordUI hears of first through
  // NavigationEntryCommitted.
  void ReadyToCommitNavigation(content::NavigationHandle* handle) override {
    if (handle->IsInPrimaryMainFrame() && !handle->IsSameDocument()) {
      [page_ resetFavicon];
      [page_ resetMedia];
    }
  }
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
  void OnAudioStateChanged(bool audible) override { [page_ notifyUpdate]; }
  // A video in full screen: ChordUI gives the page the whole window.
  void DidToggleFullscreenModeForTab(bool entered_fullscreen,
                                     bool will_cause_resize) override {
    [page_ notifyUpdate];
  }
  void MediaStartedPlaying(const MediaPlayerInfo& info,
                           const content::MediaPlayerId& id) override {
    if (info.has_audio || info.has_video) {
      [page_ mediaDidChange:YES];
    }
  }
  void MediaStoppedPlaying(const MediaPlayerInfo& info,
                           const content::MediaPlayerId& id,
                           MediaStoppedReason reason) override {
    [page_ mediaDidChange:NO];
  }
  void DidUpdateAudioMutingState(bool muted) override { [page_ notifyUpdate]; }
  // A certificate error the user went past, mixed content: the address field says
  // the page is not secure.
  void DidChangeVisibleSecurityState() override { [page_ notifyUpdate]; }
  // The page's renderer crashed or was killed: ChordUI says so, with a way to reload.
  void PrimaryMainFrameRenderProcessGone(
      base::TerminationStatus status) override {
    [page_ notifyUpdate];
  }
  void WebContentsDestroyed() override { [page_ detach]; }

 private:
  ChordPage* __weak page_;
  base::ScopedObservation<find_in_page::FindTabHelper,
                          find_in_page::FindResultObserver>
      find_observation_{this};
};

}  // namespace

@implementation ChordPage {
  raw_ptr<content::WebContents> _webContents;
  std::unique_ptr<PageObserver> _observer;
  NSURL* _faviconURL;
  NSData* _faviconData;
  id<ChordWebPageDelegate> __weak _delegate;
  BOOL _waitingForProfile;
  NSURL* _pendingURL;
  NSView* _placeholder;
  // Players playing now, and whether ChordUI paused them (the sidebar's media
  // controls): a page paused by Chord keeps its controls, one that paused itself
  // does not.
  int _playingMedia;
  BOOL _pausedByChord;
}

@synthesize engine = _engine;

- (instancetype)initWithWebContents:(content::WebContents*)contents {
  if ((self = [super init])) {
    UnhideView(contents);
    _webContents = contents;
    _observer = std::make_unique<PageObserver>(contents, self);
    Pages()[contents] = self;
    CaptureWatcher::Ensure();
  }
  return self;
}

- (instancetype)initWaitingForProfile {
  if ((self = [super init])) {
    _waitingForProfile = YES;
  }
  return self;
}

- (void)attachWebContents:(content::WebContents*)contents {
  _waitingForProfile = NO;
  _placeholder = nil;
  [self replaceWebContents:contents];
}

- (void)loadPendingURL {
  NSURL* url = _pendingURL;
  _pendingURL = nil;
  if (url) {
    [self load:url];
  }
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
  // A page put to sleep keeps its sound off.
  if (_webContents && _webContents->IsAudioMuted()) {
    contents->SetAudioMuted(true);
  }
  UnhideView(contents);
  [self detach];
  _webContents = contents;
  _observer = std::make_unique<PageObserver>(contents, self);
  Pages()[contents] = self;
  CaptureWatcher::Ensure();
  [self notifyUpdate];
}

- (void)notifyUpdate {
  [_delegate pageDidUpdate:self];
}

- (void)didFindMatches:(int)count active:(int)active final:(BOOL)final {
  if ([_delegate respondsToSelector:@selector
                 (page:didFindMatches:activeMatch:isFinal:)]) {
    [_delegate page:self didFindMatches:count activeMatch:active isFinal:final];
  }
}

- (void)mediaDidChange:(BOOL)playing {
  _playingMedia = std::max(0, _playingMedia + (playing ? 1 : -1));
  if (playing) {
    _pausedByChord = NO;
  }
  [self notifyUpdate];
}

- (void)resetMedia {
  _playingMedia = 0;
  _pausedByChord = NO;
}

// A new document declares its own icon: the previous one must not be taken for it.
- (void)resetFavicon {
  _faviconURL = nil;
  _faviconData = nil;
}

// Keeps the largest icon the page declares: the sidebar shows them at 16 pt, at 2x.
// Chromium downloads and decodes it (SVG included, with its text: Figma draws a
// file's emoji that way), and ChordUI gets the result as PNG.
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
  if (!best || !_webContents) {
    return;
  }
  NSURL* iconURL = net::NSURLWithGURL(best->icon_url);
  if ([iconURL isEqual:_faviconURL] && _faviconData) {
    return;
  }
  _faviconURL = iconURL;
  __weak ChordPage* weakSelf = self;
  _webContents->DownloadImage(
      best->icon_url, /*is_favicon=*/true, gfx::Size(64, 64),
      /*max_bitmap_size=*/256, /*bypass_cache=*/false,
      base::BindOnce(^(int, int, const GURL&,
                       const std::vector<SkBitmap>& bitmaps,
                       const std::vector<gfx::Size>&) {
        [weakSelf didDownloadFavicon:iconURL bitmaps:bitmaps];
      }));
}

// The smallest bitmap of 64 px and up (crisp at 32 pt on a Retina screen), else the
// largest. An icon the page has replaced since is dropped.
- (void)didDownloadFavicon:(NSURL*)iconURL
                   bitmaps:(const std::vector<SkBitmap>&)bitmaps {
  if (![iconURL isEqual:_faviconURL]) {
    return;
  }
  const SkBitmap* best = nullptr;
  for (const SkBitmap& bitmap : bitmaps) {
    if (bitmap.drawsNothing()) {
      continue;
    }
    bool large = bitmap.width() >= 64;
    bool bestLarge = best && best->width() >= 64;
    if (!best || (large && (!bestLarge || bitmap.width() < best->width())) ||
        (!large && !bestLarge && bitmap.width() > best->width())) {
      best = &bitmap;
    }
  }
  if (!best) {
    return;
  }
  std::optional<std::vector<uint8_t>> png =
      gfx::PNGCodec::EncodeBGRASkBitmap(*best, /*discard_transparency=*/false);
  if (!png) {
    return;
  }
  _faviconData = [NSData dataWithBytes:png->data() length:png->size()];
  [self notifyUpdate];
}

// MARK: ChordWebPage

- (NSView*)view {
  if (!_webContents) {
    if (!_placeholder) {
      _placeholder = [[NSView alloc] init];
    }
    return _placeholder;
  }
  return _webContents->GetNativeView().GetNativeNSView();
}

- (NSURL*)url {
  if (!_webContents) {
    return _pendingURL;
  }
  const GURL& url = _webContents->GetVisibleURL();
  return url.is_empty() ? nil : net::NSURLWithGURL(url);
}

- (NSString*)title {
  return _webContents ? base::SysUTF16ToNSString(_webContents->GetTitle())
                      : nil;
}

- (BOOL)isLoading {
  if (_waitingForProfile) {
    return _pendingURL != nil;
  }
  return _webContents && _webContents->IsLoading();
}

- (BOOL)canGoBack {
  return _webContents && _webContents->GetController().CanGoBack();
}

- (BOOL)canGoForward {
  return _webContents && _webContents->GetController().CanGoForward();
}

- (NSData*)faviconData {
  // While another page loads, the icon is still the previous one's.
  if (!_webContents ||
      _webContents->GetVisibleURL() != _webContents->GetLastCommittedURL()) {
    return nil;
  }
  return _faviconData;
}

- (id<ChordWebPageDelegate>)delegate {
  return _delegate;
}

- (void)setDelegate:(id<ChordWebPageDelegate>)delegate {
  _delegate = delegate;
}

- (void)load:(NSURL*)url {
  if (_waitingForProfile) {
    _pendingURL = url;
    return;
  }
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

// ⌥⌘I opens the page's developer tools, and closes them when they are open, docked or
// in their own window, as their own close button does. Chromium's "open" always
// opens, and its toggle only brings a separate window forward.
- (void)toggleDevTools {
  if (!_webContents) {
    return;
  }
  if (DevToolsWindow* window =
          DevToolsWindow::GetInstanceForInspectedWebContents(_webContents)) {
    static_cast<DevToolsUIBindings::Delegate*>(window)->CloseWindow();
    return;
  }
  DevToolsWindow::OpenDevToolsWindow(
      _webContents, DevToolsToggleAction::Toggle(),
      DevToolsOpenedByAction::kMainMenuOrMainShortcut);
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
  return StateName(settings->GetContentSetting(url, url, *type));
}

// Notifications, then every permission chosen for this site (allowed or blocked
// here, rather than left to the browser's default), named in the browser's language.
- (NSArray<NSDictionary<NSString*, NSString*>*>*)sitePermissions {
  GURL url;
  HostContentSettingsMap* settings = SettingsFor(_webContents, &url);
  if (!settings) {
    return @[];
  }
  NSMutableArray<NSDictionary<NSString*, NSString*>*>* permissions =
      [NSMutableArray array];
  auto* registry = content_settings::WebsiteSettingsRegistry::GetInstance();
  for (ContentSettingsType type : kSitePermissions) {
    const content_settings::WebsiteSettingsInfo* info = registry->Get(type);
    if (!info) {
      continue;  // Not available in this build.
    }
    content_settings::SettingInfo setting_info;
    ContentSetting setting =
        settings->GetContentSetting(url, url, type, &setting_info);
    bool chosen_for_site =
        setting_info.source == content_settings::SettingSource::kUser &&
        !setting_info.primary_pattern.MatchesAllHosts();
    if (type != ContentSettingsType::NOTIFICATIONS && !chosen_for_site) {
      continue;
    }
    [permissions addObject:@{
      @"id" : base::SysUTF8ToNSString(info->name()),
      @"title" : base::SysUTF16ToNSString(
          PageInfoUI::PermissionTypeToUIString(type)),
      @"state" : StateName(setting),
    }];
  }
  return permissions;
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

// MARK: Extensions

- (NSArray<NSDictionary<NSString*, id>*>*)extensions {
  chord::ExtensionsWatcher* watcher =
      _webContents ? [self.engine extensionsWatcher] : nullptr;
  return watcher ? watcher->ExtensionsFor(_webContents) : @[];
}

- (id<ChordExtensionPopup>)runExtension:(NSString*)extensionID {
  return _webContents ? chord::RunExtension(_webContents,
                                            base::SysNSStringToUTF8(extensionID))
                      : nil;
}

- (void)setExtension:(NSString*)extensionID pinned:(BOOL)pinned {
  if (chord::ExtensionsWatcher* watcher = [self.engine extensionsWatcher]) {
    watcher->SetPinned(base::SysNSStringToUTF8(extensionID), pinned);
  }
}

- (void)uninstallExtension:(NSString*)extensionID {
  if (chord::ExtensionsWatcher* watcher = [self.engine extensionsWatcher]) {
    watcher->Uninstall(base::SysNSStringToUTF8(extensionID));
  }
}

// MARK: Find, zoom, print

// ⌘F: Chromium's find in page, every match highlighted, without its find bar.
- (void)find:(NSString*)text forward:(BOOL)forward {
  find_in_page::FindTabHelper* helper =
      _webContents ? find_in_page::FindTabHelper::FromWebContents(_webContents)
                   : nullptr;
  if (!helper) {
    return;
  }
  _observer->ObserveFind(helper);
  if (text.length == 0) {
    // An empty text would search the previous one again.
    helper->StopFinding(find_in_page::SelectionAction::kClear);
    [self didFindMatches:0 active:0 final:YES];
    return;
  }
  helper->StartFinding(base::SysNSStringToUTF16(text), forward,
                       /*case_sensitive=*/false, /*find_match=*/true);
}

- (void)stopFinding {
  if (find_in_page::FindTabHelper* helper =
          _webContents
              ? find_in_page::FindTabHelper::FromWebContents(_webContents)
              : nullptr) {
    helper->StopFinding(find_in_page::SelectionAction::kKeep);
  }
}

// Chromium keeps the zoom per site, as in Chrome.
- (void)zoom:(NSInteger)direction {
  if (!_webContents) {
    return;
  }
  zoom::PageZoom::Zoom(_webContents, direction > 0   ? content::PAGE_ZOOM_IN
                                     : direction < 0 ? content::PAGE_ZOOM_OUT
                                                     : content::PAGE_ZOOM_RESET);
}

- (NSInteger)zoomPercent {
  zoom::ZoomController* zoom =
      _webContents ? zoom::ZoomController::FromWebContents(_webContents)
                   : nullptr;
  return zoom ? zoom->GetZoomPercent() : 100;
}

// The Mac's own print dialog, as in Safari: Chromium's print preview is made of
// Views and needs Chrome's window.
- (void)printPage {
#if BUILDFLAG(ENABLE_PRINTING)
  if (_webContents) {
    printing::StartBasicPrint(_webContents);
  }
#endif
}

// MARK: Sound and sleep

- (BOOL)isAudible {
  return _webContents && _webContents->IsCurrentlyAudible();
}

- (BOOL)isMuted {
  return _webContents && _webContents->IsAudioMuted();
}

- (void)setMuted:(BOOL)muted {
  if (_webContents) {
    _webContents->SetAudioMuted(muted);
  }
}

- (BOOL)isCapturingMedia {
  if (!_webContents) {
    return NO;
  }
  scoped_refptr<MediaStreamCaptureIndicator> indicator =
      MediaCaptureDevicesDispatcher::GetInstance()
          ->GetMediaStreamCaptureIndicator();
  return indicator->IsCapturingUserMedia(_webContents) ||
         indicator->IsCapturingWindow(_webContents) ||
         indicator->IsCapturingDisplay(_webContents) ||
         indicator->IsBeingMirrored(_webContents);
}

// Sharing a screen, a window or a tab with the site (a video call).
- (BOOL)isSharingScreen {
  if (!_webContents) {
    return NO;
  }
  scoped_refptr<MediaStreamCaptureIndicator> indicator =
      MediaCaptureDevicesDispatcher::GetInstance()
          ->GetMediaStreamCaptureIndicator();
  return indicator->IsCapturingTab(_webContents) ||
         indicator->IsCapturingWindow(_webContents) ||
         indicator->IsCapturingDisplay(_webContents);
}

// The tab another page is sharing.
- (BOOL)isBeingShared {
  if (!_webContents) {
    return NO;
  }
  return MediaCaptureDevicesDispatcher::GetInstance()
      ->GetMediaStreamCaptureIndicator()
      ->IsBeingMirrored(_webContents);
}

// Ends what the page shares (its screen, window or tab), as Chrome's "Stop sharing".
- (void)stopSharing {
  if (!_webContents) {
    return;
  }
  MediaCaptureDevicesDispatcher::GetInstance()
      ->GetMediaStreamCaptureIndicator()
      ->StopMediaCapturing(
          _webContents,
          static_cast<int>(MediaStreamCaptureIndicator::MediaType::kDisplayMedia));
}

// Chromium's verdict on the connection: "secure", "warning" (plain HTTP, mixed
// content), "dangerous" (a certificate error the user went past, a flagged site) or
// "none" (localhost, internal pages).
- (NSString*)securityState {
  if (!_webContents) {
    return @"none";
  }
  switch (chrome_security_state::GetSecurityLevel(_webContents)) {
    case security_state::SECURE:
      return @"secure";
    case security_state::WARNING:
      return @"warning";
    case security_state::DANGEROUS:
      return @"dangerous";
    default:
      return @"none";
  }
}

// The renderer crashed or was killed (not a sleeping tab, which has none either).
- (BOOL)isCrashed {
  return _webContents && _webContents->IsCrashed() &&
         !_webContents->WasDiscarded();
}

// A page element in full screen (a video): the browser window is in full screen
// with it, and ChordUI shows only the page.
- (BOOL)isFullscreen {
  return _webContents && _webContents->IsFullscreen();
}

// The sidebar's media controls, like Arc's mini player: a page playing sound or
// video, or one Chord paused, which it can play again.
- (BOOL)hasMedia {
  return _webContents && (_playingMedia > 0 || _pausedByChord);
}

- (BOOL)isPlayingMedia {
  return _webContents && _playingMedia > 0;
}

// Through the page's media session, as the Mac's media keys do.
- (void)toggleMediaPlayback {
  if (!_webContents || (_playingMedia == 0 && !_pausedByChord)) {
    return;
  }
  content::MediaSession* session = content::MediaSession::Get(_webContents);
  if (_playingMedia > 0) {
    _pausedByChord = YES;
    session->Suspend(media_session::mojom::MediaSession::SuspendType::kUI);
  } else {
    session->Resume(media_session::mojom::MediaSession::SuspendType::kUI);
  }
  [self notifyUpdate];
}

// Chromium's own tab discarding, as Chrome's Memory Saver does it: the renderer goes,
// the tab keeps its history and each page's state (scroll position, form fields),
// which come back when it loads again. The tab strip replaces the WebContents, which
// the page follows (kReplaced).
- (BOOL)sleep {
  if (!_webContents) {
    return NO;
  }
  if (_webContents->WasDiscarded()) {
    return YES;
  }
  // It has not shown a page yet (a tab opened in the background, still loading):
  // asleep, it would have nothing to load again. Its video floats in picture in
  // picture, or its developer tools are open.
  content::NavigationEntry* entry =
      _webContents->GetController().GetLastCommittedEntry();
  if (!entry || entry->IsInitialEntry() || IsInPictureInPicture(_webContents) ||
      DevToolsWindow::GetInstanceForInspectedWebContents(_webContents)) {
    return NO;
  }
  resource_coordinator::TabLifecycleUnitExternal* unit =
      resource_coordinator::TabLifecycleUnitExternal::FromWebContents(
          _webContents);
  return unit &&
         unit->DiscardTab(::mojom::LifecycleUnitDiscardReason::EXTERNAL);
}

- (BOOL)isAsleep {
  return _webContents && _webContents->WasDiscarded();
}

- (void)wake {
  if (!_webContents || !_webContents->WasDiscarded()) {
    return;
  }
  content::NavigationController& controller = _webContents->GetController();
  controller.SetNeedsReload();
  controller.LoadIfNecessary();
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
- (BOOL)announcePermissionRequest:(id<ChordPermissionRequest>)request
                          forPage:(ChordPage*)page;
- (BOOL)ownsProfile:(Profile*)profile;
// The browser holding the engine's pages, without making one.
- (BrowserWindowInterface*)existingBrowser;
// The profile is being deleted: the engine lets go of it.
- (void)forgetProfile;
- (instancetype)initWithProfile:(Profile*)profile
                        private:(BOOL)isPrivate NS_DESIGNATED_INITIALIZER;
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
    page.engine = engine;
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

// The folder of the Chromium profile behind one of ChordUI's profiles, in the user
// data folder: "Chord <id>", with only safe characters.
base::FilePath ProfilePath(NSString* profileID) {
  std::string name = "Chord ";
  for (char c : base::SysNSStringToUTF8(profileID)) {
    name += (isalnum(static_cast<unsigned char>(c)) || c == '-') ? c : '_';
  }
  return g_browser_process->profile_manager()->user_data_dir().Append(name);
}

// Chromium deletes the profile: its data now, its folder at once or, for a profile
// that was open, at the next launch. Nothing to do for one never created.
void DeleteProfileAt(const base::FilePath& path) {
  ProfileManager* manager = g_browser_process->profile_manager();
  if (!manager->GetProfileAttributesStorage().GetProfileAttributesWithPath(
          path)) {
    return;
  }
  manager->GetDeleteProfileHelper().MaybeScheduleProfileForDeletion(
      path, base::DoNothing(), ProfileMetrics::DELETE_PROFILE_SETTINGS);
}

}  // namespace

// MARK: - ChordEngine

@implementation ChordEngine {
  // The user's profile. A private engine uses its off-the-record profile, asked for
  // each time: Chromium destroys it when its last private page closes. Null while
  // the profile of another of ChordUI's profiles loads.
  raw_ptr<Profile> _profile;
  // Chromium destroys a profile when its last browser closes, and ChordUI's browser
  // closes with its last page (all tabs closed or asleep): the engine keeps its
  // profile alive, as an open window would.
  std::unique_ptr<ScopedProfileKeepAlive> _profileKeepAlive;
  BOOL _private;
  raw_ptr<BrowserWindowInterface> _browser;
  base::CallbackListSubscription _browserDidClose;
  id<ChordWebEngineDelegate> __weak _delegate;
  // The engines of ChordUI's other profiles, by ChordUI's profile id.
  NSMutableDictionary<NSString*, ChordEngine*>* _profileEngines;
  // Pages made while the profile loads.
  NSHashTable<ChordPage*>* _waitingPages;
  // The profile is being deleted: the engine lets go of it, and takes it no more.
  BOOL _forgotten;
  // While the command bar searches: suggestions from the profile's history.
  std::unique_ptr<chord::Suggester> _suggester;
  // Work waiting for the profile to load (an Arc import).
  NSMutableArray<void (^)(void)>* _whenProfileLoads;
  std::unique_ptr<chord::ExtensionsWatcher> _extensionsWatcher;
  // The profile's downloads, for ChordUI's downloads panel.
  std::unique_ptr<chord::DownloadsWatcher> _downloadsWatcher;
}

- (instancetype)initWithProfile:(Profile*)profile {
  return [self initWithProfile:profile private:NO];
}

- (instancetype)initWithProfile:(Profile*)profile private:(BOOL)isPrivate {
  if ((self = [super init])) {
    _private = isPrivate;
    _profileEngines = [NSMutableDictionary dictionary];
    _waitingPages = [NSHashTable weakObjectsHashTable];
    _whenProfileLoads = [NSMutableArray array];
    if (profile) {
      [self useProfile:profile];
    }
    [Engines() addObject:self];
  }
  return self;
}

// An engine on the profile in `path`, created there the first time. Pages made
// before it loads wait for it.
- (instancetype)initLoadingProfileAt:(const base::FilePath&)path {
  if ((self = [self initWithProfile:nullptr private:NO])) {
    ChordEngine* __weak weakSelf = self;
    g_browser_process->profile_manager()->CreateProfileAsync(
        path, base::BindOnce(^(Profile* profile) {
          [weakSelf profileDidLoad:profile];
        }));
  }
  return self;
}

- (void)useProfile:(Profile*)profile {
  _profile = profile;
  // ungoogled-chromium turns "Offer to save passwords" off by default: Chord offers,
  // like every browser. A choice made in chord://settings/passwords stays.
  profile->GetPrefs()->SetDefaultPrefValue(
      password_manager::prefs::kCredentialsEnableService, base::Value(true));
  // The same for what forms offer again (the emails typed before, addresses), which
  // Chrome and Arc do by default.
  profile->GetPrefs()->SetDefaultPrefValue(
      autofill::prefs::kAutofillProfileEnabled, base::Value(true));
  // Cards and IBANs too, kept on this Mac ("Save card?" in Chord's prompt).
  profile->GetPrefs()->SetDefaultPrefValue(
      autofill::prefs::kAutofillCreditCardEnabled, base::Value(true));
  // ungoogled-chromium asks where to save each download; Chrome and Arc save them in
  // Downloads, which Chord's panel shows. A choice made in chord://settings stays.
  profile->GetPrefs()->SetDefaultPrefValue(prefs::kPromptForDownload,
                                           base::Value(false));
  _profileKeepAlive = std::make_unique<ScopedProfileKeepAlive>(
      profile, ProfileKeepAliveOrigin::kBrowserWindow);
  _downloadsWatcher = std::make_unique<chord::DownloadsWatcher>([self profile]);
  if (!_private) {
    ChordEngine* __weak weakSelf = self;
    _extensionsWatcher = std::make_unique<chord::ExtensionsWatcher>(
        profile, base::BindRepeating(^{
          [weakSelf announceExtensionsChanged];
        }));
  }
}

- (chord::ExtensionsWatcher*)extensionsWatcher {
  return _extensionsWatcher.get();
}

- (void)announceExtensionsChanged {
  if ([_delegate respondsToSelector:@selector(engineExtensionsDidChange:)]) {
    [_delegate engineExtensionsDidChange:self];
  }
}

- (void)profileDidLoad:(Profile*)profile {
  if (!profile) {
    LOG(ERROR) << "Chord: a profile failed to load";
    return;
  }
  if (_profile || _forgotten) {
    return;
  }
  [self useProfile:profile];
  for (ChordPage* page in _waitingPages.allObjects) {
    std::unique_ptr<content::WebContents> contents =
        content::WebContents::Create(
            content::WebContents::CreateParams([self profile]));
    // Known before the tab strip announces it, so it is not taken for a new tab.
    [page attachWebContents:contents.get()];
    [self browser]->GetTabStripModel()->AppendWebContents(std::move(contents),
                                                          /*foreground=*/false);
    [page loadPendingURL];
  }
  [_waitingPages removeAllObjects];
  NSArray<void (^)(void)>* waiting = [_whenProfileLoads copy];
  [_whenProfileLoads removeAllObjects];
  for (void (^work)(void) in waiting) {
    work();
  }
}

- (Profile*)profile {
  if (!_profile) {
    return nullptr;
  }
  return _private ? _profile->GetPrimaryOTRProfile(/*create_if_needed=*/true)
                  : _profile.get();
}

- (BOOL)ownsProfile:(Profile*)profile {
  if (!_profile) {
    return NO;
  }
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

// Like Arc's profiles: each of ChordUI's profiles is a Chromium profile of its own
// (cookies, storage, history, extensions, passwords), in its own folder.
- (id<ChordWebEngine>)engineForProfile:(NSString*)profileID {
  ChordEngine* engine = _profileEngines[profileID];
  if (!engine) {
    engine = [[ChordEngine alloc] initLoadingProfileAt:ProfilePath(profileID)];
    _profileEngines[profileID] = engine;
  }
  return engine;
}

// No Space uses the profile any more: it goes, to free its space on disk.
- (void)deleteProfile:(NSString*)profileID {
  ChordEngine* engine = _profileEngines[profileID];
  [_profileEngines removeObjectForKey:profileID];
  [engine forgetProfile];
  DeleteProfileAt(ProfilePath(profileID));
}

// Settings › Reset Chord: Chord restarts, and its data goes before anything opens.
- (void)resetAllDataAndRelaunch {
  chord::ScheduleDataReset(
      g_browser_process->profile_manager()->user_data_dir());
  chrome::AttemptRestart();
}

// At launch: the profiles of ChordUI that no Space uses (deleted while Chord was
// not running to the end, from an older session) go too.
- (void)deleteProfilesExcept:(NSArray<NSString*>*)profileIDs {
  std::set<base::FilePath> kept;
  for (NSString* profileID in profileIDs) {
    kept.insert(ProfilePath(profileID));
  }
  std::vector<base::FilePath> unused;
  for (ProfileAttributesEntry* entry : g_browser_process->profile_manager()
                                           ->GetProfileAttributesStorage()
                                           .GetAllProfilesAttributes()) {
    const base::FilePath& path = entry->GetPath();
    if (path.BaseName().value().starts_with("Chord ") && !kept.contains(path)) {
      unused.push_back(path);
    }
  }
  for (const base::FilePath& path : unused) {
    DeleteProfileAt(path);
  }
}

- (void)forgetProfile {
  _forgotten = YES;
  _suggester.reset();
  _extensionsWatcher.reset();
  _downloadsWatcher.reset();
  [_waitingPages removeAllObjects];
  _profileKeepAlive.reset();
  _profile = nullptr;
}

// Pages from the profile's history and bookmarks for what is typed in the command bar.
// An empty text ends the search: nothing is kept between two openings of the bar.
- (void)suggest:(NSString*)text
     completion:
         (void (^)(NSArray<NSDictionary<NSString*, NSString*>*>*))completion {
  Profile* profile = [self profile];
  if (text.length == 0 || !profile) {
    _suggester.reset();
    completion(@[]);
    return;
  }
  if (!_suggester) {
    _suggester = std::make_unique<chord::Suggester>(profile);
  }
  _suggester->Start(base::SysNSStringToUTF16(text), completion);
}

// Arc's logins, passwords, history and site storage for one of its profiles
// ("…/Arc/User Data/Profile 1"), into this engine's profile (never a private one).
- (void)importFromArc:(NSString*)arcProfile
           completion:
               (void (^)(NSDictionary<NSString*, NSNumber*>*))completion {
  ChordEngine* __weak weakSelf = self;
  void (^run)(void) = ^{
    ChordEngine* engine = weakSelf;
    if (!engine || engine->_private || engine->_forgotten || !engine->_profile) {
      completion(@{});
      return;
    }
    chord::ImportArcProfile(
        engine->_profile, base::FilePath(base::SysNSStringToUTF8(arcProfile)),
        base::BindOnce(^(chord::ArcImportCounts counts) {
          completion(@{
            @"cookies" : @(counts.cookies),
            @"passwords" : @(counts.passwords),
            @"pages" : @(counts.pages),
            @"formValues" : @(counts.form_values),
            @"extensions" : @(counts.extensions),
            @"siteStorage" : @(counts.site_storage),
            @"keyDenied" : @(counts.key_denied),
          });
        }));
  };
  if (_profile || _forgotten || _private) {
    run();
  } else {
    [_whenProfileLoads addObject:run];
  }
}

// The same from another browser built on Chromium (Google Chrome, Brave, Edge…):
// `service` and `account` name its keychain item ("Chrome Safe Storage", "Chrome").
- (void)importFromBrowser:(NSString*)name
            keychainService:(NSString*)service
            keychainAccount:(NSString*)account
                    profile:(NSString*)profilePath
                 completion:
                     (void (^)(NSDictionary<NSString*, NSNumber*>*))completion {
  chord::ChromiumSource source{base::SysNSStringToUTF8(name),
                               base::SysNSStringToUTF8(service),
                               base::SysNSStringToUTF8(account)};
  ChordEngine* __weak weakSelf = self;
  void (^run)(void) = ^{
    ChordEngine* engine = weakSelf;
    if (!engine || engine->_private || engine->_forgotten || !engine->_profile) {
      completion(@{});
      return;
    }
    chord::ImportChromiumProfile(
        engine->_profile, source,
        base::FilePath(base::SysNSStringToUTF8(profilePath)),
        base::BindOnce(^(chord::ArcImportCounts counts) {
          completion(@{
            @"cookies" : @(counts.cookies),
            @"passwords" : @(counts.passwords),
            @"pages" : @(counts.pages),
            @"formValues" : @(counts.form_values),
            @"extensions" : @(counts.extensions),
            @"siteStorage" : @(counts.site_storage),
            @"keyDenied" : @(counts.key_denied),
          });
        }));
  };
  if (_profile || _forgotten || _private) {
    run();
  } else {
    [_whenProfileLoads addObject:run];
  }
}

// Pages visited in another browser (Safari), into the profile's history: what the
// command bar suggests. Each has "url" (NSURL), "title", "visits" and "lastVisit"
// (NSDate).
- (void)addHistory:(NSArray<NSDictionary<NSString*, id>*>*)pages {
  ChordEngine* __weak weakSelf = self;
  void (^run)(void) = ^{
    ChordEngine* engine = weakSelf;
    if (!engine || engine->_private || engine->_forgotten || !engine->_profile) {
      return;
    }
    history::HistoryService* history = HistoryServiceFactory::GetForProfile(
        engine->_profile, ServiceAccessType::EXPLICIT_ACCESS);
    if (!history) {
      return;
    }
    history::URLRows rows;
    for (NSDictionary<NSString*, id>* page in pages) {
      NSURL* url = page[@"url"];
      GURL gurl = [url isKindOfClass:[NSURL class]] ? net::GURLWithNSURL(url)
                                                     : GURL();
      if (!gurl.is_valid() || !gurl.SchemeIsHTTPOrHTTPS()) {
        continue;
      }
      history::URLRow row(gurl);
      if (NSString* title = page[@"title"]; [title isKindOfClass:[NSString class]]) {
        row.set_title(base::SysNSStringToUTF16(title));
      }
      NSNumber* visits = page[@"visits"];
      row.set_visit_count(
          std::max(1, [visits isKindOfClass:[NSNumber class]] ? visits.intValue : 1));
      NSDate* last = page[@"lastVisit"];
      row.set_last_visit([last isKindOfClass:[NSDate class]]
                             ? base::Time::FromNSDate(last)
                             : base::Time::Now());
      rows.push_back(std::move(row));
    }
    if (!rows.empty()) {
      history->AddPagesWithDetails(rows, history::SOURCE_SAFARI_IMPORTED);
    }
  };
  if (_profile || _forgotten || _private) {
    run();
  } else {
    [_whenProfileLoads addObject:run];
  }
}

// A download of any of ChordUI's profiles: ChordUI keeps one list for them all.
- (void)cancelDownload:(NSString*)downloadID {
  chord::CancelDownload(base::SysNSStringToUTF8(downloadID));
}

// The user kept a download the browser warned about (a file type that can harm the
// Mac, a file from an insecure address).
- (void)keepDownload:(NSString*)downloadID {
  chord::KeepDownload(base::SysNSStringToUTF8(downloadID));
}

- (BOOL)ownsPage:(id<ChordWebPage>)page {
  return [page isKindOfClass:[ChordPage class]] &&
         static_cast<ChordPage*>(page).engine == self;
}

- (BrowserWindowInterface*)existingBrowser {
  return _browser && !_browser->IsDeleteScheduled() ? _browser.get() : nullptr;
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
  if (!_profile) {
    ChordPage* page = [[ChordPage alloc] initWaitingForProfile];
    page.engine = self;
    [_waitingPages addObject:page];
    return page;
  }
  content::WebContents::CreateParams params([self profile]);
  std::unique_ptr<content::WebContents> contents =
      content::WebContents::Create(params);
  // Known before the tab strip announces it, so it is not taken for a new tab.
  ChordPage* page = [[ChordPage alloc] initWithWebContents:contents.get()];
  page.engine = self;
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

- (BOOL)announcePermissionRequest:(id<ChordPermissionRequest>)request
                          forPage:(ChordPage*)page {
  if (![_delegate respondsToSelector:@selector(engine:page:requests:)]) {
    return NO;
  }
  [_delegate engine:self page:page requests:request];
  return YES;
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

id<ChordWebPage> PageForContents(content::WebContents* contents) {
  return contents ? PageFor(contents) : nil;
}

id<ChordWebPage> ActivePageForProfile(content::BrowserContext* context) {
  Profile* profile = Profile::FromBrowserContext(context);
  for (ChordEngine* engine in Engines()) {
    if (![engine ownsProfile:profile]) {
      continue;
    }
    BrowserWindowInterface* browser = [engine existingBrowser];
    content::WebContents* active =
        browser ? browser->GetTabStripModel()->GetActiveWebContents() : nullptr;
    if (ChordPage* page = active ? PageFor(active) : nil) {
      return page;
    }
  }
  return nil;
}

bool RequestPermission(content::WebContents* contents,
                       id<ChordPermissionRequest> request) {
  ChordPage* page = contents ? PageFor(contents) : nil;
  ChordEngine* engine = contents ? EngineFor(contents) : nil;
  return page && engine &&
         [engine announcePermissionRequest:request forPage:page];
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
