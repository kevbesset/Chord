// Copyright 2026 The Chord Authors

#ifndef CHORD_BROWSER_CHORD_PERMISSION_PROMPT_H_
#define CHORD_BROWSER_CHORD_PERMISSION_PROMPT_H_

#include <memory>

#include "components/permissions/permission_prompt.h"

#if defined(__OBJC__)
#import "chord/browser/chord_ui.h"

// A question ChordUI shows and answers once: a site's permission request, or one of the
// browser's own (save a password). The answer goes back through `answer`, which does
// nothing once the question is gone.
@interface ChordPermissionRequestImpl : NSObject <ChordPermissionRequest>
- (instancetype)initWithSite:(NSString*)site
                        asks:(NSArray<NSString*>*)asks
                      symbol:(NSString*)symbol
                      answer:(void (^)(NSInteger answer))answer;
// The question went away unanswered: ChordUI takes it down.
- (void)cancel;
@property(nonatomic, copy) NSString* question;
@property(nonatomic, copy) NSString* detail;
@property(nonatomic, copy) NSString* allowTitle;
@property(nonatomic, copy) NSString* blockTitle;
@property(nonatomic, copy) NSString* dismissTitle;
@end
#endif

namespace content {
class WebContents;
}

namespace chord {

// How a question was answered.
enum Answer : long { kAllow, kBlock, kDismiss };

// chrome/browser/ui/views/permissions/permission_prompt_factory.cc: whether the page
// is in a Chord window, whose permission prompts are Chord's. Chromium's bubble needs
// its Views window to hang from (it crashed without one).
bool ShowsPermissionPrompts(content::WebContents* web_contents);

// The site's question, shown by ChordUI like Arc's: what it asks for (notifications,
// location, camera…), "Pas maintenant" and "Autoriser". nullptr when ChordUI does not
// know the page, which leaves the request unanswered.
std::unique_ptr<permissions::PermissionPrompt> CreatePermissionPrompt(
    content::WebContents* web_contents,
    permissions::PermissionPrompt::Delegate* delegate);

}  // namespace chord

#endif  // CHORD_BROWSER_CHORD_PERMISSION_PROMPT_H_
