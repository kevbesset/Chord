// Copyright 2026 The Chord Authors

#import "chord/browser/chord_browser_window.h"

#import <AppKit/AppKit.h>

#include "base/functional/bind.h"
#include "base/task/sequenced_task_runner.h"
#import "chord/browser/chord_engine.h"
#import "chord/browser/chord_ui.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/themes/theme_service.h"
#include "chrome/browser/ui/browser_active_state_manager/browser_active_state_manager.h"
#include "chrome/browser/ui/browser_command_controller.h"
#include "chrome/browser/ui/browser_manager_service.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_context.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_manager.h"
#include "chrome/browser/ui/exclusive_access/fullscreen_controller.h"
#include "chrome/browser/ui/find_bar/find_bar.h"
#include "chrome/browser/ui/location_bar/location_bar.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/unload_controller.h"
#include "chrome/browser/ui/views/bubble_anchor_util_views.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/web_modal/web_contents_modal_dialog_host.h"
#include "content/public/browser/eye_dropper.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/mojom/window_show_state.mojom.h"
#include "ui/color/color_provider_manager.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "ui/native_theme/native_theme.h"

// MARK: - Location bar

// Chromium asks the window for its location bar in many places. Chord's address bar
// is ChordUI's, so this one only answers with the active page and its browser.
class ChordLocationBar : public LocationBar {
 public:
  explicit ChordLocationBar(BrowserWindowInterface* browser)
      : LocationBar(chrome::BrowserCommandController::From(browser)),
        browser_(browser) {}
  ~ChordLocationBar() override = default;

  // LocationBar:
  void FocusLocation(bool is_user_initiated,
                     bool clear_focus_if_failed) override {}
  void FocusSearch() override {}
  void UpdateFocusBehavior(bool toolbar_visible) override {}
  void UpdateContentSettingsIcons() override {}
  void SaveStateToContents(content::WebContents* contents) override {}
  void Revert() override {}
  OmniboxView* GetOmniboxView() override { return nullptr; }
  OmniboxPopupView* GetOmniboxPopupView() override { return nullptr; }
  OmniboxController* GetOmniboxController() override { return nullptr; }
  bool ShouldCloseOmniboxPopup(ui::MouseEvent* event) override { return false; }
  content::WebContents* GetWebContents() override {
    return browser_->GetTabStripModel()->GetActiveWebContents();
  }
  LocationBarModel* GetLocationBarModel() override { return nullptr; }
  std::optional<bubble_anchor_util::AnchorConfiguration> GetChipAnchor()
      override {
    return std::nullopt;
  }
  ChipController* GetChipController() override { return nullptr; }
  void AnnounceAlert(const std::u16string& announcement) override {}
  void OnChanged() override {}
  void UpdateWithoutTabRestore() override {}
  ui::TrackedElement* GetAnchorOrNull() override { return nullptr; }
  BrowserWindowInterface* GetBrowser() override { return browser_; }
  Profile* GetProfile() override { return browser_->GetProfile(); }
  bool IsInitialized() const override { return true; }
  bool IsVisible() const override { return false; }
  bool IsDrawn() const override { return false; }
  bool IsFullscreen() const override { return false; }
  bool IsEditingOrEmpty() const override { return false; }
  bool IsMouseHovered() const override { return false; }
  bool IsFocusWithin() const override { return false; }
  void InvalidateLayout() override {}
  gfx::Rect Bounds() const override { return gfx::Rect(); }
  gfx::Rect BoundsInScreen() const override { return gfx::Rect(); }
  gfx::Size MinimumSize() const override { return gfx::Size(); }
  gfx::Size PreferredSize() const override { return gfx::Size(); }
  void Update(content::WebContents* contents) override {}
  void ResetTabState(content::WebContents* contents) override {}
  bool HasSecurityStateChanged() override { return false; }
  LocationBarTesting* GetLocationBarForTesting() override { return nullptr; }

 private:
  const raw_ptr<BrowserWindowInterface> browser_;
};

// MARK: - Dialogs

// Where tab-modal dialogs (alert, confirm, permission prompts) go: centred over the
// page, at its top edge.
class ChordModalDialogHost : public web_modal::WebContentsModalDialogHost {
 public:
  explicit ChordModalDialogHost(ChordBrowserWindow* window) : window_(window) {}
  ~ChordModalDialogHost() override {
    observers_.Notify(&web_modal::ModalDialogHostObserver::OnHostDestroying);
  }

  // web_modal::WebContentsModalDialogHost:
  gfx::NativeView GetHostView() const override {
    NSWindow* window = window_->GetNativeWindow().GetNativeNSWindow();
    return gfx::NativeView(window.contentView);
  }
  gfx::Point GetDialogPosition(const gfx::Size& size) override {
    gfx::Rect contents = window_->GetContentsBoundsInWindow();
    return gfx::Point(contents.x() + (contents.width() - size.width()) / 2,
                      contents.y());
  }
  bool ShouldActivateDialog() const override { return true; }
  gfx::Size GetMaximumDialogSize() override {
    return window_->GetContentsBoundsInWindow().size();
  }
  void AddObserver(web_modal::ModalDialogHostObserver* observer) override {
    observers_.AddObserver(observer);
  }
  void RemoveObserver(web_modal::ModalDialogHostObserver* observer) override {
    observers_.RemoveObserver(observer);
  }

 private:
  const raw_ptr<ChordBrowserWindow> window_;
  base::ObserverList<web_modal::ModalDialogHostObserver> observers_;
};

// MARK: - Fullscreen

// A page asking for fullscreen (a video) puts the window in fullscreen. Chromium is
// told when the window has actually changed, as BrowserView does.
class ChordExclusiveAccessContext : public ExclusiveAccessContext {
 public:
  explicit ChordExclusiveAccessContext(ChordBrowserWindow* window)
      : window_(window) {
    auto changed = ^(NSNotification* notification) {
      if (notification.object == Window()) {
        if (auto* manager = ExclusiveAccessManager::From(window_->browser())) {
          manager->fullscreen_controller()->WindowFullscreenStateChanged();
        }
      }
    };
    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    enter_observer_ =
        [center addObserverForName:NSWindowDidEnterFullScreenNotification
                            object:nil
                             queue:nil
                        usingBlock:changed];
    exit_observer_ =
        [center addObserverForName:NSWindowDidExitFullScreenNotification
                            object:nil
                             queue:nil
                        usingBlock:changed];
  }
  ~ChordExclusiveAccessContext() override {
    [NSNotificationCenter.defaultCenter removeObserver:enter_observer_];
    [NSNotificationCenter.defaultCenter removeObserver:exit_observer_];
  }

  // ExclusiveAccessContext:
  Profile* GetProfile() override { return window_->browser()->GetProfile(); }
  bool IsFullscreen() const override { return window_->IsFullscreen(); }
  void EnterFullscreen(const url::Origin& origin,
                       ExclusiveAccessBubbleType bubble_type,
                       FullscreenTabParams fullscreen_tab_params) override {
    if (!IsFullscreen()) {
      [Window() toggleFullScreen:nil];
    }
  }
  void ExitFullscreen() override {
    if (IsFullscreen()) {
      [Window() toggleFullScreen:nil];
    }
  }
  void UpdateExclusiveAccessBubble(
      const ExclusiveAccessBubbleParams& params,
      ExclusiveAccessBubbleHideCallback first_hide_callback) override {
    if (first_hide_callback) {
      std::move(first_hide_callback)
          .Run(ExclusiveAccessBubbleHideReason::kNotShown);
    }
  }
  bool IsExclusiveAccessBubbleDisplayed() const override { return false; }
  void OnExclusiveAccessUserInput() override {}
  content::WebContents* GetWebContentsForExclusiveAccess() override {
    return window_->browser()->GetTabStripModel()->GetActiveWebContents();
  }
  bool CanUserEnterFullscreen() const override { return true; }
  bool CanUserExitFullscreen() const override { return true; }

 private:
  NSWindow* Window() const {
    return window_->GetNativeWindow().GetNativeNSWindow();
  }

  const raw_ptr<ChordBrowserWindow> window_;
  id enter_observer_;
  id exit_observer_;
};

// MARK: - Window

namespace {

Class<ChordUIHostInterface> Host() {
  return (Class<ChordUIHostInterface>)NSClassFromString(@"ChordUIHost");
}

}  // namespace

ChordBrowserWindow::ChordBrowserWindow(BrowserWindowInterface* browser)
    : browser_(browser),
      location_bar_(std::make_unique<ChordLocationBar>(browser)),
      modal_dialog_host_(std::make_unique<ChordModalDialogHost>(this)),
      exclusive_access_context_(
          std::make_unique<ChordExclusiveAccessContext>(this)) {
  chord::WatchBrowser(browser);
}

ChordBrowserWindow::~ChordBrowserWindow() {
  browser_->GetFeatures().TearDownPreBrowserWindowDestruction();
}

// The window of the active page: the main window, or a little window.
gfx::NativeWindow ChordBrowserWindow::GetNativeWindow() const {
  NSWindow* window = nil;
  if (content::WebContents* contents =
          browser_->GetTabStripModel()->GetActiveWebContents()) {
    window = contents->GetNativeView().GetNativeNSView().window;
  }
  if (!window) {
    window = [Host() mainWindow];
  }
  return gfx::NativeWindow(window);
}

bool ChordBrowserWindow::IsActive() const {
  return GetNativeWindow().GetNativeNSWindow().isKeyWindow;
}

bool ChordBrowserWindow::IsMaximized() const {
  return GetNativeWindow().GetNativeNSWindow().isZoomed;
}

bool ChordBrowserWindow::IsMinimized() const {
  return GetNativeWindow().GetNativeNSWindow().isMiniaturized;
}

bool ChordBrowserWindow::IsFullscreen() const {
  NSWindow* window = GetNativeWindow().GetNativeNSWindow();
  return window && (window.styleMask & NSWindowStyleMaskFullScreen) != 0;
}

gfx::Rect ChordBrowserWindow::GetContentsBoundsInWindow() const {
  content::WebContents* contents =
      browser_->GetTabStripModel()->GetActiveWebContents();
  NSView* view = contents ? contents->GetNativeView().GetNativeNSView() : nil;
  NSView* content_view = view.window.contentView;
  if (!view || !content_view) {
    return gfx::Rect();
  }
  NSRect frame = [view convertRect:view.bounds toView:nil];
  CGFloat height = content_view.bounds.size.height;
  return gfx::Rect(frame.origin.x, height - NSMaxY(frame), frame.size.width,
                   frame.size.height);
}

gfx::Rect ChordBrowserWindow::GetRestoredBounds() const {
  return GetBounds();
}

ui::mojom::WindowShowState ChordBrowserWindow::GetRestoredState() const {
  return ui::mojom::WindowShowState::kNormal;
}

gfx::Rect ChordBrowserWindow::GetBounds() const {
  NSWindow* window = GetNativeWindow().GetNativeNSWindow();
  return window ? gfx::ScreenRectFromNSRect(window.frame) : gfx::Rect();
}

// Chromium shows a browser when it opened something in it: bring ChordUI forward.
void ChordBrowserWindow::Show() {
  BrowserActiveStateManager::From(browser_)->DidBecomeActive();
  [Host() reopen];
}

void ChordBrowserWindow::Hide() {}

bool ChordBrowserWindow::IsVisible() const {
  return GetNativeWindow().GetNativeNSWindow().isVisible;
}

void ChordBrowserWindow::ShowInactive() {}

// Like BrowserView: give unload handlers their chance, close the tabs, and once the
// tab strip is empty (Chromium calls Close() again then), destroy the browser.
// ChordUI's window stays: it belongs to ChordUI, not to this browser.
void ChordBrowserWindow::Close() {
  if (closing_) {
    return;
  }
  UnloadController* unload = UnloadController::From(browser_);
  if (!unload->HandleBeforeClose()) {
    return;
  }
  unload->OnWindowClosing();
  if (!browser_->GetTabStripModel()->empty()) {
    return;
  }
  closing_ = true;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&ChordBrowserWindow::DestroyBrowser,
                                weak_factory_.GetWeakPtr()));
}

void ChordBrowserWindow::DestroyBrowser() {
  BrowserManagerService::SynchronouslyDestroyBrowser(browser_);
}

void ChordBrowserWindow::Activate() {
  [GetNativeWindow().GetNativeNSWindow() makeKeyAndOrderFront:nil];
}

void ChordBrowserWindow::Deactivate() {}

void ChordBrowserWindow::Maximize() {}
void ChordBrowserWindow::Minimize() {
  [GetNativeWindow().GetNativeNSWindow() miniaturize:nil];
}
void ChordBrowserWindow::Restore() {}

// The size is ChordUI's to choose (extensions asking to resize are ignored).
void ChordBrowserWindow::SetBounds(const gfx::Rect& bounds) {}

void ChordBrowserWindow::FlashFrame(bool flash) {}

ui::ZOrderLevel ChordBrowserWindow::GetZOrderLevel() const {
  return ui::ZOrderLevel::kNormal;
}

void ChordBrowserWindow::SetZOrderLevel(ui::ZOrderLevel order) {}

bool ChordBrowserWindow::IsOnCurrentWorkspace() const {
  return GetNativeWindow().GetNativeNSWindow().isOnActiveSpace;
}

bool ChordBrowserWindow::IsVisibleOnScreen() const {
  return IsVisible();
}

void ChordBrowserWindow::SetTopControlsShownRatio(
    content::WebContents* web_contents,
    float ratio) {}

bool ChordBrowserWindow::DoBrowserControlsShrinkRendererSize(
    const content::WebContents* contents) const {
  return false;
}

ui::NativeTheme* ChordBrowserWindow::GetNativeTheme() {
  return ui::NativeTheme::GetInstanceForNativeUi();
}

const ui::ThemeProvider* ChordBrowserWindow::GetThemeProvider() const {
  return &ThemeService::GetThemeProviderForProfile(browser_->GetProfile());
}

const ui::ColorProvider* ChordBrowserWindow::GetColorProvider() const {
  return ui::ColorProviderManager::Get().GetColorProviderFor(
      ui::NativeTheme::GetInstanceForNativeUi()->GetColorProviderKey(nullptr));
}

int ChordBrowserWindow::GetTopControlsHeight() const {
  return 0;
}

void ChordBrowserWindow::SetTopControlsGestureScrollInProgress(
    bool in_progress) {}

std::vector<StatusBubble*> ChordBrowserWindow::GetStatusBubbles() {
  return {};
}

void ChordBrowserWindow::UpdateTitleBar() {}
void ChordBrowserWindow::UpdateLoadingAnimations(bool is_visible) {}

// ChordUI chose the page (didBecomeActive) and already shows it.
void ChordBrowserWindow::OnActiveTabChanged(content::WebContents* old_contents,
                                            content::WebContents* new_contents,
                                            int index,
                                            int reason) {}

void ChordBrowserWindow::OnTabDetached(content::WebContents* contents,
                                       bool was_active) {}

gfx::Size ChordBrowserWindow::GetContentsSize() const {
  content::WebContents* contents =
      browser_->GetTabStripModel()->GetActiveWebContents();
  return contents ? contents->GetContainerBounds().size() : gfx::Size();
}

void ChordBrowserWindow::SetContentsSize(const gfx::Size& size) {}

autofill::AutofillBubbleHandler*
ChordBrowserWindow::GetAutofillBubbleHandler() {
  return nullptr;
}

LocationBar* ChordBrowserWindow::GetLocationBar() const {
  return location_bar_.get();
}

ui::AcceleratorProvider* ChordBrowserWindow::GetAcceleratorProvider() {
  return this;
}

void ChordBrowserWindow::SetFocusToLocationBar(bool is_user_initiated) {}
void ChordBrowserWindow::UpdateReloadStopState(bool is_loading, bool force) {}
void ChordBrowserWindow::UpdateToolbar(content::WebContents* contents) {}

bool ChordBrowserWindow::UpdateToolbarSecurityState() {
  return false;
}

void ChordBrowserWindow::UpdateCustomTabBarVisibility(bool visible,
                                                      bool animate) {}
void ChordBrowserWindow::ResetToolbarTabState(content::WebContents* contents) {}
void ChordBrowserWindow::FocusToolbar() {}
void ChordBrowserWindow::ToolbarSizeChanged(bool is_animating) {}
void ChordBrowserWindow::TabDraggingStatusChanged(bool is_dragging) {}
void ChordBrowserWindow::LinkOpeningFromGesture(
    WindowOpenDisposition disposition) {}
void ChordBrowserWindow::FocusAppMenu() {}

bool ChordBrowserWindow::IsTabStripEditable() const {
  return true;
}

void ChordBrowserWindow::DisableTabStripEditingForTesting() {}

bool ChordBrowserWindow::IsToolbarVisible() const {
  return false;
}

bool ChordBrowserWindow::IsToolbarShowing() const {
  return false;
}

bool ChordBrowserWindow::IsLocationBarVisible() const {
  return false;
}

void ChordBrowserWindow::ShowUpdateChromeDialog() {}

void ChordBrowserWindow::ShowIntentPickerBubble(
    std::vector<apps::IntentPickerAppInfo> app_info,
    bool show_stay_in_chrome,
    bool show_remember_selection,
    apps::IntentPickerBubbleType bubble_type,
    const std::optional<url::Origin>& initiating_origin,
    IntentPickerResponse callback) {}

void ChordBrowserWindow::ShowBookmarkBubble(const GURL& url,
                                            bool already_bookmarked) {}

ShowTranslateBubbleResult ChordBrowserWindow::ShowTranslateBubble(
    content::WebContents* contents,
    translate::TranslateStep step,
    const std::string& source_language,
    const std::string& target_language,
    translate::TranslateErrors error_type,
    bool is_user_gesture) {
  return ShowTranslateBubbleResult::kBrowserWindowNotValid;
}

DownloadBubbleUIController* ChordBrowserWindow::GetDownloadBubbleUIController() {
  return nullptr;
}

// ChordUI's downloads panel follows them; quitting does not wait for them.
void ChordBrowserWindow::ConfirmBrowserCloseWithPendingDownloads(
    int download_count,
    DownloadCloseType dialog_type,
    base::OnceCallback<void(bool)> callback) {
  std::move(callback).Run(true);
}

void ChordBrowserWindow::ShowAppMenu() {}

void ChordBrowserWindow::PreHandleDragUpdate(const content::DropData& drop_data,
                                             const gfx::PointF& point) {}
void ChordBrowserWindow::PreHandleDragExit() {}
void ChordBrowserWindow::HandleDragEnded() {}

content::KeyboardEventProcessingResult
ChordBrowserWindow::PreHandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  return content::KeyboardEventProcessingResult::NOT_HANDLED;
}

// The page did not use the key: on Mac, shortcuts belong to the menu, which is
// ChordUI's (MainMenu.swift), so the event goes back to it.
bool ChordBrowserWindow::HandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  if (event.skip_if_unhandled ||
      event.GetType() == input::NativeWebKeyboardEvent::Type::kChar ||
      !event.os_event || event.os_event.Get().type != NSEventTypeKeyDown) {
    return false;
  }
  return [[NSApp mainMenu] performKeyEquivalent:event.os_event.Get()];
}

std::unique_ptr<FindBar> ChordBrowserWindow::CreateFindBar() {
  return nullptr;
}

web_modal::WebContentsModalDialogHost*
ChordBrowserWindow::GetWebContentsModalDialogHost() {
  return modal_dialog_host_.get();
}

web_modal::WebContentsModalDialogHost*
ChordBrowserWindow::GetWebContentsModalDialogHostFor(
    content::WebContents* web_contents) {
  return modal_dialog_host_.get();
}

void ChordBrowserWindow::ShowAvatarBubbleFromAvatarButton(
    bool is_source_accelerator) {}
void ChordBrowserWindow::MaybeShowProfileSwitchIPH() {}
void ChordBrowserWindow::MaybeShowSupervisedUserProfileSignInIPH() {}

void ChordBrowserWindow::ShowHatsDialog(
    const std::string& site_id,
    const std::optional<std::string>& hats_histogram_name,
    const std::optional<uint64_t> hats_survey_ukm_id,
    base::OnceClosure success_callback,
    base::OnceClosure failure_callback,
    const SurveyBitsData& product_specific_bits_data,
    const SurveyStringData& product_specific_string_data) {
  std::move(failure_callback).Run();
}

ExclusiveAccessContext* ChordBrowserWindow::GetExclusiveAccessContext() {
  return exclusive_access_context_.get();
}

std::string ChordBrowserWindow::GetWorkspace() const {
  return std::string();
}

bool ChordBrowserWindow::IsVisibleOnAllWorkspaces() const {
  return false;
}

void ChordBrowserWindow::ShowEmojiPanel() {
  [NSApp orderFrontCharacterPalette:nil];
}

std::unique_ptr<content::EyeDropper> ChordBrowserWindow::OpenEyeDropper(
    content::RenderFrameHost* frame,
    content::EyeDropperListener* listener) {
  return nullptr;
}

void ChordBrowserWindow::ShowCaretBrowsingDialog() {}
void ChordBrowserWindow::CreateTabSearchBubble() {}
void ChordBrowserWindow::CloseTabSearchBubble() {}
void ChordBrowserWindow::ShowIncognitoClearBrowsingDataDialog() {}
void ChordBrowserWindow::ShowIncognitoHistoryDisclaimerDialog() {}

bool ChordBrowserWindow::IsUnframedModeEnabled() const {
  return false;
}

bool ChordBrowserWindow::GetCanResize() {
  return true;
}

ui::mojom::WindowShowState ChordBrowserWindow::GetWindowShowState() const {
  if (IsFullscreen()) {
    return ui::mojom::WindowShowState::kFullscreen;
  }
  if (IsMinimized()) {
    return ui::mojom::WindowShowState::kMinimized;
  }
  return ui::mojom::WindowShowState::kNormal;
}

void ChordBrowserWindow::ShowChromeLabs() {}

BrowserView* ChordBrowserWindow::AsBrowserView() {
  return nullptr;
}

bool ChordBrowserWindow::GetAcceleratorForCommandId(
    int command_id,
    ui::Accelerator* accelerator) const {
  return false;
}

void ChordBrowserWindow::DeleteBrowserWindow() {
  delete this;
}
