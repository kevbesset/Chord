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

// A native sheet on the page's window: the site, what it asks for, "Autoriser" and
// "Bloquer". Chromium keeps the decision as with its own bubble.
class ChordPermissionPrompt : public permissions::PermissionPrompt {
 public:
  ChordPermissionPrompt(Delegate* delegate, NSWindow* window)
      : delegate_(delegate), window_(window) {
    NSMutableArray<NSString*>* asks = [NSMutableArray array];
    for (const auto& request : delegate->Requests()) {
      NSString* text =
          base::SysUTF16ToNSString(request->GetMessageTextFragment());
      if (text.length && ![asks containsObject:text]) {
        [asks addObject:text];
      }
    }
    NSString* site =
        base::SysUTF8ToNSString(delegate->GetRequestingOrigin().host());

    alert_ = [[NSAlert alloc] init];
    alert_.messageText =
        [NSString stringWithFormat:@"%@ demande l'autorisation", site];
    alert_.informativeText = [@"• " stringByAppendingString:[asks
                                  componentsJoinedByString:@"\n• "]];
    [alert_ addButtonWithTitle:@"Autoriser"];
    NSButton* block = [alert_ addButtonWithTitle:@"Bloquer"];
    block.keyEquivalent = @"\e";

    base::WeakPtr<ChordPermissionPrompt> weak = weak_factory_.GetWeakPtr();
    [alert_ beginSheetModalForWindow:window
                   completionHandler:^(NSModalResponse response) {
                     if (ChordPermissionPrompt* prompt = weak.get()) {
                       prompt->Answer(response);
                     }
                   }];
  }

  ~ChordPermissionPrompt() override {
    // Gone before an answer (the tab was switched or closed): take the sheet away
    // without deciding anything.
    weak_factory_.InvalidateWeakPtrs();
    if (NSWindow* window = window_; window && alert_.window.sheetParent) {
      [window endSheet:alert_.window returnCode:NSModalResponseAbort];
    }
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
  void Answer(NSModalResponse response) {
    Delegate* delegate = delegate_;
    if (response == NSAlertFirstButtonReturn) {
      delegate->Accept(PromptOptions(std::monostate()));
    } else if (response == NSAlertSecondButtonReturn) {
      delegate->Deny(PromptOptions(std::monostate()));
    } else {
      delegate->Dismiss(PromptOptions(std::monostate()));
    }
  }

  const raw_ptr<Delegate> delegate_;
  NSWindow* __weak window_;
  NSAlert* alert_;
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
  NSWindow* window = web_contents->GetNativeView().GetNativeNSView().window;
  if (!window) {
    return nullptr;
  }
  return std::make_unique<ChordPermissionPrompt>(delegate, window);
}

}  // namespace chord
