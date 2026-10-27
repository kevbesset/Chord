// Copyright 2026 The Chord Authors

#ifndef CHORD_BROWSER_CHORD_ARC_IMPORT_H_
#define CHORD_BROWSER_CHORD_ARC_IMPORT_H_

#include "base/files/file_path.h"
#include "base/functional/callback_forward.h"

class Profile;

namespace chord {

struct ArcImportCounts {
  int cookies = 0;
  int passwords = 0;
  int pages = 0;
  // Values typed in Arc's forms, offered again under the same fields.
  int form_values = 0;
  // Installed from the Chrome Web Store; their data comes at the next launch.
  int extensions = 0;
  // Arc's site storage (Local Storage, IndexedDB) comes at the next launch.
  bool site_storage = false;
  // macOS did not give Arc's key: cookies and passwords stayed behind.
  bool key_denied = false;
};

// Arc keeps a Chromium profile: its logins (cookies), passwords, history, values
// typed in forms and extensions from the Chrome Web Store go into `profile` through Chromium's own
// services, which encrypt them with Chord's key. Arc's key comes from its keychain
// item, which macOS asks the user for. Arc's databases are read from copies, so Arc
// may be running. `arc_profile` is one of Arc's profile folders
// ("…/Arc/User Data/Default"). Importing again adds only what is new.
void ImportArcProfile(Profile* profile,
                      const base::FilePath& arc_profile,
                      base::OnceCallback<void(ArcImportCounts)> done);

// At launch, before any profile opens: the site storage of the Arc profiles imported
// last time joins their Chord profiles, without replacing what a site already keeps
// there.
void MergePendingArcSiteStorage(const base::FilePath& user_data_dir);

}  // namespace chord

#endif  // CHORD_BROWSER_CHORD_ARC_IMPORT_H_
