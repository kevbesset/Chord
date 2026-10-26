// Copyright 2026 The Chord Authors

#ifndef CHORD_BROWSER_CHORD_CONTEXT_MENU_H_
#define CHORD_BROWSER_CHORD_CONTEXT_MENU_H_

#include "components/remote_cocoa/common/menu.mojom-forward.h"

namespace ui {
class SimpleMenuModel;
}

namespace chord {

// chrome/browser/ui/cocoa/renderer_context_menu/render_view_context_menu_mac_cocoa.mm:
// a page's context menu (right click) in a Chord window, which has no Views widget.
// Takes out the items whose UI needs one (Cast, translate, QR code…) or that open a
// page where ChordUI cannot show it, and returns the menu's look.
remote_cocoa::mojom::MenuControllerParamsPtr PrepareContextMenu(
    ui::SimpleMenuModel* model);

}  // namespace chord

#endif  // CHORD_BROWSER_CHORD_CONTEXT_MENU_H_
