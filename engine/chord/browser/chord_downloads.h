// Copyright 2026 The Chord Authors

#ifndef CHORD_BROWSER_CHORD_DOWNLOADS_H_
#define CHORD_BROWSER_CHORD_DOWNLOADS_H_

#import "chord/browser/chord_ui.h"

#include <map>
#include <string>

#include "base/memory/raw_ptr.h"
#include "base/scoped_observation.h"
#include "components/download/public/common/download_item.h"
#include "content/public/browser/download_manager.h"

class Profile;

namespace chord {

// Follows a profile's downloads for ChordUI's downloads panel. Each download is told
// to the page that started it (else the profile's active page), once its file is
// chosen, then its progress and its end. Chromium's own downloads bubble is made of
// Views and needs Chrome's toolbar, which Chord's windows do not have.
class DownloadsWatcher : public content::DownloadManager::Observer,
                         public download::DownloadItem::Observer {
 public:
  explicit DownloadsWatcher(Profile* profile);
  DownloadsWatcher(const DownloadsWatcher&) = delete;
  DownloadsWatcher& operator=(const DownloadsWatcher&) = delete;
  ~DownloadsWatcher() override;

  // content::DownloadManager::Observer:
  void OnDownloadCreated(content::DownloadManager* manager,
                         download::DownloadItem* item) override;
  void ManagerGoingDown(content::DownloadManager* manager) override;

  // download::DownloadItem::Observer:
  void OnDownloadUpdated(download::DownloadItem* item) override;
  void OnDownloadDestroyed(download::DownloadItem* item) override;

  // A download of this session still running, by its id (Chromium's GUID).
  download::DownloadItem* Find(const std::string& guid);

 private:
  struct Download {
    raw_ptr<download::DownloadItem> item;
    id<ChordWebPage> page;
    bool announced = false;
    bool approval_asked = false;
    int percent = -1;
  };

  void Forget(download::DownloadItem* item);

  std::map<std::string, Download> downloads_;
  base::ScopedObservation<content::DownloadManager,
                          content::DownloadManager::Observer>
      manager_observation_{this};
};

// The download with this id (Chromium's GUID), in any profile.
void CancelDownload(const std::string& guid);
void KeepDownload(const std::string& guid);

}  // namespace chord

#endif  // CHORD_BROWSER_CHORD_DOWNLOADS_H_
