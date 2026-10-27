// Copyright 2026 The Chord Authors

#import "chord/browser/chord_password_prompt.h"

#import <AppKit/AppKit.h>

#include <memory>
#include <utility>

#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "chord/browser/chord_engine.h"
#import "chord/browser/chord_permission_prompt.h"
#include "chrome/browser/ui/passwords/bubble_controllers/password_bubble_controller_base.h"
#include "chrome/browser/ui/passwords/bubble_controllers/save_update_bubble_controller.h"
#include "chrome/browser/ui/passwords/manage_passwords_ui_controller.h"
#include "chrome/browser/ui/passwords/passwords_model_delegate.h"
#include "chrome/grit/generated_resources.h"
#include "components/password_manager/core/browser/password_form.h"
#include "components/password_manager/core/common/password_manager_ui.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_user_data.h"
#include "ui/base/l10n/l10n_util_mac.h"

namespace chord {
namespace {

// The question of one page, while ChordUI shows it. It plays the part of Chromium's
// bubble view: its SaveUpdateBubbleController tells the password manager the bubble
// is up, and that it went once the controller goes.
class PasswordPrompt : public content::WebContentsUserData<PasswordPrompt> {
 public:
  ~PasswordPrompt() override { Hide(); }

  void Show() {
    Hide();
    controller_ = std::make_unique<SaveUpdateBubbleController>(
        PasswordsModelDelegateFromWebContents(&GetWebContents()),
        PasswordBubbleControllerBase::DisplayReason::kAutomatic);
    bool update = controller_->IsCurrentStateUpdate();
    NSString* site = base::SysUTF8ToNSString(
        GetWebContents().GetLastCommittedURL().host());
    base::WeakPtr<PasswordPrompt> weak = weak_factory_.GetWeakPtr();
    ChordPermissionRequestImpl* request = [[ChordPermissionRequestImpl alloc]
        initWithSite:site
                asks:@[]
              symbol:@"key"
              answer:^(NSInteger answer) {
                if (PasswordPrompt* prompt = weak.get()) {
                  prompt->Answer(static_cast<chord::Answer>(answer));
                }
              }];
    request.question = base::SysUTF16ToNSString(controller_->GetTitle());
    const std::u16string& username =
        controller_->pending_password().username_value;
    request.detail = username.empty() ? site : base::SysUTF16ToNSString(username);
    request.allowTitle = l10n_util::GetNSString(
        update ? IDS_PASSWORD_MANAGER_UPDATE_BUTTON
               : IDS_PASSWORD_MANAGER_SAVE_BUTTON);
    // "Never" is for saving only, as in Chrome's bubble.
    request.blockTitle =
        update ? @""
               : l10n_util::GetNSString(
                     IDS_PASSWORD_MANAGER_BUBBLE_BLOCKLIST_BUTTON);
    request.dismissTitle =
        l10n_util::GetNSString(IDS_PASSWORD_MANAGER_CANCEL_BUTTON);
    request_ = request;
    if (!RequestPermission(&GetWebContents(), request)) {
      // ChordUI does not know the page: nothing shows.
      request_ = nil;
      controller_.reset();
    }
  }

  void Hide() {
    weak_factory_.InvalidateWeakPtrs();
    ChordPermissionRequestImpl* request = request_;
    request_ = nil;
    [request cancel];
    controller_.reset();
  }

 private:
  friend class content::WebContentsUserData<PasswordPrompt>;

  explicit PasswordPrompt(content::WebContents* contents)
      : content::WebContentsUserData<PasswordPrompt>(*contents) {}

  // Answering may make the password manager take its bubble back (Hide()): the
  // controller is taken out first, and goes once it has answered.
  void Answer(chord::Answer answer) {
    std::unique_ptr<SaveUpdateBubbleController> controller =
        std::move(controller_);
    request_ = nil;
    if (!controller) {
      return;
    }
    switch (answer) {
      case kAllow:
        controller->OnSaveClicked();
        break;
      case kBlock:
        controller->OnNeverForThisSiteClicked();
        break;
      case kDismiss:
        controller->OnNotNowClicked();
        break;
    }
  }

  std::unique_ptr<SaveUpdateBubbleController> controller_;
  ChordPermissionRequestImpl* request_;
  base::WeakPtrFactory<PasswordPrompt> weak_factory_{this};

  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

WEB_CONTENTS_USER_DATA_KEY_IMPL(PasswordPrompt);

}  // namespace

bool ShowPasswordBubble(content::WebContents* web_contents) {
  if (!ShowsPermissionPrompts(web_contents)) {
    return false;
  }
  ManagePasswordsUIController* passwords =
      ManagePasswordsUIController::FromWebContents(web_contents);
  password_manager::ui::State state =
      passwords ? passwords->GetState() : password_manager::ui::INACTIVE_STATE;
  if (state != password_manager::ui::PENDING_PASSWORD_STATE &&
      state != password_manager::ui::PENDING_PASSWORD_UPDATE_STATE) {
    return false;
  }
  PasswordPrompt::CreateForWebContents(web_contents);
  PasswordPrompt::FromWebContents(web_contents)->Show();
  return true;
}

void HidePasswordBubble(content::WebContents* web_contents) {
  if (PasswordPrompt* prompt = PasswordPrompt::FromWebContents(web_contents)) {
    prompt->Hide();
  }
}

}  // namespace chord
