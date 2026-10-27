// Copyright 2026 The Chord Authors

#ifndef CHORD_BROWSER_CHORD_PASSWORD_PROMPT_H_
#define CHORD_BROWSER_CHORD_PASSWORD_PROMPT_H_

namespace content {
class WebContents;
}

namespace chord {

// chrome/browser/ui/passwords/manage_passwords_ui_controller.cc: the password
// manager wants its bubble on the page ("Save password?", "Update password?").
// Chromium's bubble hangs from Chrome's toolbar, which Chord's windows do not have:
// ChordUI asks instead, like a site's permission. Returns false when Chord does not
// show this one, which leaves it to Chromium.
bool ShowPasswordBubble(content::WebContents* web_contents);

// The password manager takes its bubble back (another page, the question changed).
void HidePasswordBubble(content::WebContents* web_contents);

}  // namespace chord

#endif  // CHORD_BROWSER_CHORD_PASSWORD_PROMPT_H_
