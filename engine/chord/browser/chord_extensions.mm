// Copyright 2026 The Chord Authors

#import "chord/browser/chord_extensions.h"

#include <algorithm>
#include <vector>

#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/extensions/extension_action_runner.h"
#include "chrome/browser/extensions/extension_tab_util.h"
#include "chrome/browser/extensions/extension_view.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "chrome/browser/extensions/extension_view_host_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "extensions/browser/extension_action.h"
#include "extensions/browser/extension_action_manager.h"
#include "extensions/browser/extension_registrar.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/uninstall_reason.h"
#include "extensions/common/extension.h"
#include "extensions/common/manifest_handlers/options_page_info.h"
#include "skia/ext/skia_utils_mac.h"
#include "ui/gfx/geometry/size.h"
#include "ui/gfx/image/image.h"

@class ChordExtensionPopupImpl;

@interface ChordExtensionPopupImpl : NSObject <ChordExtensionPopup>
- (instancetype)initWithHost:
    (std::unique_ptr<extensions::ExtensionViewHost>)host;
- (void)didResize:(const gfx::Size&)size;
- (void)didLoad;
- (void)requestClose;
@end

namespace chord {
namespace {

// Chrome's bounds for popups.
constexpr gfx::Size kPopupMinSize(25, 25);
constexpr gfx::Size kPopupMaxSize(800, 600);

// The popup's page, sized by its own content, as Chrome's popup view does.
class PopupView : public extensions::ExtensionView {
 public:
  PopupView(extensions::ExtensionViewHost* host, ChordExtensionPopupImpl* popup)
      : host_(host), popup_(popup) {}

  // extensions::ExtensionView:
  gfx::NativeView GetNativeView() override {
    return host_->host_contents()->GetNativeView();
  }
  void ResizeDueToAutoResize(content::WebContents* web_contents,
                             const gfx::Size& new_size) override {
    [popup_ didResize:new_size];
  }
  void RenderFrameCreated(content::RenderFrameHost* frame_host) override {
    if (!frame_host->GetParentOrOuterDocument()) {
      if (content::RenderWidgetHostView* view = frame_host->GetView()) {
        view->EnableAutoResize(kPopupMinSize, kPopupMaxSize);
      }
    }
  }
  // The popup's page did not use the key: on the Mac, ⌘A, ⌘C, ⌘V… belong to the
  // menu (ChordUI's), as for pages in tabs (ChordBrowserWindow).
  bool HandleKeyboardEvent(content::WebContents* source,
                           const input::NativeWebKeyboardEvent& event) override {
    if (event.skip_if_unhandled ||
        event.GetType() == input::NativeWebKeyboardEvent::Type::kChar ||
        !event.os_event || event.os_event.Get().type != NSEventTypeKeyDown) {
      return false;
    }
    return [[NSApp mainMenu] performKeyEquivalent:event.os_event.Get()];
  }
  void OnLoaded() override { [popup_ didLoad]; }

 private:
  raw_ptr<extensions::ExtensionViewHost> host_;
  ChordExtensionPopupImpl* __weak popup_;
};

}  // namespace
}  // namespace chord

@implementation ChordExtensionPopupImpl {
  std::unique_ptr<extensions::ExtensionViewHost> _host;
  std::unique_ptr<chord::PopupView> _popupView;
  NSSize _size;
  BOOL _loaded;
}

@synthesize onResize = _onResize;
@synthesize onClose = _onClose;

- (instancetype)initWithHost:
    (std::unique_ptr<extensions::ExtensionViewHost>)host {
  if ((self = [super init])) {
    _host = std::move(host);
    _popupView = std::make_unique<chord::PopupView>(_host.get(), self);
    _host->set_view(_popupView.get());
    ChordExtensionPopupImpl* __weak weakSelf = self;
    // window.close() from the popup.
    _host->SetCloseHandler(base::BindOnce(^(extensions::ExtensionHost*) {
      [weakSelf requestClose];
    }));
    _host->CreateRendererSoon();
  }
  return self;
}

- (void)dealloc {
  [self close];
}

- (NSView*)view {
  if (!_host) {
    return [[NSView alloc] init];
  }
  return _host->host_contents()->GetNativeView().GetNativeNSView();
}

- (NSSize)preferredSize {
  return _size;
}

- (void)didResize:(const gfx::Size&)size {
  _size = NSMakeSize(size.width(), size.height());
  if (_loaded && _onResize) {
    _onResize();
  }
}

- (void)didLoad {
  _loaded = YES;
  if (_host) {
    _host->host_contents()->WasShown();
  }
  if (_onResize) {
    _onResize();
  }
}

// Later: the host is still running the code that asked.
- (void)requestClose {
  ChordExtensionPopupImpl* __weak weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    ChordExtensionPopupImpl* popup = weakSelf;
    if (popup && popup->_onClose) {
      popup->_onClose();
    }
  });
}

- (void)close {
  if (!_host) {
    return;
  }
  _host->set_view(nullptr);
  _host.reset();
  _popupView.reset();
}

@end

namespace chord {

ExtensionsWatcher::ExtensionsWatcher(Profile* profile,
                                     base::RepeatingClosure changed)
    : profile_(profile), changed_(std::move(changed)) {
  if (ToolbarActionsModel* model = ToolbarActionsModel::Get(profile)) {
    model_observation_.Observe(model);
  }
  if (auto* dispatcher = extensions::ExtensionActionDispatcher::Get(profile)) {
    dispatcher_observation_.Observe(dispatcher);
  }
}

ExtensionsWatcher::~ExtensionsWatcher() = default;

NSArray<NSDictionary<NSString*, id>*>* ExtensionsWatcher::ExtensionsFor(
    content::WebContents* contents) {
  ToolbarActionsModel* model =
      model_observation_.IsObserving() ? ToolbarActionsModel::Get(profile_)
                                       : nullptr;
  if (!model || !model->actions_initialized()) {
    return @[];
  }
  auto* registry = extensions::ExtensionRegistry::Get(profile_);
  auto* manager = extensions::ExtensionActionManager::Get(profile_);
  const int tab_id =
      contents ? extensions::ExtensionTabUtil::GetTabId(contents) : -1;

  // Pinned first, in their order; then the others, by name.
  std::vector<std::string> ids = model->pinned_action_ids();
  std::vector<std::string> others;
  for (const std::string& id : model->action_ids()) {
    if (!model->IsActionPinned(id)) {
      others.push_back(id);
    }
  }
  std::ranges::sort(others, [&](const std::string& a, const std::string& b) {
    return model->GetExtensionName(a) < model->GetExtensionName(b);
  });
  ids.insert(ids.end(), others.begin(), others.end());

  NSMutableArray<NSDictionary<NSString*, id>*>* list = [NSMutableArray array];
  for (const std::string& extension_id : ids) {
    const extensions::Extension* extension =
        registry->enabled_extensions().GetByID(extension_id);
    extensions::ExtensionAction* action =
        extension ? manager->GetExtensionAction(*extension) : nullptr;
    if (!action) {
      continue;
    }
    std::unique_ptr<extensions::ExtensionActionIconFactory>& factory =
        icon_factories_[extension_id];
    if (!factory) {
      factory = std::make_unique<extensions::ExtensionActionIconFactory>(
          extension, action, this);
    }
    NSMutableDictionary<NSString*, id>* item = [NSMutableDictionary dictionary];
    item[@"id"] = base::SysUTF8ToNSString(extension_id);
    item[@"name"] = base::SysUTF8ToNSString(extension->name());
    gfx::Image icon = factory->GetIcon(tab_id);
    if (!icon.IsEmpty()) {
      item[@"icon"] = icon.ToNSImage();
    }
    std::string badge = action->GetDisplayBadgeText(tab_id);
    item[@"badge"] = base::SysUTF8ToNSString(badge);
    if (!badge.empty()) {
      item[@"badgeColor"] =
          skia::SkColorToSRGBNSColor(action->GetBadgeBackgroundColor(tab_id));
    }
    item[@"pinned"] = @(model->IsActionPinned(extension_id));
    const GURL& options =
        extensions::OptionsPageInfo::GetOptionsPage(extension);
    if (options.is_valid()) {
      item[@"options"] = base::SysUTF8ToNSString(options.spec());
    }
    [list addObject:item];
  }
  return list;
}

void ExtensionsWatcher::SetPinned(const std::string& id, bool pinned) {
  if (ToolbarActionsModel* model = ToolbarActionsModel::Get(profile_);
      model && model->HasAction(id)) {
    model->SetActionVisibility(id, pinned);
  }
}

void ExtensionsWatcher::Uninstall(const std::string& id) {
  std::u16string error;
  extensions::ExtensionRegistrar::Get(profile_)->UninstallExtension(
      id, extensions::UNINSTALL_REASON_USER_INITIATED, &error);
}

void ExtensionsWatcher::OnToolbarActionAdded(
    const ToolbarActionsModel::ActionId& id) {
  Changed();
}

void ExtensionsWatcher::OnToolbarActionRemoved(
    const ToolbarActionsModel::ActionId& id) {
  icon_factories_.erase(id);
  Changed();
}

void ExtensionsWatcher::OnToolbarActionUpdated(
    const ToolbarActionsModel::ActionId& id) {
  Changed();
}

void ExtensionsWatcher::OnToolbarModelInitialized() {
  Changed();
}

void ExtensionsWatcher::OnToolbarPinnedActionsChanged() {
  Changed();
}

void ExtensionsWatcher::OnToolbarActionsModelShutdown() {
  model_observation_.Reset();
  icon_factories_.clear();
}

void ExtensionsWatcher::OnExtensionActionUpdated(
    extensions::ExtensionAction* extension_action,
    content::WebContents* web_contents,
    content::BrowserContext* browser_context) {
  if (browser_context == profile_.get()) {
    Changed();
  }
}

void ExtensionsWatcher::OnShuttingDown() {
  dispatcher_observation_.Reset();
}

void ExtensionsWatcher::OnIconUpdated() {
  Changed();
}

// Badges can change many times in a row: ChordUI hears of them once per turn.
void ExtensionsWatcher::Changed() {
  if (change_pending_) {
    return;
  }
  change_pending_ = true;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<ExtensionsWatcher> watcher) {
                       if (watcher) {
                         watcher->change_pending_ = false;
                         watcher->changed_.Run();
                       }
                     },
                     weak_factory_.GetWeakPtr()));
}

id<ChordExtensionPopup> RunExtension(content::WebContents* contents,
                                     const std::string& id) {
  Profile* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
  const extensions::Extension* extension =
      extensions::ExtensionRegistry::Get(profile)->enabled_extensions().GetByID(
          id);
  extensions::ExtensionAction* action =
      extension ? extensions::ExtensionActionManager::Get(profile)
                      ->GetExtensionAction(*extension)
                : nullptr;
  auto* runner = extensions::ExtensionActionRunner::GetForWebContents(contents);
  tabs::TabInterface* tab = tabs::TabInterface::MaybeGetFromContents(contents);
  BrowserWindowInterface* browser =
      tab ? tab->GetBrowserWindowInterface() : nullptr;
  if (!action || !runner || !browser) {
    return nil;
  }
  // Like a click on its button: grants the extension the page (activeTab), fires
  // action.onClicked, or asks for its popup.
  if (runner->RunAction(extension, /*grant_tab_permissions=*/true) !=
      extensions::ExtensionAction::ShowAction::kShowPopup) {
    return nil;
  }
  GURL url = action->GetPopupUrl(extensions::ExtensionTabUtil::GetTabId(contents));
  std::unique_ptr<extensions::ExtensionViewHost> host =
      extensions::ExtensionViewHostFactory::CreatePopupHost(*extension, url,
                                                            browser);
  if (!host) {
    return nil;
  }
  return [[ChordExtensionPopupImpl alloc] initWithHost:std::move(host)];
}

}  // namespace chord
