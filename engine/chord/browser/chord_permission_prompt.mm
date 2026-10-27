// Copyright 2026 The Chord Authors

#import "chord/browser/chord_permission_prompt.h"

#import <AppKit/AppKit.h>

#include <variant>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "chord/browser/chord_engine.h"
#include "chord/browser/chord_hooks.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "components/permissions/features.h"
#include "components/permissions/permission_request.h"
#include "components/permissions/permission_uma_constants.h"
#include "components/permissions/resolvers/permission_prompt_options.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"

namespace chord {
namespace {

NSString* SymbolFor(permissions::RequestType type) {
  switch (type) {
    case permissions::RequestType::kNotifications:
      return @"bell";
    case permissions::RequestType::kGeolocation:
      return @"location";
    case permissions::RequestType::kCameraStream:
    case permissions::RequestType::kCameraPanTiltZoom:
      return @"camera";
    case permissions::RequestType::kMicStream:
      return @"mic";
    case permissions::RequestType::kClipboard:
      return @"doc.on.clipboard";
    case permissions::RequestType::kLocalNetwork:
      return @"network";
    default:
      return @"lock.shield";
  }
}

}  // namespace
}  // namespace chord


@implementation ChordPermissionRequestImpl {
  void (^_answer)(NSInteger);
}

@synthesize site = _site;
@synthesize asks = _asks;
@synthesize symbol = _symbol;
@synthesize onCancel = _onCancel;
@synthesize question = _question;
@synthesize detail = _detail;
@synthesize allowTitle = _allowTitle;
@synthesize blockTitle = _blockTitle;
@synthesize dismissTitle = _dismissTitle;

- (instancetype)initWithSite:(NSString*)site
                        asks:(NSArray<NSString*>*)asks
                      symbol:(NSString*)symbol
                      answer:(void (^)(NSInteger answer))answer {
  if ((self = [super init])) {
    _site = [site copy];
    _asks = [asks copy];
    _symbol = [symbol copy];
    _answer = [answer copy];
  }
  return self;
}

- (void)allow {
  _answer(chord::kAllow);
}

- (void)block {
  _answer(chord::kBlock);
}

- (void)dismiss {
  _answer(chord::kDismiss);
}

- (void)cancel {
  if (_onCancel) {
    _onCancel();
  }
}

@end

namespace chord {
namespace {

// The question goes to ChordUI, which shows it like Arc's, from the site controls of
// the window showing the page: the page stays usable while it is up. Chromium keeps
// the decision when there is one.
class ChordPermissionPrompt : public permissions::PermissionPrompt {
 public:
  explicit ChordPermissionPrompt(Delegate* delegate) : delegate_(delegate) {
    NSMutableArray<NSString*>* asks = [NSMutableArray array];
    NSString* symbol = @"lock.shield";
    for (const auto& request : delegate->Requests()) {
      NSString* text =
          base::SysUTF16ToNSString(request->GetMessageTextFragment());
      if (text.length && ![asks containsObject:text]) {
        [asks addObject:text];
      }
      if (asks.count == 1) {
        symbol = SymbolFor(request->request_type());
      }
    }
    NSString* site =
        base::SysUTF8ToNSString(delegate->GetRequestingOrigin().host());
    base::WeakPtr<ChordPermissionPrompt> weak = weak_factory_.GetWeakPtr();
    request_ = [[ChordPermissionRequestImpl alloc]
        initWithSite:site
                asks:asks
              symbol:symbol
              answer:^(NSInteger answer) {
                if (ChordPermissionPrompt* prompt = weak.get()) {
                  prompt->Answer(static_cast<chord::Answer>(answer));
                }
              }];
  }

  ~ChordPermissionPrompt() override {
    // Gone before an answer (another tab, the tab closed): the question goes without
    // deciding anything.
    weak_factory_.InvalidateWeakPtrs();
    if (!answered_) {
      [request_ cancel];
    }
  }

  bool Show(content::WebContents* web_contents) {
    return RequestPermission(web_contents, request_);
  }

  // permissions::PermissionPrompt:
  bool UpdateAnchor() override { return true; }
  TabSwitchingBehavior GetTabSwitchingBehavior() override {
    return kDestroyPromptButKeepRequestPending;
  }
  permissions::PermissionPromptDisposition GetPromptDisposition()
      const override {
    return permissions::PermissionPromptDisposition::ANCHORED_BUBBLE;
  }
  bool IsAskPrompt() const override { return true; }
  std::optional<gfx::Rect> GetViewBoundsInScreen() const override {
    return std::nullopt;
  }
  std::vector<permissions::ElementAnchoredBubbleVariant> GetPromptVariants()
      const override {
    return {};
  }
  std::optional<permissions::feature_params::PermissionElementPromptPosition>
  GetPromptPosition() const override {
    return std::nullopt;
  }

 private:
  // The delegate may destroy this prompt while handling the answer: nothing of it
  // is used afterwards.
  void Answer(chord::Answer answer) {
    if (answered_) {
      return;
    }
    answered_ = true;
    Delegate* delegate = delegate_;
    switch (answer) {
      case kAllow:
        delegate->Accept(PromptOptions(std::monostate()));
        break;
      case kBlock:
        delegate->Deny(PromptOptions(std::monostate()));
        break;
      case kDismiss:
        delegate->Dismiss(PromptOptions(std::monostate()));
        break;
    }
  }

  const raw_ptr<Delegate> delegate_;
  ChordPermissionRequestImpl* request_;
  bool answered_ = false;
  base::WeakPtrFactory<ChordPermissionPrompt> weak_factory_{this};
};

}  // namespace

bool ShowsPermissionPrompts(content::WebContents* web_contents) {
  if (!IsEnabled() || !web_contents) {
    return false;
  }
  tabs::TabInterface* tab =
      tabs::TabInterface::MaybeGetFromContents(web_contents);
  BrowserWindowInterface* browser =
      tab ? tab->GetBrowserWindowInterface() : nullptr;
  return browser &&
         browser->GetType() == BrowserWindowInterface::Type::TYPE_NORMAL;
}

std::unique_ptr<permissions::PermissionPrompt> CreatePermissionPrompt(
    content::WebContents* web_contents,
    permissions::PermissionPrompt::Delegate* delegate) {
  auto prompt = std::make_unique<ChordPermissionPrompt>(delegate);
  if (!prompt->Show(web_contents)) {
    return nullptr;
  }
  return prompt;
}

}  // namespace chord
