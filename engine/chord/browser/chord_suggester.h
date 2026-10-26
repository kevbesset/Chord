// Copyright 2026 The Chord Authors

#ifndef CHORD_BROWSER_CHORD_SUGGESTER_H_
#define CHORD_BROWSER_CHORD_SUGGESTER_H_

#import <Foundation/Foundation.h>

#include <memory>
#include <string>

#include "base/memory/raw_ptr.h"
#include "components/omnibox/browser/autocomplete_controller.h"

class Profile;

namespace chord {

// History and bookmark suggestions for what is typed in ChordUI's command bar, like
// Chrome's omnibox and Arc's command bar: from one profile's own history only, so
// that Spaces on different profiles never see each other's pages.
class Suggester : public AutocompleteController::Observer {
 public:
  // Each suggestion: "url", "title", and "isTopHit" ("1" when it completes what is
  // typed, like the omnibox's inline completion, else "0").
  using Completion = void (^)(NSArray<NSDictionary<NSString*, NSString*>*>*);

  explicit Suggester(Profile* profile);
  ~Suggester() override;

  // Calls `completion` each time the suggestions for `text` change (some come
  // later than others), until the next Start().
  void Start(const std::u16string& text, Completion completion);

  // AutocompleteController::Observer:
  void OnResultChanged(AutocompleteController* controller,
                       bool default_match_changed) override;

 private:
  raw_ptr<Profile> profile_;
  std::unique_ptr<AutocompleteController> controller_;
  Completion completion_;
};

}  // namespace chord

#endif  // CHORD_BROWSER_CHORD_SUGGESTER_H_
