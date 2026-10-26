// Copyright 2026 The Chord Authors
// A page's context menu in Chord's windows (right click), which Chromium shows as a
// native menu: Chord prepares it, as these windows have no Views widget.

#include <optional>

#include "base/numerics/safe_conversions.h"
#include "chord/browser/chord_context_menu.h"
#include "chrome/app/chrome_command_ids.h"
#include "components/remote_cocoa/common/menu.mojom.h"
#include "third_party/skia/include/core/SkColor.h"
#include "ui/menus/simple_menu_model.h"
#include "ui/views/badge_painter.h"
#include "ui/views/controls/menu/menu_config.h"
#include "ui/views/layout/layout_provider.h"

namespace chord {
namespace {

// Items whose UI is a Views bubble or side panel anchored to Chromium's own window
// (Cast, translate, QR code, Lens, reading mode, sharing…), or that open a page where
// ChordUI cannot show it (another profile, a Chromium private or app window).
constexpr int kItemsWithoutChordUI[] = {
    IDC_ROUTE_MEDIA,
    IDC_CONTENT_CONTEXT_TRANSLATE,
    IDC_CONTENT_CONTEXT_PARTIAL_TRANSLATE,
    IDC_CONTENT_CONTEXT_GENERATE_QR_CODE,
    IDC_SEND_TAB_TO_SELF,
    IDC_CONTENT_CONTEXT_SHARING_SUBMENU,
    IDC_CONTENT_CONTEXT_LENS_REGION_SEARCH,
    IDC_CONTENT_CONTEXT_WEB_REGION_SEARCH,
    IDC_CONTENT_CONTEXT_SEARCHLENSFORIMAGE,
    IDC_CONTENT_CONTEXT_SEARCHLENSFORVIDEOFRAME,
    IDC_CONTENT_CONTEXT_OPEN_IN_READING_MODE,
    IDC_CONTENT_CONTEXT_LISTEN_TO_THIS_PAGE,
    IDC_CONTENT_CONTEXT_ADD_LINK_TO_READING_LIST,
    IDC_CONTENT_CONTEXT_GLIC,
    IDC_CONTENT_CONTEXT_GLICSHAREIMAGE,
    IDC_CONTEXT_COMPOSE,
    IDC_CONTENT_CONTEXT_OPENLINKINPROFILE,
    IDC_CONTENT_CONTEXT_OPENLINKOFFTHERECORD,
    IDC_CONTENT_CONTEXT_OPENLINKSPLITVIEW,
    IDC_CONTENT_CONTEXT_OPENLINKBOOKMARKAPP,
    IDC_CONTENT_CONTEXT_OPENLINK_ISOLATED,
};

bool IsWithoutChordUI(int command_id) {
  for (int id : kItemsWithoutChordUI) {
    if (id == command_id) {
      return true;
    }
  }
  // "Open link as <profile>", one item per other profile: at most 100, as
  // render_view_context_menu.cc counts them.
  return command_id >= IDC_OPEN_LINK_IN_PROFILE_FIRST &&
         command_id < IDC_OPEN_LINK_IN_PROFILE_FIRST + 100;
}

}  // namespace

remote_cocoa::mojom::MenuControllerParamsPtr PrepareContextMenu(
    ui::SimpleMenuModel* model) {
  for (size_t i = model->GetItemCount(); i-- > 0;) {
    if (model->GetTypeAt(i) != ui::MenuModel::TYPE_SEPARATOR &&
        IsWithoutChordUI(model->GetCommandIdAt(i))) {
      model->RemoveItemAt(i);
    }
  }
  // What is left keeps its separators between groups only.
  for (size_t i = model->GetItemCount(); i-- > 0;) {
    if (model->GetTypeAt(i) != ui::MenuModel::TYPE_SEPARATOR) {
      continue;
    }
    bool first = i == 0;
    bool last = i + 1 == model->GetItemCount();
    bool doubled =
        !first && model->GetTypeAt(i - 1) == ui::MenuModel::TYPE_SEPARATOR;
    if (first || last || doubled) {
      model->RemoveItemAt(i);
    }
  }

  // The look Chromium gives its menus ("new" badges), with the system's blue.
  constexpr SkColor kBlue = SkColorSetRGB(0x0A, 0x84, 0xFF);
  auto params = remote_cocoa::mojom::MenuControllerParams::New();
  params->badge_font = views::BadgePainter::GetBadgeFont(
                           views::MenuConfig::instance().font_list)
                           .GetPrimaryFont();
  params->badge_color = kBlue;
  params->badge_text_color = SK_ColorWHITE;
  params->badge_horizontal_margin = views::BadgePainter::kBadgeHorizontalMargin;
  params->badge_internal_padding = views::BadgePainter::kBadgeInternalPadding;
  params->badge_min_height = views::BadgePainter::kBadgeMinHeightCocoa;
  params->badge_radius = base::checked_cast<uint32_t>(
      views::LayoutProvider::Get()->GetCornerRadiusMetric(
          views::ShapeContextTokens::kBadgeRadius));
  params->iph_dot_color = kBlue;
  return params;
}

}  // namespace chord
