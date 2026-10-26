// Copyright 2026 The Chord Authors
// The extensions ChordUI shows, like Arc's: their buttons (icon, badge, pinned or
// not) and their popups, which Chromium would show in its Views toolbar.

#ifndef CHORD_BROWSER_CHORD_EXTENSIONS_H_
#define CHORD_BROWSER_CHORD_EXTENSIONS_H_

#import <AppKit/AppKit.h>

#include <map>
#include <memory>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/scoped_observation.h"
#include "chord/browser/chord_ui.h"
#include "chrome/browser/extensions/extension_action_dispatcher.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "extensions/browser/extension_action_icon_factory.h"

class Profile;

namespace content {
class WebContents;
}

namespace chord {

// Follows a profile's extensions with an action (a toolbar button in Chrome):
// added, removed, pinned, their badges and icons. `changed` runs, at most once per
// turn of the run loop, when ChordUI should draw them again.
class ExtensionsWatcher : public ToolbarActionsModel::Observer,
                          public extensions::ExtensionActionDispatcher::Observer,
                          public extensions::ExtensionActionIconFactory::Observer {
 public:
  ExtensionsWatcher(Profile* profile, base::RepeatingClosure changed);
  ~ExtensionsWatcher() override;

  // The extensions as `contents` sees them (badges are per tab), pinned ones first in
  // their order, then the others by name. Each: "id", "name", "icon" (NSImage),
  // "badge", "badgeColor" (NSColor), "pinned" (NSNumber), "options" (NSString URL).
  NSArray<NSDictionary<NSString*, id>*>* ExtensionsFor(
      content::WebContents* contents);

  void SetPinned(const std::string& id, bool pinned);
  void Uninstall(const std::string& id);

  // ToolbarActionsModel::Observer:
  void OnToolbarActionAdded(const ToolbarActionsModel::ActionId& id) override;
  void OnToolbarActionRemoved(const ToolbarActionsModel::ActionId& id) override;
  void OnToolbarActionUpdated(const ToolbarActionsModel::ActionId& id) override;
  void OnToolbarModelInitialized() override;
  void OnToolbarPinnedActionsChanged() override;
  void OnToolbarActionsModelShutdown() override;

  // extensions::ExtensionActionDispatcher::Observer:
  void OnExtensionActionUpdated(
      extensions::ExtensionAction* extension_action,
      content::WebContents* web_contents,
      content::BrowserContext* browser_context) override;
  void OnShuttingDown() override;

  // extensions::ExtensionActionIconFactory::Observer:
  void OnIconUpdated() override;

 private:
  void Changed();

  raw_ptr<Profile> profile_;
  base::RepeatingClosure changed_;
  bool change_pending_ = false;
  // One per extension, kept: icons load asynchronously, then tell this watcher.
  std::map<std::string, std::unique_ptr<extensions::ExtensionActionIconFactory>>
      icon_factories_;
  base::ScopedObservation<ToolbarActionsModel, ToolbarActionsModel::Observer>
      model_observation_{this};
  base::ScopedObservation<extensions::ExtensionActionDispatcher,
                          extensions::ExtensionActionDispatcher::Observer>
      dispatcher_observation_{this};
  base::WeakPtrFactory<ExtensionsWatcher> weak_factory_{this};
};

// Runs the extension's action on the page, as a click on its toolbar button does.
// Returns its popup, for ChordUI to show, or nil when the action shows none.
id<ChordExtensionPopup> RunExtension(content::WebContents* contents,
                                     const std::string& id);

}  // namespace chord

#endif  // CHORD_BROWSER_CHORD_EXTENSIONS_H_
