// Copyright 2026 The Chord Authors

#include "chord/browser/chord_arc_import.h"

#import <Foundation/Foundation.h>
#import <Security/Security.h>

#include <array>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <tuple>
#include <vector>

#include "base/barrier_closure.h"
#include "base/files/file_enumerator.h"
#include "base/files/file_util.h"
#include "base/files/scoped_temp_dir.h"
#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/memory/ref_counted.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/synchronization/lock.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/thread_pool.h"
#include "base/time/time.h"
#include "base/values.h"
#include "base/version_info/version_info.h"
#include "chrome/browser/history/history_service_factory.h"
#include "chrome/browser/password_manager/factories/profile_password_store_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "components/crx_file/crx_verifier.h"
#include "components/history/core/browser/history_service.h"
#include "components/history/core/browser/url_row.h"
#include "components/keyed_service/core/service_access_type.h"
#include "components/password_manager/core/browser/password_form.h"
#include "components/password_manager/core/browser/password_store/password_store_consumer.h"
#include "components/password_manager/core/browser/password_store/password_store_interface.h"
#include "components/password_manager/core/browser/password_store/stored_credential.h"
#include "content/public/browser/storage_partition.h"
#include "crypto/aes_cbc.h"
#include "extensions/browser/crx_file_info.h"
#include "extensions/browser/crx_installer.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/common/mojom/manifest.mojom-shared.h"
#include "crypto/sha2.h"
#include "net/cookies/canonical_cookie.h"
#include "net/cookies/cookie_access_result.h"
#include "net/cookies/cookie_options.h"
#include "net/cookies/cookie_partition_key.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/simple_url_loader.h"
#include "services/network/public/mojom/cookie_manager.mojom.h"
#include "sql/database.h"
#include "sql/statement.h"
#include "third_party/boringssl/src/include/openssl/evp.h"
#include "third_party/leveldatabase/src/include/leveldb/db.h"
#include "third_party/leveldatabase/src/include/leveldb/write_batch.h"
#include "url/gurl.h"

namespace chord {
namespace {

// Left in a Chord profile's folder after an import, as JSON: Arc's profile folder
// ("arc"), whose site storage joins the profile at the next launch, and the
// extensions the import installed ("extensions"), whose data comes with it.
constexpr char kPendingSiteStorage[] = "Chord Arc Site Storage";

// In a Chord profile's folder: the last visit of Arc's history already imported,
// so that importing again adds only what is newer.
constexpr char kHistoryImported[] = "Chord Arc History";

// Like Chromium's history, only the last 90 days.
constexpr base::TimeDelta kHistoryKept = base::Days(90);

constexpr net::NetworkTrafficAnnotationTag kTrafficAnnotation =
    net::DefineNetworkTrafficAnnotation("chord_arc_extensions", R"(
      semantics {
        sender: "Chord Arc import"
        description:
          "Downloads from the Chrome Web Store the extensions the user had in "
          "Arc, to install them in Chord."
        trigger: "The user imports from Arc."
        data: "The extension's id and the browser's version."
        destination: GOOGLE_OWNED_SERVICE
      }
      policy {
        cookies_allowed: NO
        setting: "None: the user starts the import."
        policy_exception_justification: "Chord's own import."
      })");

struct ArcData {
  std::vector<net::CanonicalCookie> cookies;
  std::vector<password_manager::StoredCredential> passwords;
  history::URLRows pages;
  base::Time newest_page;
  // Ids of Arc's extensions from the Chrome Web Store: the same in every browser.
  std::vector<std::string> extensions;
  bool site_storage = false;
  bool key_denied = false;
};

// Arc's own Chromium key, derived like Chromium's from the password of Arc's keychain
// item. macOS asks the user before handing it to Chord.
std::optional<std::vector<uint8_t>> ReadArcKey() {
  NSDictionary* query = @{
    (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService : @"Arc Safe Storage",
    (__bridge id)kSecAttrAccount : @"Arc",
    (__bridge id)kSecReturnData : @YES,
    (__bridge id)kSecMatchLimit : (__bridge id)kSecMatchLimitOne,
  };
  CFTypeRef result = nullptr;
  if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) !=
          errSecSuccess ||
      !result) {
    return std::nullopt;
  }
  NSData* password = (__bridge_transfer NSData*)result;
  static constexpr char kSalt[] = "saltysalt";
  std::vector<uint8_t> key(16);
  if (!PKCS5_PBKDF2_HMAC_SHA1(static_cast<const char*>(password.bytes),
                              password.length,
                              reinterpret_cast<const uint8_t*>(kSalt),
                              sizeof(kSalt) - 1, /*iterations=*/1003,
                              key.size(), key.data())) {
    return std::nullopt;
  }
  return key;
}

// The key, asked once for all of Arc's profiles imported together (they share it):
// the answer, given or refused, holds for a minute.
std::optional<std::vector<uint8_t>> ArcKey() {
  struct Cache {
    base::Lock lock;
    base::TimeTicks asked;
    std::optional<std::vector<uint8_t>> key;
  };
  static base::NoDestructor<Cache> cache;
  base::AutoLock lock(cache->lock);
  if (cache->asked.is_null() ||
      base::TimeTicks::Now() - cache->asked > base::Minutes(1)) {
    cache->key = ReadArcKey();
    cache->asked = base::TimeTicks::Now();
  }
  return cache->key;
}

// A value Arc encrypted ("v10", AES-128-CBC with an IV of spaces).
std::optional<std::string> Decrypt(const std::vector<uint8_t>& key,
                                   base::span<const uint8_t> value) {
  if (value.size() < 3 || value[0] != 'v' || value[1] != '1' ||
      value[2] != '0') {
    return std::nullopt;
  }
  std::array<uint8_t, crypto::aes_cbc::kBlockSize> iv;
  iv.fill(' ');
  std::optional<std::vector<uint8_t>> plain =
      crypto::aes_cbc::Decrypt(key, iv, value.subspan(3u));
  if (!plain) {
    return std::nullopt;
  }
  return std::string(plain->begin(), plain->end());
}

base::Time FromChromiumTime(int64_t microseconds) {
  return microseconds ? base::Time::FromDeltaSinceWindowsEpoch(
                            base::Microseconds(microseconds))
                      : base::Time();
}

// Arc may be running: its databases are read from copies, with their journals.
bool OpenCopy(const base::FilePath& source,
              const base::ScopedTempDir& temp,
              sql::Database& db) {
  if (!base::PathExists(source)) {
    return false;
  }
  base::FilePath copy = temp.GetPath().Append(source.BaseName());
  for (const char* suffix : {"", "-journal", "-wal", "-shm"}) {
    base::FilePath from(source.value() + suffix);
    if (base::PathExists(from)) {
      base::CopyFile(from, base::FilePath(copy.value() + suffix));
    }
  }
  return db.Open(copy);
}

int MetaVersion(sql::Database& db) {
  sql::Statement statement(
      db.GetUniqueStatement("SELECT value FROM meta WHERE key='version'"));
  return statement.Step() ? statement.ColumnInt(0) : 0;
}

void ReadCookies(const base::FilePath& arc_profile,
                 const base::ScopedTempDir& temp,
                 const std::vector<uint8_t>& key,
                 ArcData& data) {
  sql::Database db(sql::DatabaseOptions(), "FirefoxImporter");
  if (!OpenCopy(arc_profile.Append("Cookies"), temp, db)) {
    return;
  }
  // From version 24, a cookie's value starts with the hash of its domain.
  const bool hashed = MetaVersion(db) >= 24;
  sql::Statement statement(db.GetUniqueStatement(
      "SELECT host_key, top_frame_site_key, name, value, encrypted_value, path, "
      "creation_utc, expires_utc, last_access_utc, last_update_utc, is_secure, "
      "is_httponly, has_expires, is_persistent, priority, samesite, "
      "source_scheme, source_port, source_type, has_cross_site_ancestor "
      "FROM cookies"));
  const base::Time now = base::Time::Now();
  while (statement.Step()) {
    std::string domain = statement.ColumnString(0);
    std::string value = statement.ColumnString(3);
    base::span<const uint8_t> encrypted = statement.ColumnBlob(4);
    if (!encrypted.empty()) {
      std::optional<std::string> plain = Decrypt(key, encrypted);
      if (!plain) {
        continue;
      }
      value = std::move(*plain);
      if (hashed) {
        std::string hash = crypto::SHA256HashString(domain);
        if (!base::StartsWith(value, hash)) {
          continue;
        }
        value = value.substr(hash.size());
      }
    }
    base::Time expiration;
    if (statement.ColumnBool(12) && statement.ColumnBool(13)) {
      expiration = FromChromiumTime(statement.ColumnInt64(7));
      if (expiration < now) {
        continue;
      }
    }
    auto partition_key = net::CookiePartitionKey::FromStorage(
        statement.ColumnString(1), statement.ColumnBool(19));
    if (!partition_key.has_value()) {
      continue;
    }
    std::unique_ptr<net::CanonicalCookie> cookie =
        net::CanonicalCookie::FromStorage(
            statement.ColumnString(2), std::move(value), std::move(domain),
            statement.ColumnString(5), FromChromiumTime(statement.ColumnInt64(6)),
            expiration, FromChromiumTime(statement.ColumnInt64(8)),
            FromChromiumTime(statement.ColumnInt64(9)),
            statement.ColumnBool(10), statement.ColumnBool(11),
            static_cast<net::CookieSameSite>(statement.ColumnInt(15)),
            static_cast<net::CookiePriority>(statement.ColumnInt(14)),
            std::move(*partition_key),
            static_cast<net::CookieSourceScheme>(statement.ColumnInt(16)),
            statement.ColumnInt(17),
            static_cast<net::CookieSourceType>(statement.ColumnInt(18)),
            net::CanonicalCookieFromStorageCallSite::kCookieManager);
    if (cookie) {
      data.cookies.push_back(std::move(*cookie));
    }
  }
}

void ReadPasswords(const base::FilePath& arc_profile,
                   const base::ScopedTempDir& temp,
                   const std::vector<uint8_t>& key,
                   ArcData& data) {
  sql::Database db(sql::DatabaseOptions(), "FirefoxImporter");
  if (!OpenCopy(arc_profile.Append("Login Data"), temp, db)) {
    return;
  }
  sql::Statement statement(db.GetUniqueStatement(
      "SELECT origin_url, action_url, username_element, username_value, "
      "password_element, password_value, submit_element, signon_realm, "
      "date_created, blacklisted_by_user, scheme, password_type, times_used, "
      "display_name, date_last_used, date_password_modified FROM logins"));
  while (statement.Step()) {
    password_manager::StoredCredential credential;
    credential.blocked_by_user = statement.ColumnBool(9);
    base::span<const uint8_t> encrypted = statement.ColumnBlob(5);
    if (!encrypted.empty()) {
      std::optional<std::string> plain = Decrypt(key, encrypted);
      if (!plain) {
        continue;
      }
      credential.password_value =
          password_manager::PasswordString(base::UTF8ToUTF16(*plain));
    } else if (!credential.blocked_by_user) {
      continue;
    }
    credential.url = GURL(statement.ColumnString(0));
    credential.action = GURL(statement.ColumnString(1));
    credential.username_element = statement.ColumnString16(2);
    credential.username_value = statement.ColumnString16(3);
    credential.password_element = statement.ColumnString16(4);
    credential.submit_element = statement.ColumnString16(6);
    credential.signon_realm = statement.ColumnString(7);
    credential.date_created = FromChromiumTime(statement.ColumnInt64(8));
    credential.scheme =
        static_cast<password_manager::PasswordForm::Scheme>(
            statement.ColumnInt(10));
    credential.type = static_cast<password_manager::PasswordForm::Type>(
        statement.ColumnInt(11));
    credential.times_used_in_html_form = statement.ColumnInt(12);
    credential.display_name = statement.ColumnString16(13);
    credential.date_last_used = FromChromiumTime(statement.ColumnInt64(14));
    credential.date_password_modified =
        FromChromiumTime(statement.ColumnInt64(15));
    credential.in_store = password_manager::PasswordForm::Store::kProfileStore;
    if (credential.url.is_valid() && !credential.signon_realm.empty()) {
      data.passwords.push_back(std::move(credential));
    }
  }
}

void ReadHistory(const base::FilePath& arc_profile,
                 const base::FilePath& chord_profile,
                 const base::ScopedTempDir& temp,
                 ArcData& data) {
  sql::Database db(sql::DatabaseOptions(), "FirefoxImporter");
  if (!OpenCopy(arc_profile.Append("History"), temp, db)) {
    return;
  }
  // Newer than the last import, within Chromium's 90 days.
  int64_t since = (base::Time::Now() - kHistoryKept)
                      .ToDeltaSinceWindowsEpoch()
                      .InMicroseconds();
  std::string imported;
  int64_t last_import = 0;
  if (base::ReadFileToString(chord_profile.Append(kHistoryImported),
                             &imported) &&
      base::StringToInt64(base::TrimWhitespaceASCII(imported, base::TRIM_ALL),
                          &last_import)) {
    since = std::max(since, last_import);
  }
  sql::Statement statement(db.GetUniqueStatement(
      "SELECT url, title, visit_count, typed_count, last_visit_time, hidden "
      "FROM urls WHERE last_visit_time > ?"));
  statement.BindInt64(0, since);
  while (statement.Step()) {
    GURL url(statement.ColumnString(0));
    if (!url.is_valid() || !url.SchemeIsHTTPOrHTTPS()) {
      continue;
    }
    history::URLRow row(url);
    row.set_title(statement.ColumnString16(1));
    row.set_visit_count(statement.ColumnInt(2));
    row.set_typed_count(statement.ColumnInt(3));
    row.set_last_visit(FromChromiumTime(statement.ColumnInt64(4)));
    row.set_hidden(statement.ColumnBool(5));
    data.newest_page = std::max(data.newest_page, row.last_visit());
    data.pages.push_back(std::move(row));
  }
}

// Arc's extensions installed from the Chrome Web Store (Arc's own and Chromium's
// built-in ones stay behind), from its preferences.
void ReadExtensions(const base::FilePath& arc_profile, ArcData& data) {
  for (const char* file : {"Secure Preferences", "Preferences"}) {
    std::string json;
    if (!base::ReadFileToString(arc_profile.Append(file), &json)) {
      continue;
    }
    std::optional<base::DictValue> preferences =
        base::JSONReader::ReadDict(json, base::JSON_PARSE_RFC);
    const base::DictValue* settings =
        preferences ? preferences->FindDictByDottedPath("extensions.settings")
                    : nullptr;
    if (!settings) {
      continue;
    }
    for (const auto [id, value] : *settings) {
      const base::DictValue* extension = value.GetIfDict();
      if (!extension || extension->FindBool("from_webstore") != true ||
          extension->FindInt("location") !=
              static_cast<int>(extensions::mojom::ManifestLocation::kInternal) ||
          std::ranges::find(data.extensions, id) != data.extensions.end()) {
        continue;
      }
      data.extensions.push_back(id);
    }
  }
}

// Blocking: on a pool thread.
std::unique_ptr<ArcData> ReadArcProfile(const base::FilePath& arc_profile,
                                        const base::FilePath& chord_profile) {
  auto data = std::make_unique<ArcData>();
  base::ScopedTempDir temp;
  if (!temp.CreateUniqueTempDir()) {
    return data;
  }
  std::optional<std::vector<uint8_t>> key = ArcKey();
  if (key) {
    ReadCookies(arc_profile, temp, *key, *data);
    ReadPasswords(arc_profile, temp, *key, *data);
  } else {
    data->key_denied = true;
  }
  ReadHistory(arc_profile, chord_profile, temp, *data);
  ReadExtensions(arc_profile, *data);
  data->site_storage =
      base::PathExists(arc_profile.Append("Local Storage")) ||
      base::PathExists(arc_profile.Append("IndexedDB"));
  return data;
}

// Arc's passwords that this profile does not have yet: Chromium's store would replace
// a password saved since in Chord with Arc's older one. Deletes itself when done.
class NewPasswordsAdder : public password_manager::PasswordStoreConsumer {
 public:
  NewPasswordsAdder(
      scoped_refptr<password_manager::PasswordStoreInterface> store,
      std::vector<password_manager::StoredCredential> passwords,
      base::OnceCallback<void(int)> done)
      : store_(std::move(store)),
        passwords_(std::move(passwords)),
        done_(std::move(done)) {
    store_->GetAllLogins(weak_factory_.GetWeakPtr());
  }

  // password_manager::PasswordStoreConsumer:
  void OnGetPasswordStoreResultsOrErrorFrom(
      password_manager::PasswordStoreInterface* store,
      base::expected<std::vector<password_manager::StoredCredential>,
                     password_manager::PasswordStoreBackendError> results)
      override {
    using Key = std::tuple<std::string, std::string, std::u16string,
                           std::u16string, std::u16string>;
    auto key = [](const password_manager::StoredCredential& credential) {
      return Key(credential.signon_realm, credential.url.spec(),
                 credential.username_element, credential.username_value,
                 credential.password_element);
    };
    std::set<Key> existing;
    if (results.has_value()) {
      for (const auto& credential : *results) {
        existing.insert(key(credential));
      }
    }
    std::vector<password_manager::StoredCredential> added;
    for (auto& credential : passwords_) {
      if (!existing.contains(key(credential))) {
        added.push_back(std::move(credential));
      }
    }
    int count = added.size();
    if (!added.empty()) {
      store_->AddLogins(std::move(added));
    }
    std::move(done_).Run(count);
    delete this;
  }

 private:
  ~NewPasswordsAdder() override = default;

  scoped_refptr<password_manager::PasswordStoreInterface> store_;
  std::vector<password_manager::StoredCredential> passwords_;
  base::OnceCallback<void(int)> done_;
  base::WeakPtrFactory<NewPasswordsAdder> weak_factory_{this};
};

// Arc's cookies that this profile does not have yet (a login made since in Chord
// stays), through the cookie manager, which encrypts them with Chord's key.
void AddNewCookies(network::mojom::CookieManager* cookie_manager,
                   std::vector<net::CanonicalCookie> cookies,
                   base::OnceCallback<void(int)> done) {
  cookie_manager->GetAllCookies(base::BindOnce(
      [](network::mojom::CookieManager* cookie_manager,
         std::vector<net::CanonicalCookie> cookies,
         base::OnceCallback<void(int)> done,
         const std::vector<net::CanonicalCookie>& current) {
        std::set<net::CanonicalCookie> existing(current.begin(),
                                                current.end());
        std::vector<net::CanonicalCookie> added;
        for (auto& cookie : cookies) {
          if (!existing.contains(cookie)) {
            added.push_back(std::move(cookie));
          }
        }
        if (added.empty()) {
          std::move(done).Run(0);
          return;
        }
        auto accepted = base::MakeRefCounted<base::RefCountedData<int>>(0);
        base::RepeatingClosure finished = base::BarrierClosure(
            added.size(),
            base::BindOnce(
                [](scoped_refptr<base::RefCountedData<int>> accepted,
                   base::OnceCallback<void(int)> done) {
                  std::move(done).Run(accepted->data);
                },
                accepted, std::move(done)));
        for (const net::CanonicalCookie& cookie : added) {
          std::string host = cookie.Domain();
          if (base::StartsWith(host, ".")) {
            host = host.substr(1);
          }
          GURL source((cookie.SecureAttribute() ? "https://" : "http://") +
                      host + cookie.Path());
          cookie_manager->SetCanonicalCookie(
              cookie, source, net::CookieOptions::MakeAllInclusive(),
              base::BindOnce(
                  [](scoped_refptr<base::RefCountedData<int>> accepted,
                     base::RepeatingClosure finished,
                     net::CookieAccessResult result) {
                    if (result.status.IsInclude()) {
                      accepted->data++;
                    }
                    finished.Run();
                  },
                  accepted, finished));
        }
      },
      // The manager belongs to the profile's storage partition, which outlives
      // this import.
      base::Unretained(cookie_manager), std::move(cookies), std::move(done)));
}

// One extension from the Chrome Web Store, its CRX checked as Chrome checks it
// (the store's signature, the expected id). Silent: the user had accepted it and its
// permissions in Arc. Chromium's own store download is off in ungoogled-chromium,
// hence the download here. Deletes itself when done.
class StoreExtensionInstaller {
 public:
  static void Install(Profile* profile,
                      std::string id,
                      base::OnceCallback<void(bool)> done) {
    new StoreExtensionInstaller(profile, std::move(id), std::move(done));
  }

 private:
  StoreExtensionInstaller(Profile* profile,
                          std::string id,
                          base::OnceCallback<void(bool)> done)
      : profile_(profile->GetWeakPtr()),
        id_(std::move(id)),
        done_(std::move(done)) {
    auto request = std::make_unique<network::ResourceRequest>();
    request->url = GURL(
        "https://clients2.google.com/service/update2/crx?response=redirect"
        "&acceptformat=crx3&prodversion=" +
        std::string(version_info::GetVersionNumber()) + "&x=id%3D" + id_ +
        "%26installsource%3Dondemand%26uc");
    request->credentials_mode = network::mojom::CredentialsMode::kOmit;
    loader_ = network::SimpleURLLoader::Create(std::move(request),
                                               kTrafficAnnotation);
    loader_->DownloadToTempFile(
        profile->GetDefaultStoragePartition()
            ->GetURLLoaderFactoryForBrowserProcess()
            .get(),
        base::BindOnce(&StoreExtensionInstaller::Downloaded,
                       base::Unretained(this)));
  }

  void Downloaded(base::FilePath crx) {
    Profile* profile = profile_.get();
    if (crx.empty() || !profile) {
      Finish(false);
      return;
    }
    scoped_refptr<extensions::CrxInstaller> installer =
        extensions::CrxInstaller::CreateSilent(profile);
    installer->set_expected_id(id_);
    installer->set_is_gallery_install(true);
    installer->set_install_source(
        extensions::mojom::ManifestLocation::kInternal);
    installer->set_allow_silent_install(true);
    installer->set_grant_permissions(true);
    installer->set_delete_source(true);
    installer->AddInstallerCallback(base::BindOnce(
        [](StoreExtensionInstaller* self,
           const std::optional<extensions::CrxInstallError>& error) {
          self->Finish(!error.has_value());
        },
        base::Unretained(this)));
    installer->InstallCrxFile(extensions::CRXFileInfo(
        crx, crx_file::VerifierFormat::CRX3_WITH_PUBLISHER_PROOF));
  }

  void Finish(bool installed) {
    std::move(done_).Run(installed);
    delete this;
  }

  base::WeakPtr<Profile> profile_;
  const std::string id_;
  base::OnceCallback<void(bool)> done_;
  std::unique_ptr<network::SimpleURLLoader> loader_;
};

void ApplyArcData(base::WeakPtr<Profile> weak_profile,
                  base::FilePath arc_profile,
                  base::OnceCallback<void(ArcImportCounts)> done,
                  std::unique_ptr<ArcData> data) {
  Profile* profile = weak_profile.get();
  auto counts = base::MakeRefCounted<base::RefCountedData<ArcImportCounts>>();
  counts->data.key_denied = data->key_denied;
  if (!profile) {
    std::move(done).Run(counts->data);
    return;
  }

  if (history::HistoryService* history = HistoryServiceFactory::GetForProfile(
          profile, ServiceAccessType::EXPLICIT_ACCESS);
      history && !data->pages.empty()) {
    counts->data.pages = data->pages.size();
    history->AddPagesWithDetails(data->pages, history::SOURCE_BROWSED);
    base::ThreadPool::PostTask(
        FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
        base::BindOnce(
            [](base::FilePath file, int64_t newest) {
              base::WriteFile(file, base::NumberToString(newest));
            },
            profile->GetPath().Append(kHistoryImported),
            data->newest_page.ToDeltaSinceWindowsEpoch().InMicroseconds()));
  }

  counts->data.site_storage = data->site_storage;

  // Passwords and cookies are added once the profile's own are known; extensions
  // once downloaded. Then the site storage and the new extensions' data wait for
  // the next launch.
  auto installed =
      base::MakeRefCounted<base::RefCountedData<std::vector<std::string>>>();
  base::RepeatingClosure finished = base::BarrierClosure(
      3,
      base::BindOnce(
          [](scoped_refptr<base::RefCountedData<ArcImportCounts>> counts,
             scoped_refptr<base::RefCountedData<std::vector<std::string>>>
                 installed,
             base::FilePath marker, base::FilePath arc_profile,
             base::OnceCallback<void(ArcImportCounts)> done) {
            counts->data.extensions = installed->data.size();
            if (counts->data.site_storage || !installed->data.empty()) {
              base::ListValue extensions;
              for (const std::string& id : installed->data) {
                extensions.Append(id);
              }
              std::optional<std::string> json =
                  base::WriteJson(base::DictValue()
                                      .Set("arc", arc_profile.value())
                                      .Set("extensions", std::move(extensions)));
              base::ThreadPool::PostTask(
                  FROM_HERE,
                  {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
                  base::BindOnce(
                      [](base::FilePath marker, std::string json) {
                        base::WriteFile(marker, json);
                      },
                      marker, json.value_or("")));
            }
            std::move(done).Run(counts->data);
          },
          counts, installed, profile->GetPath().Append(kPendingSiteStorage),
          arc_profile, std::move(done)));

  // The extensions this profile does not have yet.
  std::vector<std::string> missing;
  extensions::ExtensionRegistry* registry =
      extensions::ExtensionRegistry::Get(profile);
  for (const std::string& id : data->extensions) {
    if (!registry->GetInstalledExtension(id)) {
      missing.push_back(id);
    }
  }
  if (missing.empty()) {
    finished.Run();
  } else {
    base::RepeatingClosure all_installed =
        base::BarrierClosure(missing.size(), finished);
    for (const std::string& id : missing) {
      StoreExtensionInstaller::Install(
          profile, id,
          base::BindOnce(
              [](scoped_refptr<
                     base::RefCountedData<std::vector<std::string>>> installed,
                 std::string id, base::RepeatingClosure all_installed,
                 bool ok) {
                if (ok) {
                  installed->data.push_back(id);
                }
                all_installed.Run();
              },
              installed, id, all_installed));
    }
  }

  scoped_refptr<password_manager::PasswordStoreInterface> store =
      ProfilePasswordStoreFactory::GetForProfile(
          profile, ServiceAccessType::EXPLICIT_ACCESS);
  if (store && !data->passwords.empty()) {
    new NewPasswordsAdder(
        std::move(store), std::move(data->passwords),
        base::BindOnce(
            [](scoped_refptr<base::RefCountedData<ArcImportCounts>> counts,
               base::RepeatingClosure finished, int added) {
              counts->data.passwords = added;
              finished.Run();
            },
            counts, finished));
  } else {
    finished.Run();
  }

  network::mojom::CookieManager* cookie_manager =
      profile->GetDefaultStoragePartition()
          ->GetCookieManagerForBrowserProcess();
  if (cookie_manager && !data->cookies.empty()) {
    AddNewCookies(
        cookie_manager, std::move(data->cookies),
        base::BindOnce(
            [](scoped_refptr<base::RefCountedData<ArcImportCounts>> counts,
               base::RepeatingClosure finished, int added) {
              counts->data.cookies = added;
              finished.Run();
            },
            counts, finished));
  } else {
    finished.Run();
  }
}

// Arc's Local Storage keys that this profile does not have yet, for web sites; for
// the extensions the import just installed, Arc's keys replace theirs.
void MergeLocalStorage(const base::FilePath& arc_leveldb,
                       const base::FilePath& chord_leveldb,
                       const std::set<std::string>& new_extensions) {
  base::ScopedTempDir temp;
  if (!base::PathExists(arc_leveldb) || !temp.CreateUniqueTempDir()) {
    return;
  }
  // A copy, without Arc's lock.
  base::FilePath copy = temp.GetPath().Append("leveldb");
  if (!base::CopyDirectory(arc_leveldb, copy, /*recursive=*/true)) {
    return;
  }
  base::DeleteFile(copy.Append("LOCK"));
  base::CreateDirectory(chord_leveldb);

  leveldb::Options options;
  leveldb::DB* raw = nullptr;
  if (!leveldb::DB::Open(options, copy.value(), &raw).ok()) {
    return;
  }
  std::unique_ptr<leveldb::DB> from(raw);
  options.create_if_missing = true;
  raw = nullptr;
  if (!leveldb::DB::Open(options, chord_leveldb.value(), &raw).ok()) {
    return;
  }
  std::unique_ptr<leveldb::DB> to(raw);

  leveldb::WriteBatch batch;
  std::unique_ptr<leveldb::Iterator> it(from->NewIterator({}));
  std::string existing;
  for (it->SeekToFirst(); it->Valid(); it->Next()) {
    std::string key = it->key().ToString();
    static constexpr char kExtensionScheme[] = "chrome-extension://";
    size_t extension = key.find(kExtensionScheme);
    if (extension != std::string::npos) {
      std::string id =
          key.substr(extension + sizeof(kExtensionScheme) - 1, 32);
      if (new_extensions.contains(id)) {
        batch.Put(it->key(), it->value());
      }
      continue;
    }
    if (to->Get({}, it->key(), &existing).IsNotFound()) {
      batch.Put(it->key(), it->value());
    }
  }
  to->Write({}, &batch);
}

// Arc's IndexedDB databases of web sites that this profile has none of.
void MergeIndexedDB(const base::FilePath& arc_indexed_db,
                    const base::FilePath& chord_indexed_db) {
  if (!base::PathExists(arc_indexed_db)) {
    return;
  }
  base::CreateDirectory(chord_indexed_db);
  base::FileEnumerator origins(arc_indexed_db, /*recursive=*/false,
                               base::FileEnumerator::DIRECTORIES);
  for (base::FilePath origin = origins.Next(); !origin.empty();
       origin = origins.Next()) {
    std::string name = origin.BaseName().value();
    base::FilePath target = chord_indexed_db.Append(name);
    if (!base::StartsWith(name, "http") || base::PathExists(target)) {
      continue;
    }
    base::CopyDirectory(origin, target, /*recursive=*/true);
  }
}

// What an extension the import just installed kept in Arc (Bitwarden keeps its
// session there) replaces the little it wrote since in Chord.
void ReplaceExtensionData(const base::FilePath& arc,
                          const base::FilePath& profile,
                          const std::string& id) {
  for (const char* folder :
       {"Local Extension Settings", "Sync Extension Settings"}) {
    base::FilePath from = arc.Append(folder).Append(id);
    if (!base::PathExists(from)) {
      continue;
    }
    base::FilePath to = profile.Append(folder).Append(id);
    base::DeletePathRecursively(to);
    base::CreateDirectory(to.DirName());
    if (base::CopyDirectory(from, to, /*recursive=*/true)) {
      base::DeleteFile(to.Append("LOCK"));
    }
  }
  base::FilePath arc_indexed_db = arc.Append("IndexedDB");
  if (!base::PathExists(arc_indexed_db)) {
    return;
  }
  base::CreateDirectory(profile.Append("IndexedDB"));
  base::FileEnumerator databases(arc_indexed_db, /*recursive=*/false,
                                 base::FileEnumerator::DIRECTORIES);
  for (base::FilePath from = databases.Next(); !from.empty();
       from = databases.Next()) {
    std::string name = from.BaseName().value();
    if (!base::StartsWith(name, "chrome-extension_" + id + "_")) {
      continue;
    }
    base::FilePath to = profile.Append("IndexedDB").Append(name);
    base::DeletePathRecursively(to);
    base::CopyDirectory(from, to, /*recursive=*/true);
  }
}

}  // namespace

void ImportArcProfile(Profile* profile,
                      const base::FilePath& arc_profile,
                      base::OnceCallback<void(ArcImportCounts)> done) {
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
      base::BindOnce(&ReadArcProfile, arc_profile, profile->GetPath()),
      base::BindOnce(&ApplyArcData, profile->GetWeakPtr(), arc_profile,
                     std::move(done)));
}

void MergePendingArcSiteStorage(const base::FilePath& user_data_dir) {
  base::FileEnumerator profiles(user_data_dir, /*recursive=*/false,
                                base::FileEnumerator::DIRECTORIES);
  for (base::FilePath profile = profiles.Next(); !profile.empty();
       profile = profiles.Next()) {
    base::FilePath marker = profile.Append(kPendingSiteStorage);
    std::string contents;
    if (!base::ReadFileToString(marker, &contents)) {
      continue;
    }
    base::DeleteFile(marker);
    // JSON, or, from the first version, Arc's folder alone.
    std::optional<base::DictValue> pending =
        base::JSONReader::ReadDict(contents, base::JSON_PARSE_RFC);
    const std::string* arc_profile = pending ? pending->FindString("arc") : nullptr;
    base::FilePath arc(arc_profile ? *arc_profile : contents);
    std::set<std::string> new_extensions;
    if (const base::ListValue* ids =
            pending ? pending->FindList("extensions") : nullptr) {
      for (const base::Value& id : *ids) {
        if (id.is_string()) {
          new_extensions.insert(id.GetString());
        }
      }
    }
    MergeLocalStorage(arc.Append("Local Storage").Append("leveldb"),
                      profile.Append("Local Storage").Append("leveldb"),
                      new_extensions);
    MergeIndexedDB(arc.Append("IndexedDB"), profile.Append("IndexedDB"));
    for (const std::string& id : new_extensions) {
      ReplaceExtensionData(arc, profile, id);
    }
  }
}

}  // namespace chord
