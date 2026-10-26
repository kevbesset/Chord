// Copyright 2026 The Chord Authors

#import "chord/browser/chord_permission_prompt.h"

#import <AppKit/AppKit.h>

#include <variant>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
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
      return @"video";
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

// The bubble's content: what the site asks for, then "Bloquer" and "Autoriser".
@interface ChordPermissionViewController : NSViewController
@property(nonatomic, copy) void (^onAnswer)(BOOL allow);
- (instancetype)initWithSite:(NSString*)site
                        asks:(NSArray<NSString*>*)asks
                      symbol:(NSString*)symbol;
@end

@implementation ChordPermissionViewController {
  NSString* _site;
  NSArray<NSString*>* _asks;
  NSString* _symbol;
}

- (instancetype)initWithSite:(NSString*)site
                        asks:(NSArray<NSString*>*)asks
                      symbol:(NSString*)symbol {
  if ((self = [super initWithNibName:nil bundle:nil])) {
    _site = [site copy];
    _asks = [asks copy];
    _symbol = [symbol copy];
  }
  return self;
}

- (void)loadView {
  NSImageView* icon = [NSImageView imageViewWithImage:
      [[NSImage imageWithSystemSymbolName:_symbol accessibilityDescription:nil]
          imageWithSymbolConfiguration:[NSImageSymbolConfiguration
                                           configurationWithPointSize:15
                                                               weight:NSFontWeightMedium]]];
  icon.contentTintColor = NSColor.controlAccentColor;

  NSTextField* site = [NSTextField labelWithString:
      [NSString stringWithFormat:@"%@ souhaite", _site]];
  site.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  NSTextField* asks = [NSTextField wrappingLabelWithString:
      [_asks componentsJoinedByString:@"\n"]];
  asks.font = [NSFont systemFontOfSize:12];
  asks.textColor = NSColor.secondaryLabelColor;
  asks.preferredMaxLayoutWidth = 220;

  NSStackView* texts = [NSStackView stackViewWithViews:@[ site, asks ]];
  texts.orientation = NSUserInterfaceLayoutOrientationVertical;
  texts.alignment = NSLayoutAttributeLeading;
  texts.spacing = 2;
  NSStackView* header = [NSStackView stackViewWithViews:@[ icon, texts ]];
  header.alignment = NSLayoutAttributeTop;
  header.spacing = 10;

  NSButton* block = [NSButton buttonWithTitle:@"Bloquer"
                                       target:self
                                       action:@selector(block:)];
  NSButton* allow = [NSButton buttonWithTitle:@"Autoriser"
                                       target:self
                                       action:@selector(allow:)];
  allow.keyEquivalent = @"\r";
  block.controlSize = allow.controlSize = NSControlSizeSmall;
  NSStackView* buttons = [NSStackView stackViewWithViews:@[ block, allow ]];
  buttons.spacing = 8;

  NSStackView* column = [NSStackView stackViewWithViews:@[ header, buttons ]];
  column.orientation = NSUserInterfaceLayoutOrientationVertical;
  column.alignment = NSLayoutAttributeTrailing;
  column.spacing = 12;
  column.edgeInsets = NSEdgeInsetsMake(14, 14, 12, 14);
  self.view = column;
}

- (void)allow:(id)sender {
  if (self.onAnswer) {
    self.onAnswer(YES);
  }
}

- (void)block:(id)sender {
  if (self.onAnswer) {
    self.onAnswer(NO);
  }
}

@end

namespace chord {
namespace {

// A small bubble at the top of the page, like Arc's: the page stays usable while it
// is up. Clicking elsewhere closes it and leaves the request undecided, as Chrome's
// bubble does; Chromium keeps the decision when there is one.
class ChordPermissionPrompt : public permissions::PermissionPrompt {
 public:
  ChordPermissionPrompt(Delegate* delegate, NSView* page_view)
      : delegate_(delegate) {
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

    ChordPermissionViewController* content =
        [[ChordPermissionViewController alloc] initWithSite:site
                                                       asks:asks
                                                     symbol:symbol];
    base::WeakPtr<ChordPermissionPrompt> weak = weak_factory_.GetWeakPtr();
    content.onAnswer = ^(BOOL allow) {
      if (ChordPermissionPrompt* prompt = weak.get()) {
        prompt->Answer(allow ? kAllow : kBlock);
      }
    };

    popover_ = [[NSPopover alloc] init];
    popover_.contentViewController = content;
    popover_.behavior = NSPopoverBehaviorTransient;
    popover_.animates = YES;
    closed_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:NSPopoverDidCloseNotification
                    object:popover_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (ChordPermissionPrompt* prompt = weak.get()) {
                    prompt->Answer(kDismiss);
                  }
                }];

    // Just under the top edge of the page, near its left corner (where Arc's sits,
    // under the address).
    NSRect bounds = page_view.bounds;
    CGFloat top = page_view.isFlipped ? NSMinY(bounds) : NSMaxY(bounds) - 1;
    [popover_ showRelativeToRect:NSMakeRect(NSMinX(bounds) + 28, top, 1, 1)
                          ofView:page_view
                   preferredEdge:page_view.isFlipped ? NSRectEdgeMaxY
                                                     : NSRectEdgeMinY];
  }

  ~ChordPermissionPrompt() override {
    // Gone before an answer (another tab, the tab closed): the bubble goes without
    // deciding anything.
    weak_factory_.InvalidateWeakPtrs();
    [NSNotificationCenter.defaultCenter removeObserver:closed_observer_];
    [popover_ close];
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
  enum AnswerKind { kAllow, kBlock, kDismiss };

  // The delegate may destroy this prompt while handling the answer: nothing of it
  // is used afterwards.
  void Answer(AnswerKind answer) {
    if (answered_) {
      return;
    }
    answered_ = true;
    Delegate* delegate = delegate_;
    if (answer != kDismiss) {
      [popover_ close];
    }
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
  NSPopover* popover_;
  id closed_observer_;
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
  NSView* page_view = web_contents->GetNativeView().GetNativeNSView();
  if (!page_view.window) {
    return nullptr;
  }
  return std::make_unique<ChordPermissionPrompt>(delegate, page_view);
}

}  // namespace chord
