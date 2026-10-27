// Copyright 2026 The Chord Authors

#import "chord/browser/chord_downloads.h"

#include <set>

#include "base/files/file_path.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#import "chord/browser/chord_engine.h"
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/download_item_utils.h"

namespace chord {
namespace {

std::set<DownloadsWatcher*>& Watchers() {
  static base::NoDestructor<std::set<DownloadsWatcher*>> watchers;
  return *watchers;
}

NSString* ID(download::DownloadItem* item) {
  return base::SysUTF8ToNSString(item->GetGuid());
}

NSURL* FileURL(const base::FilePath& path) {
  return [NSURL fileURLWithPath:base::SysUTF8ToNSString(path.value())];
}

// What the browser warns about: "insecure" (an http address) or "dangerous" (a
// file type that can harm the Mac).
NSString* Warning(download::DownloadItem* item) {
  return item->IsInsecure() ? @"insecure" : @"dangerous";
}

}  // namespace

DownloadsWatcher::DownloadsWatcher(Profile* profile) {
  if (content::DownloadManager* manager = profile->GetDownloadManager()) {
    manager_observation_.Observe(manager);
  }
  Watchers().insert(this);
}

DownloadsWatcher::~DownloadsWatcher() {
  Watchers().erase(this);
  for (auto& [guid, download] : downloads_) {
    download.item->RemoveObserver(this);
  }
}

// A download of this session (the history's past downloads arrive done).
void DownloadsWatcher::OnDownloadCreated(content::DownloadManager* manager,
                                         download::DownloadItem* item) {
  if (item->IsTransient() ||
      item->GetState() != download::DownloadItem::IN_PROGRESS) {
    return;
  }
  downloads_[item->GetGuid()].item = item;
  item->AddObserver(this);
  OnDownloadUpdated(item);
}

void DownloadsWatcher::ManagerGoingDown(content::DownloadManager* manager) {
  for (auto& [guid, download] : downloads_) {
    download.item->RemoveObserver(this);
  }
  downloads_.clear();
  manager_observation_.Reset();
}

void DownloadsWatcher::OnDownloadUpdated(download::DownloadItem* item) {
  auto it = downloads_.find(item->GetGuid());
  if (it == downloads_.end()) {
    return;
  }
  Download& download = it->second;
  NSString* downloadID = ID(item);
  if (!download.announced) {
    // Once its file is chosen (Chromium may ask where to save it first).
    if (item->GetTargetFilePath().empty()) {
      return;
    }
    download.announced = true;
    content::WebContents* contents =
        content::DownloadItemUtils::GetWebContents(item);
    download.page = PageForContents(contents);
    if (!download.page) {
      download.page = ActivePageForProfile(
          content::DownloadItemUtils::GetBrowserContext(item));
    }
    if (!download.page) {
      return;
    }
    id<ChordWebPage> page = download.page;
    NSURL* destination = FileURL(item->GetTargetFilePath());
    // After Chromium's own work: ChordUI may close the tab the file came from.
    dispatch_async(dispatch_get_main_queue(), ^{
      id<ChordWebPageDelegate> delegate = page.delegate;
      if ([delegate respondsToSelector:@selector
                    (page:didStartDownload:destination:)]) {
        [delegate page:page didStartDownload:downloadID destination:destination];
      }
    });
  }
  id<ChordWebPage> page = download.page;
  if (!page) {
    return;
  }
  auto tell = ^(void (^call)(id<ChordWebPageDelegate>)) {
    dispatch_async(dispatch_get_main_queue(), ^{
      call(page.delegate);
    });
  };

  if ((item->IsDangerous() || item->IsInsecure()) && !download.approval_asked &&
      item->GetState() == download::DownloadItem::IN_PROGRESS) {
    download.approval_asked = true;
    NSString* warning = Warning(item);
    tell(^(id<ChordWebPageDelegate> delegate) {
      if ([delegate respondsToSelector:@selector
                    (page:download:needsApproval:)]) {
        [delegate page:page download:downloadID needsApproval:warning];
      }
    });
  }

  switch (item->GetState()) {
    case download::DownloadItem::IN_PROGRESS: {
      int64_t total = item->GetTotalBytes();
      int percent =
          total > 0 ? static_cast<int>(item->GetReceivedBytes() * 100 / total)
                    : 0;
      if (percent == download.percent) {
        return;
      }
      download.percent = percent;
      double fraction = percent / 100.0;
      tell(^(id<ChordWebPageDelegate> delegate) {
        if ([delegate respondsToSelector:@selector(page:download:didProgress:)]) {
          [delegate page:page download:downloadID didProgress:fraction];
        }
      });
      return;
    }
    case download::DownloadItem::COMPLETE:
    case download::DownloadItem::CANCELLED:
    case download::DownloadItem::INTERRUPTED: {
      NSURL* file = item->GetState() == download::DownloadItem::COMPLETE
                        ? FileURL(item->GetTargetFilePath())
                        : nil;
      tell(^(id<ChordWebPageDelegate> delegate) {
        if ([delegate respondsToSelector:@selector(page:download:didFinishAt:)]) {
          [delegate page:page download:downloadID didFinishAt:file];
        }
      });
      Forget(item);
      return;
    }
    default:
      return;
  }
}

void DownloadsWatcher::OnDownloadDestroyed(download::DownloadItem* item) {
  Forget(item);
}

void DownloadsWatcher::Forget(download::DownloadItem* item) {
  item->RemoveObserver(this);
  downloads_.erase(item->GetGuid());
}

namespace {

download::DownloadItem* FindDownload(const std::string& guid) {
  for (DownloadsWatcher* watcher : Watchers()) {
    if (download::DownloadItem* item = watcher->Find(guid)) {
      return item;
    }
  }
  return nullptr;
}

}  // namespace

download::DownloadItem* DownloadsWatcher::Find(const std::string& guid) {
  auto it = downloads_.find(guid);
  return it == downloads_.end() ? nullptr : it->second.item.get();
}

void CancelDownload(const std::string& guid) {
  if (download::DownloadItem* item = FindDownload(guid)) {
    item->Cancel(/*user_cancel=*/true);
  }
}

void KeepDownload(const std::string& guid) {
  download::DownloadItem* item = FindDownload(guid);
  if (!item) {
    return;
  }
  if (item->IsInsecure()) {
    item->ValidateInsecureDownload();
  } else if (item->IsDangerous()) {
    item->ValidateDangerousDownload();
  }
}

}  // namespace chord
