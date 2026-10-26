// Copyright 2026 The Chord Authors

#include "chord/browser/chord_suggester.h"

#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/autocomplete/chrome_autocomplete_provider_client.h"
#include "chrome/browser/autocomplete/chrome_autocomplete_scheme_classifier.h"
#include "chrome/browser/profiles/profile.h"
#include "components/omnibox/browser/autocomplete_controller_config.h"
#include "components/omnibox/browser/autocomplete_enums.h"
#include "components/omnibox/browser/autocomplete_input.h"
#include "components/omnibox/browser/autocomplete_match.h"
#include "components/omnibox/browser/autocomplete_provider.h"
#include "components/omnibox/browser/autocomplete_result.h"
#include "third_party/metrics_proto/omnibox_event.pb.h"

namespace chord {

Suggester::Suggester(Profile* profile)
    : profile_(profile),
      controller_(std::make_unique<AutocompleteController>(
          std::make_unique<ChromeAutocompleteProviderClient>(profile),
          // Pages only: ChordUI makes its own search row, with its own engine.
          AutocompleteControllerConfig{
              .provider_types = AutocompleteProvider::TYPE_HISTORY_QUICK |
                                AutocompleteProvider::TYPE_HISTORY_URL |
                                AutocompleteProvider::TYPE_BOOKMARK |
                                AutocompleteProvider::TYPE_SHORTCUTS})) {
  controller_->AddObserver(this);
}

Suggester::~Suggester() {
  controller_->RemoveObserver(this);
}

void Suggester::Start(const std::u16string& text, Completion completion) {
  completion_ = completion;
  if (text.empty()) {
    controller_->Stop(AutocompleteStopReason::kClobbered);
    completion(@[]);
    return;
  }
  controller_->Start(AutocompleteInput(text,
                                       metrics::OmniboxEventProto::OTHER,
                                       ChromeAutocompleteSchemeClassifier(profile_)));
}

void Suggester::OnResultChanged(AutocompleteController* controller,
                                bool default_match_changed) {
  NSMutableArray<NSDictionary<NSString*, NSString*>*>* suggestions =
      [NSMutableArray array];
  for (const AutocompleteMatch& match : controller->result()) {
    if (!match.destination_url.is_valid() ||
        AutocompleteMatch::IsSearchType(match.type) ||
        match.type == AutocompleteMatchType::URL_WHAT_YOU_TYPED) {
      continue;
    }
    bool top_hit = match.allowed_to_be_default_match &&
                   !match.inline_autocompletion.empty();
    [suggestions addObject:@{
      @"url" : base::SysUTF8ToNSString(match.destination_url.spec()),
      @"title" : base::SysUTF16ToNSString(match.description),
      @"isTopHit" : top_hit ? @"1" : @"0",
    }];
  }
  if (completion_) {
    completion_(suggestions);
  }
}

}  // namespace chord
