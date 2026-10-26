// Copyright 2026 The Chord Authors

#ifndef CHORD_BROWSER_CHORD_PERMISSION_PROMPT_H_
#define CHORD_BROWSER_CHORD_PERMISSION_PROMPT_H_

#include <memory>

#include "components/permissions/permission_prompt.h"

namespace content {
class WebContents;
}

namespace chord {

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
