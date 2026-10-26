// Copyright 2026 The Chord Authors
// Chord's data where it belongs: its own folder, encrypted with its own key.

#ifndef CHORD_BROWSER_CHORD_DATA_MIGRATION_H_
#define CHORD_BROWSER_CHORD_DATA_MIGRATION_H_

#include "base/files/file_path.h"

namespace chord {

// Whether this copy of Chord is signed ad hoc (a development build, signed by the
// linker): its signature changes at each build, so macOS would ask for the keychain
// at every launch. Such builds keep their key in Chromium's mock keychain.
bool IsSignedAdHoc();

// First thing at launch, before Chromium opens its data folder: the data of the
// development builds, which lived in ~/Library/Application Support/Chromium next to
// ChordUI's session in …/Chord, moves into Chord's own folder, ChordUI's session
// into its ChordUI subfolder. A Chromium installed on the Mac is left alone: only a
// folder that sits beside ChordUI's session moves. While the old build that uses it is
// open, Chord asks to quit it and stops.
void MoveDataIntoChordFolder();

// Before any profile opens: cookies and passwords encrypted with the mock keychain's
// key (development builds) are encrypted again with Chord's real key, from the
// keychain ("Chord Safe Storage"), once. The folder records which key its data uses.
void UpdateDataEncryption(const base::FilePath& user_data_dir,
                          bool mock_keychain);

}  // namespace chord

#endif  // CHORD_BROWSER_CHORD_DATA_MIGRATION_H_
