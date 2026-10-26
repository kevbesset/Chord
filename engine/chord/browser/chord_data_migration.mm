// Copyright 2026 The Chord Authors

#include "chord/browser/chord_data_migration.h"

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <signal.h>

#include <array>
#include <optional>
#include <string>
#include <vector>

#include "base/command_line.h"
#include "base/files/file_enumerator.h"
#include "base/files/file_util.h"
#include "base/logging.h"
#include "base/path_service.h"
#include "base/process/process.h"
#include "base/strings/strcat.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_util.h"
#include "chrome/common/chrome_paths.h"
#include "chrome/common/chrome_switches.h"
#include "components/os_crypt/common/keychain_password_mac.h"
#include "crypto/aes_cbc.h"
#include "crypto/apple/keychain_v2.h"
#include "sql/database.h"
#include "sql/statement.h"
#include "sql/transaction.h"
#include "third_party/boringssl/src/include/openssl/evp.h"

namespace chord {
namespace {

// In the data folder: "mock" while its cookies and passwords use the mock keychain's
// key, "keychain" once they use Chord's real one.
constexpr char kKeyMarker[] = "Chord Key";

// The password Chromium's mock keychain hands out (crypto/apple/fake_keychain_v2.mm).
constexpr char kMockPassword[] = "mock_password";

// Chromium's key from a keychain password (os_crypt's KeychainKeyProvider).
std::vector<uint8_t> DeriveKey(const std::string& password) {
  static constexpr char kSalt[] = "saltysalt";
  std::vector<uint8_t> key(16);
  PKCS5_PBKDF2_HMAC_SHA1(password.data(), password.size(),
                         reinterpret_cast<const uint8_t*>(kSalt),
                         sizeof(kSalt) - 1, /*iterations=*/1003, key.size(),
                         key.data());
  return key;
}

constexpr std::array<uint8_t, crypto::aes_cbc::kBlockSize> kIV = [] {
  std::array<uint8_t, crypto::aes_cbc::kBlockSize> iv{};
  iv.fill(' ');
  return iv;
}();

// A "v10" value encrypted with `from`, encrypted again with `to`; nullopt when it
// was not encrypted with `from`.
std::optional<std::vector<uint8_t>> Reencrypt(base::span<const uint8_t> value,
                                              const std::vector<uint8_t>& from,
                                              const std::vector<uint8_t>& to) {
  if (value.size() < 3 || value[0] != 'v' || value[1] != '1' ||
      value[2] != '0') {
    return std::nullopt;
  }
  std::optional<std::vector<uint8_t>> plain =
      crypto::aes_cbc::Decrypt(from, kIV, value.subspan(3u));
  if (!plain) {
    return std::nullopt;
  }
  std::vector<uint8_t> result = {'v', '1', '0'};
  std::vector<uint8_t> encrypted = crypto::aes_cbc::Encrypt(to, kIV, *plain);
  result.insert(result.end(), encrypted.begin(), encrypted.end());
  return result;
}

// Every encrypted value of `column` in `table`, row by row, in one transaction.
void ReencryptColumn(const base::FilePath& path,
                     sql::Database::Tag tag,
                     const std::string& table,
                     const std::string& column,
                     const std::vector<uint8_t>& from,
                     const std::vector<uint8_t>& to) {
  if (!base::PathExists(path)) {
    return;
  }
  sql::Database db(sql::DatabaseOptions(), tag);
  if (!db.Open(path) || !db.DoesColumnExist(table, column)) {
    return;
  }
  sql::Transaction transaction(&db);
  if (!transaction.Begin()) {
    return;
  }
  std::vector<std::pair<int64_t, std::vector<uint8_t>>> updates;
  {
    sql::Statement select(db.GetUniqueStatement(
        base::StrCat({"SELECT rowid, ", column, " FROM ", table})));
    while (select.Step()) {
      if (std::optional<std::vector<uint8_t>> value =
              Reencrypt(select.ColumnBlob(1), from, to)) {
        updates.emplace_back(select.ColumnInt64(0), std::move(*value));
      }
    }
  }
  const std::string update_sql =
      base::StrCat({"UPDATE ", table, " SET ", column, "=? WHERE rowid=?"});
  for (const auto& [rowid, value] : updates) {
    sql::Statement update(db.GetUniqueStatement(update_sql));
    update.BindBlob(0, value);
    update.BindInt64(1, rowid);
    update.Run();
  }
  transaction.Commit();
}

// Whether a Chromium-made data folder is in use: its lock names a running process.
bool IsInUse(const base::FilePath& folder) {
  base::FilePath target;
  if (!base::ReadSymbolicLink(folder.Append("SingletonLock"), &target)) {
    return false;
  }
  std::string lock = target.value();  // "host-pid"
  size_t dash = lock.rfind('-');
  int pid = 0;
  return dash != std::string::npos &&
         base::StringToInt(lock.substr(dash + 1), &pid) && pid > 0 &&
         kill(pid, 0) == 0;
}

// The development build that still uses the old folder is open: moving its data now
// would split it in two. Chord asks to quit that one first, and stops.
[[noreturn]] void AskToQuitOldChord() {
  CFUserNotificationDisplayAlert(
      0, kCFUserNotificationCautionAlertLevel, nullptr, nullptr, nullptr,
      (__bridge CFStringRef) @"Une autre version de Chord est ouverte",
      (__bridge CFStringRef) @"Chord range maintenant ses données dans son "
                             @"propre dossier. Quittez la version déjà "
                             @"ouverte, puis relancez Chord : vos Spaces, "
                             @"onglets et connexions suivront.",
      (__bridge CFStringRef) @"OK", nullptr, nullptr, nullptr);
  base::Process::TerminateCurrentProcessImmediately(0);
}

}  // namespace

bool IsSignedAdHoc() {
  SecCodeRef code = nullptr;
  if (SecCodeCopySelf(kSecCSDefaultFlags, &code) != errSecSuccess) {
    return true;
  }
  SecStaticCodeRef static_code = nullptr;
  OSStatus status =
      SecCodeCopyStaticCode(code, kSecCSDefaultFlags, &static_code);
  CFRelease(code);
  if (status != errSecSuccess) {
    return true;
  }
  CFDictionaryRef info = nullptr;
  status = SecCodeCopySigningInformation(static_code, kSecCSSigningInformation,
                                         &info);
  CFRelease(static_code);
  if (status != errSecSuccess || !info) {
    return true;
  }
  NSDictionary* signing = (__bridge_transfer NSDictionary*)info;
  NSNumber* flags = signing[(__bridge NSString*)kSecCodeInfoFlags];
  // Unsigned code has no certificates either.
  return !signing[(__bridge NSString*)kSecCodeInfoCertificates] ||
         (flags.unsignedIntValue & kSecCodeSignatureAdhoc);
}

void MoveDataIntoChordFolder() {
  // Tests and second profile folders choose their own.
  if (base::CommandLine::ForCurrentProcess()->HasSwitch(
          switches::kUserDataDir)) {
    return;
  }
  base::FilePath chord;
  if (!base::PathService::Get(chrome::DIR_USER_DATA, &chord) ||
      chord.BaseName().value() != "Chord") {
    return;
  }
  base::FilePath chromium = chord.DirName().Append("Chromium");
  base::FilePath old_session = chord.Append("session.json");
  if (base::PathExists(old_session) &&
      !base::PathExists(chord.Append("Local State")) &&
      base::PathExists(chromium.Append("Local State"))) {
    if (IsInUse(chromium)) {
      AskToQuitOldChord();
    }
    base::FileEnumerator entries(
        chromium, /*recursive=*/false,
        base::FileEnumerator::FILES | base::FileEnumerator::DIRECTORIES |
            base::FileEnumerator::SHOW_SYM_LINKS);
    for (base::FilePath entry = entries.Next(); !entry.empty();
         entry = entries.Next()) {
      std::string name = entry.BaseName().value();
      base::FilePath target = chord.Append(name);
      // The old instance's lock, and what Chord already made in its folder.
      if (base::StartsWith(name, "Singleton") || base::PathExists(target)) {
        continue;
      }
      if (!base::Move(entry, target)) {
        LOG(ERROR) << "Chord: could not move " << entry;
      }
    }
    // The development builds encrypted with the mock keychain's key.
    base::WriteFile(chord.Append(kKeyMarker), "mock");
    LOG(WARNING) << "Chord: data moved from " << chromium << " to " << chord;
  }
  // ChordUI's session now lives in the data folder, as with --user-data-dir.
  base::FilePath session = chord.Append("ChordUI").Append("session.json");
  if (base::PathExists(old_session) && !base::PathExists(session)) {
    base::CreateDirectory(session.DirName());
    base::Move(old_session, session);
  }
}

void UpdateDataEncryption(const base::FilePath& user_data_dir,
                          bool mock_keychain) {
  base::FilePath marker = user_data_dir.Append(kKeyMarker);
  std::string current;
  base::ReadFileToString(marker, &current);
  if (current.empty()) {
    // A new folder, or one from before the marker: it uses the key of this build.
    base::WriteFile(marker, mock_keychain ? "mock" : "keychain");
    return;
  }
  if (mock_keychain || current != "mock") {
    if (mock_keychain && current != "mock") {
      LOG(ERROR) << "Chord: this build signed ad hoc cannot read the data "
                    "encrypted with Chord's keychain key";
    }
    return;
  }

  // macOS may ask the user, the first time, to let Chord use its keychain item.
  std::string password =
      KeychainPassword(crypto::apple::KeychainV2::GetInstance()).GetPassword();
  if (password.empty()) {
    LOG(ERROR) << "Chord: no keychain key yet, data stays as it is";
    return;
  }
  const std::vector<uint8_t> from = DeriveKey(kMockPassword);
  const std::vector<uint8_t> to = DeriveKey(password);
  base::FileEnumerator profiles(user_data_dir, /*recursive=*/false,
                                base::FileEnumerator::DIRECTORIES);
  for (base::FilePath profile = profiles.Next(); !profile.empty();
       profile = profiles.Next()) {
    ReencryptColumn(profile.Append("Cookies"), "Cookie", "cookies",
                    "encrypted_value", from, to);
    ReencryptColumn(profile.Append("Login Data"), "Passwords", "logins",
                    "password_value", from, to);
    ReencryptColumn(profile.Append("Login Data For Account"), "Passwords",
                    "logins", "password_value", from, to);
    ReencryptColumn(profile.Append("Web Data"), "Web", "credit_cards",
                    "card_number_encrypted", from, to);
  }
  base::WriteFile(marker, "keychain");
  LOG(WARNING) << "Chord: cookies and passwords now use the keychain key";
}

}  // namespace chord
