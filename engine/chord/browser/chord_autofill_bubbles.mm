// Copyright 2026 The Chord Authors

#import "chord/browser/chord_autofill_bubbles.h"

#import <AppKit/AppKit.h>

#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/location.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chord/browser/chord_engine.h"
#import "chord/browser/chord_permission_prompt.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/ui/autofill/address_bubbles_controller.h"
#include "chrome/browser/ui/autofill/autofill_ai/autofill_ai_import_data_controller.h"
#include "chrome/browser/ui/autofill/autofill_bubble_base.h"
#include "chrome/browser/ui/autofill/payments/filled_card_information_bubble_controller.h"
#include "chrome/browser/ui/autofill/payments/iban_bubble_controller.h"
#include "chrome/browser/ui/autofill/payments/mandatory_reauth_bubble_controller.h"
#include "chrome/browser/ui/autofill/payments/offer_notification_bubble_controller.h"
#include "chrome/browser/ui/autofill/payments/omnibox_autofill_bubble_controller.h"
#include "chrome/browser/ui/autofill/payments/payments_churned_users_bubble_controller.h"
#include "chrome/browser/ui/autofill/payments/save_card_bubble_controller.h"
#include "chrome/browser/ui/autofill/payments/save_card_ui.h"
#include "chrome/browser/ui/autofill/payments/save_iban_ui.h"
#include "chrome/browser/ui/autofill/payments/wallet_reminder_notice_bubble_controller.h"
#include "chrome/browser/ui/autofill/save_address_bubble_controller.h"
#include "chrome/browser/ui/autofill/update_address_bubble_controller.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "components/autofill/core/browser/data_model/addresses/autofill_profile.h"
#include "components/autofill/core/browser/data_model/addresses/autofill_profile_comparator.h"
#include "components/autofill/core/browser/data_model/payments/credit_card.h"
#include "components/autofill/core/browser/data_model/payments/iban.h"
#include "components/autofill/core/browser/payments/payments_autofill_client.h"
#include "components/autofill/core/browser/foundations/autofill_client.h"
#include "components/autofill/core/browser/ui/addresses/autofill_address_util.h"
#include "components/autofill/core/browser/ui/payments/payments_ui_closed_reasons.h"
#include "components/autofill/core/browser/ui/payments/virtual_card_enroll_bubble_controller.h"
#include "content/public/browser/web_contents.h"

namespace chord {
namespace {

using autofill::AutofillBubbleBase;
using autofill::AutofillProfile;
using autofill::PaymentsUiClosedReason;
using autofill::SaveAddressBubbleController;
using autofill::UpdateAddressBubbleController;
using Decision = autofill::AutofillClient::AddressPromptUserDecision;

// A bubble Chord does not show. Right after it opens, its controller is told it
// closed unseen (Chromium's queue of bubbles waits for that), unless the controller
// takes it back first: it does before it goes, so `close` never outlives it.
class UnshownBubble : public AutofillBubbleBase {
 public:
  static AutofillBubbleBase* Show(base::OnceClosure close) {
    auto* bubble = new UnshownBubble(std::move(close));
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&UnshownBubble::Close,
                                  bubble->weak_factory_.GetWeakPtr()));
    return bubble;
  }

  // AutofillBubbleBase:
  void Hide() override { Finish(); }
  bool IsMouseHovered() const override { return false; }

 private:
  explicit UnshownBubble(base::OnceClosure close) : close_(std::move(close)) {}

  void Close() {
    base::OnceClosure close = std::move(close_);
    Finish();
    std::move(close).Run();
  }

  // Goes once the controller is done with it (it may still call Hide()).
  void Finish() {
    if (finished_) {
      return;
    }
    finished_ = true;
    weak_factory_.InvalidateWeakPtrs();
    base::SequencedTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE, this);
  }

  base::OnceClosure close_;
  bool finished_ = false;
  base::WeakPtrFactory<UnshownBubble> weak_factory_{this};
};

template <typename Controller>
AutofillBubbleBase* ShowUnshown(Controller* controller) {
  return UnshownBubble::Show(
      base::BindOnce(&Controller::OnBubbleClosed, base::Unretained(controller),
                     PaymentsUiClosedReason::kNotInteracted));
}

const AutofillProfile& ProfileToSave(SaveAddressBubbleController& controller) {
  return controller.GetAutofillProfile();
}
const AutofillProfile& ProfileToSave(UpdateAddressBubbleController& controller) {
  return controller.GetProfileToSave();
}

Decision DeclineDecision(SaveAddressBubbleController& controller) {
  return controller.GetCancelCallbackValue();
}
Decision DeclineDecision(UpdateAddressBubbleController& controller) {
  return Decision::kDeclined;
}

// What the question says, from the controller, in Chromium's words.
struct AddressQuestion {
  std::u16string title;
  std::u16string detail;
  std::u16string accept;
  std::u16string decline;
};

// "Save address?" or "Update address?", asked through ChordUI. It plays the part of
// Chromium's bubble view: it owns the controller, tells it the answer, then that the
// bubble closed.
template <typename Controller>
class AddressPrompt : public AutofillBubbleBase {
 public:
  static AutofillBubbleBase* Show(content::WebContents* web_contents,
                                  std::unique_ptr<Controller> controller,
                                  const AddressQuestion& question) {
    auto* prompt = new AddressPrompt(std::move(controller));
    prompt->Ask(web_contents, question);
    return prompt;
  }

  // AutofillBubbleBase:
  void Hide() override { Close(); }
  bool IsMouseHovered() const override { return false; }

 private:
  explicit AddressPrompt(std::unique_ptr<Controller> controller)
      : controller_(std::move(controller)) {}

  void Ask(content::WebContents* web_contents,
           const AddressQuestion& question) {
    NSString* site =
        base::SysUTF8ToNSString(web_contents->GetLastCommittedURL().host());
    base::WeakPtr<AddressPrompt> weak = weak_factory_.GetWeakPtr();
    ChordPermissionRequestImpl* request = [[ChordPermissionRequestImpl alloc]
        initWithSite:site
                asks:@[]
              symbol:@"house"
              answer:^(NSInteger answer) {
                if (AddressPrompt* prompt = weak.get()) {
                  prompt->Answer(static_cast<chord::Answer>(answer));
                }
              }];
    request.question = base::SysUTF16ToNSString(question.title);
    request.detail = base::SysUTF16ToNSString(question.detail);
    request.allowTitle = base::SysUTF16ToNSString(question.accept);
    request.blockTitle = @"";
    request.dismissTitle = base::SysUTF16ToNSString(question.decline);
    request_ = request;
    if (!RequestPermission(web_contents, request)) {
      // ChordUI does not know the page: the bubble closes unseen, once the
      // controller has it.
      request_ = nil;
      base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, base::BindOnce(&AddressPrompt::Close, weak));
    }
  }

  // The decision may make the controller take its bubble back (Hide()): `this`
  // stays until the next task, and closes once.
  void Answer(chord::Answer answer) {
    request_ = nil;
    if (answer == kAllow) {
      controller_->OnUserDecision(Decision::kAccepted,
                                  ProfileToSave(*controller_));
    } else {
      controller_->OnUserDecision(DeclineDecision(*controller_), std::nullopt);
    }
    Close();
  }

  void Close() {
    if (closed_) {
      return;
    }
    closed_ = true;
    weak_factory_.InvalidateWeakPtrs();
    ChordPermissionRequestImpl* request = request_;
    request_ = nil;
    [request cancel];
    controller_->OnBubbleClosed();
    base::SequencedTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE, this);
  }

  std::unique_ptr<Controller> controller_;
  ChordPermissionRequestImpl* request_;
  bool closed_ = false;
  base::WeakPtrFactory<AddressPrompt> weak_factory_{this};
};

// "Save card?" or "Save IBAN?", kept on this Mac (Chord has no Google Payments),
// asked through ChordUI like an address. Its controller belongs to the page and
// outlives it: it takes the bubble back (Hide()) before it goes.
class PaymentPrompt : public AutofillBubbleBase {
 public:
  struct Question {
    std::u16string title;
    std::u16string detail;
    std::u16string accept;
    std::u16string decline;
  };

  static AutofillBubbleBase* Show(
      content::WebContents* web_contents,
      const Question& question,
      base::OnceClosure accept,
      base::OnceCallback<void(PaymentsUiClosedReason)> closed) {
    auto* prompt = new PaymentPrompt(std::move(accept), std::move(closed));
    prompt->Ask(web_contents, question);
    return prompt;
  }

  // AutofillBubbleBase:
  void Hide() override { Close(PaymentsUiClosedReason::kNotInteracted); }
  bool IsMouseHovered() const override { return false; }

 private:
  PaymentPrompt(base::OnceClosure accept,
                base::OnceCallback<void(PaymentsUiClosedReason)> closed)
      : accept_(std::move(accept)), closed_(std::move(closed)) {}

  void Ask(content::WebContents* web_contents, const Question& question) {
    NSString* site =
        base::SysUTF8ToNSString(web_contents->GetLastCommittedURL().host());
    base::WeakPtr<PaymentPrompt> weak = weak_factory_.GetWeakPtr();
    ChordPermissionRequestImpl* request = [[ChordPermissionRequestImpl alloc]
        initWithSite:site
                asks:@[]
              symbol:@"creditcard"
              answer:^(NSInteger answer) {
                if (PaymentPrompt* prompt = weak.get()) {
                  prompt->Answer(static_cast<chord::Answer>(answer));
                }
              }];
    request.question = base::SysUTF16ToNSString(question.title);
    request.detail = base::SysUTF16ToNSString(question.detail);
    request.allowTitle = base::SysUTF16ToNSString(question.accept);
    request.blockTitle = @"";
    request.dismissTitle = base::SysUTF16ToNSString(question.decline);
    request_ = request;
    if (!RequestPermission(web_contents, request)) {
      request_ = nil;
      base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, base::BindOnce(&PaymentPrompt::Close, weak,
                                    PaymentsUiClosedReason::kNotInteracted));
    }
  }

  void Answer(chord::Answer answer) {
    request_ = nil;
    if (answer == kAllow) {
      std::move(accept_).Run();
      Close(PaymentsUiClosedReason::kAccepted);
    } else {
      Close(PaymentsUiClosedReason::kCancelled);
    }
  }

  void Close(PaymentsUiClosedReason reason) {
    if (finished_) {
      return;
    }
    finished_ = true;
    weak_factory_.InvalidateWeakPtrs();
    ChordPermissionRequestImpl* request = request_;
    request_ = nil;
    [request cancel];
    std::move(closed_).Run(reason);
    base::SequencedTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE, this);
  }

  base::OnceClosure accept_;
  base::OnceCallback<void(PaymentsUiClosedReason)> closed_;
  ChordPermissionRequestImpl* request_;
  bool finished_ = false;
  base::WeakPtrFactory<PaymentPrompt> weak_factory_{this};
};

// The detail line holds one line: the summary's lines, comma-separated.
std::u16string OneLine(const std::u16string& text) {
  std::u16string line;
  base::ReplaceChars(text, u"\n", u", ", &line);
  return line;
}

}  // namespace

AutofillBubbles::AutofillBubbles(BrowserWindowInterface* browser)
    : scoped_user_data_(browser->GetUnownedUserDataHost(), *this) {}

AutofillBubbles::~AutofillBubbles() = default;

AutofillBubbleBase* AutofillBubbles::ShowSaveAddressProfileBubble(
    content::WebContents* web_contents,
    std::unique_ptr<SaveAddressBubbleController> controller,
    bool is_user_gesture) {
  AddressQuestion question{
      .title = controller->GetWindowTitle(),
      .detail = OneLine(controller->GetAddressSummary()),
      .accept = controller->GetOkButtonLabel(),
      .decline = controller->GetNegativeButtonLabel(),
  };
  return AddressPrompt<SaveAddressBubbleController>::Show(
      web_contents, std::move(controller), question);
}

AutofillBubbleBase* AutofillBubbles::ShowUpdateAddressProfileBubble(
    content::WebContents* web_contents,
    std::unique_ptr<UpdateAddressBubbleController> controller,
    bool is_user_gesture) {
  // As in UpdateAddressProfileView: the new values, and whether the saved address
  // had none of them (the wording then says "add").
  std::vector<autofill::ProfileValueDifference> differences =
      autofill::GetProfileDifferenceForUi(
          controller->GetProfileToSave(), controller->GetOriginalProfile(),
          g_browser_process->GetApplicationLocale());
  bool has_empty_original_values = true;
  std::vector<std::u16string> new_values;
  for (const autofill::ProfileValueDifference& difference : differences) {
    if (!difference.second_value.empty()) {
      has_empty_original_values = false;
    }
    if (!difference.first_value.empty()) {
      new_values.push_back(OneLine(difference.first_value));
    }
  }
  AddressQuestion question{
      .title = controller->GetWindowTitle(has_empty_original_values),
      .detail = base::JoinString(new_values, u", "),
      .accept = controller->GetPositiveButtonText(has_empty_original_values),
      .decline = controller->GetNegativeButtonText(has_empty_original_values),
  };
  return AddressPrompt<UpdateAddressBubbleController>::Show(
      web_contents, std::move(controller), question);
}

#if BUILDFLAG(ENABLE_DICE_SUPPORT)
AutofillBubbleBase* AutofillBubbles::ShowAddressSignInPromo(
    content::WebContents* web_contents,
    const AutofillProfile& autofill_profile) {
  // Like AddressSignInPromoView, which tells the page's controller it closed.
  return UnshownBubble::Show(base::BindOnce(
      [](base::WeakPtr<content::WebContents> contents) {
        if (!contents) {
          return;
        }
        if (auto* controller =
                autofill::AddressBubblesController::FromWebContents(
                    contents.get())) {
          controller->OnBubbleClosed();
        }
      },
      web_contents->GetWeakPtr()));
}
#endif

AutofillBubbleBase* AutofillBubbles::ShowSaveCreditCardBubble(
    content::WebContents* web_contents,
    autofill::SaveCardBubbleController* controller,
    bool is_user_gesture) {
  autofill::PaymentsBubbleType type = controller->GetPaymentsBubbleType();
  // Uploading to Google Payments, or asking for a missing name or date: not in
  // Chord.
  if ((type != autofill::PaymentsBubbleType::kLocalSave &&
       type != autofill::PaymentsBubbleType::kLocalCvcSave) ||
      controller->ShouldRequestNameFromUser() ||
      controller->ShouldRequestExpirationDateFromUser()) {
    return ShowUnshown(controller);
  }
  PaymentPrompt::Question question{
      .title = controller->GetWindowTitle(),
      .detail = controller->GetCard().CardNameAndLastFourDigits(),
      .accept = controller->GetAcceptButtonText(),
      .decline = controller->GetDeclineButtonText(),
  };
  return PaymentPrompt::Show(
      web_contents, question,
      base::BindOnce(&autofill::SaveCardBubbleController::OnSaveButton,
                     base::Unretained(controller),
                     autofill::payments::PaymentsAutofillClient::
                         UserProvidedCardDetails()),
      base::BindOnce(&autofill::SaveCardBubbleController::OnBubbleClosed,
                     base::Unretained(controller)));
}

AutofillBubbleBase* AutofillBubbles::ShowSaveCardConfirmationBubble(
    content::WebContents* web_contents,
    autofill::SaveCardBubbleController* controller) {
  return ShowUnshown(controller);
}

AutofillBubbleBase* AutofillBubbles::ShowIbanBubble(
    content::WebContents* web_contents,
    autofill::IbanBubbleController* controller,
    bool is_user_gesture,
    autofill::IbanBubbleType bubble_type) {
  if (bubble_type != autofill::IbanBubbleType::kLocalSave) {
    return ShowUnshown(controller);
  }
  PaymentPrompt::Question question{
      .title = controller->GetWindowTitle(),
      .detail = controller->GetIban().GetIdentifierStringForAutofillDisplay(),
      .accept = controller->GetAcceptButtonText(),
      .decline = controller->GetDeclineButtonText(),
  };
  return PaymentPrompt::Show(
      web_contents, question,
      base::BindOnce(&autofill::IbanBubbleController::OnAcceptButton,
                     base::Unretained(controller), std::u16string_view()),
      base::BindOnce(&autofill::IbanBubbleController::OnBubbleClosed,
                     base::Unretained(controller)));
}

AutofillBubbleBase* AutofillBubbles::ShowSaveIbanConfirmationBubble(
    content::WebContents* web_contents,
    autofill::IbanBubbleController* controller) {
  return ShowUnshown(controller);
}

AutofillBubbleBase* AutofillBubbles::ShowOfferNotificationBubble(
    content::WebContents* web_contents,
    autofill::OfferNotificationBubbleController* controller,
    bool is_user_gesture) {
  return ShowUnshown(controller);
}

AutofillBubbleBase* AutofillBubbles::ShowFilledCardInformationBubble(
    content::WebContents* web_contents,
    autofill::FilledCardInformationBubbleController* controller,
    bool is_user_gesture) {
  return ShowUnshown(controller);
}

AutofillBubbleBase* AutofillBubbles::ShowVirtualCardEnrollBubble(
    content::WebContents* web_contents,
    autofill::VirtualCardEnrollBubbleController* controller,
    bool is_user_gesture) {
  return ShowUnshown(controller);
}

AutofillBubbleBase* AutofillBubbles::ShowVirtualCardEnrollConfirmationBubble(
    content::WebContents* web_contents,
    autofill::VirtualCardEnrollBubbleController* controller) {
  return ShowUnshown(controller);
}

AutofillBubbleBase* AutofillBubbles::ShowMandatoryReauthBubble(
    content::WebContents* web_contents,
    autofill::MandatoryReauthBubbleController* controller,
    bool is_user_gesture,
    autofill::MandatoryReauthBubbleType bubble_type) {
  return ShowUnshown(controller);
}

AutofillBubbleBase* AutofillBubbles::ShowOmniboxAutofillBubble(
    content::WebContents* web_contents,
    autofill::OmniboxAutofillBubbleController* controller) {
  return ShowUnshown(controller);
}

AutofillBubbleBase* AutofillBubbles::ShowPaymentsChurnedUsersBubble(
    content::WebContents* web_contents,
    autofill::PaymentsChurnedUsersBubbleController* controller,
    bool is_user_gesture) {
  return ShowUnshown(controller);
}

AutofillBubbleBase* AutofillBubbles::ShowPaymentsChurnedUsersConfirmationBubble(
    content::WebContents* web_contents,
    autofill::PaymentsChurnedUsersBubbleController* controller) {
  return ShowUnshown(controller);
}

AutofillBubbleBase* AutofillBubbles::ShowWalletReminderNoticeBubble(
    content::WebContents* web_contents,
    autofill::WalletReminderNoticeBubbleController* controller,
    bool is_user_gesture) {
  return UnshownBubble::Show(
      base::BindOnce(&autofill::WalletReminderNoticeBubbleController::
                         OnBubbleClosed,
                     base::Unretained(controller)));
}

AutofillBubbleBase* AutofillBubbles::ShowSaveAutofillAiDataBubble(
    content::WebContents* web_contents,
    autofill::AutofillAiImportDataController* controller) {
  return UnshownBubble::Show(base::BindOnce(
      &autofill::AutofillAiImportDataController::OnBubbleClosed,
      base::Unretained(controller),
      autofill::AutofillClient::AutofillAiBubbleResult::kNotInteracted));
}

AutofillBubbleBase* AutofillBubbles::ShowAutofillAiLocalSaveNotification(
    content::WebContents* web_contents,
    autofill::AutofillAiImportDataController* controller) {
  return ShowSaveAutofillAiDataBubble(web_contents, controller);
}

}  // namespace chord
