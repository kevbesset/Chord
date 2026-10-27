// Copyright 2026 The Chord Authors
// Links clicked in Chord's pages that ChordUI opens elsewhere, like Arc: ⇧-click in a
// Peek, and a link leaving the site of a pinned tab or a favorite in a Peek too, so
// that the tab stays on its page.

#import <AppKit/AppKit.h>

#include <memory>

#include "chord/browser/chord_hooks.h"
#import "chord/browser/chord_engine.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/navigation_throttle.h"
#include "content/public/browser/navigation_throttle_registry.h"
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/web_contents.h"
#include "net/base/apple/url_conversions.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"

namespace chord {
namespace {

// Asks ChordUI whether the page follows a link it opens; false when ChordUI opened
// it elsewhere (a Peek).
bool FollowsLink(content::WebContents* contents,
                 const GURL& url,
                 NSEventModifierFlags modifiers) {
  id<ChordWebPage> page = PageForContents(contents);
  id<ChordWebPageDelegate> delegate = page.delegate;
  if (!page || !url.SchemeIsHTTPOrHTTPS() ||
      ![delegate respondsToSelector:@selector(page:shouldFollowLinkTo:modifiers:)]) {
    return true;
  }
  return [delegate page:page
      shouldFollowLinkTo:net::NSURLWithGURL(url)
               modifiers:modifiers];
}

// A link clicked in the page itself, for ChordUI to keep a pinned tab on its site.
class LinkThrottle : public content::NavigationThrottle {
 public:
  using content::NavigationThrottle::NavigationThrottle;

  ThrottleCheckResult WillStartRequest() override {
    content::NavigationHandle* handle = navigation_handle();
    if (!handle->IsInPrimaryMainFrame() || !handle->IsRendererInitiated() ||
        !handle->HasUserGesture() || handle->IsSameDocument() ||
        !ui::PageTransitionCoreTypeIs(handle->GetPageTransition(),
                                      ui::PAGE_TRANSITION_LINK)) {
      return PROCEED;
    }
    return FollowsLink(handle->GetWebContents(), handle->GetURL(), 0)
               ? PROCEED
               : CANCEL_AND_IGNORE;
  }

  const char* GetNameForLogging() override { return "ChordLinkThrottle"; }
};

}  // namespace

void AddNavigationThrottles(content::NavigationThrottleRegistry& registry) {
  if (!IsEnabled() ||
      !PageForContents(registry.GetNavigationHandle().GetWebContents())) {
    return;
  }
  registry.AddThrottle(std::make_unique<LinkThrottle>(registry));
}

// ⇧-click asks for a new window: ChordUI opens a Peek instead. ⌘-click (a background
// tab) and window.open stay Chromium's, whose new tabs ChordUI adopts.
bool HandleOpenURL(content::WebContents* source,
                   const content::OpenURLParams& params) {
  if (!IsEnabled() || !source || !params.user_gesture ||
      !params.is_renderer_initiated ||
      params.disposition != WindowOpenDisposition::NEW_WINDOW) {
    return false;
  }
  return !FollowsLink(source, params.url, NSEventModifierFlagShift);
}

}  // namespace chord
