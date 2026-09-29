# 15 — App encryption documentation

**Compiled 2026-09-24** against `373ea9b`. This is the answer to App Store
Connect's *App Encryption Documentation* panel, and the evidence behind it.

`05-age-rating-and-declarations.md` §3 remains the authority on the *declaration*.
This file is the **algorithm inventory** that §3's conclusion rests on — the thing
to hand over if Apple or BIS ever asks what the app actually contains. Where the
two disagree, `05` wins and this file is stale.

> This is an engineering evidence record, not legal advice. The export
> classification is a determination for the account holder to make or to take to
> counsel; everything below is the factual basis they need in order to make it.

---

## 1. The determination

**No documentation upload is required, and `ITSAppUsesNonExemptEncryption`
stays `false`.**

App Store Connect asks for documentation when an app contains either of two
things. Neither is present:

| Apple's trigger | Memento | Basis |
|---|---|---|
| Encryption algorithms that are **proprietary** or not accepted as standard by IEEE/IETF/ITU | **Absent** | Every primitive is a published standard: AES-GCM (NIST SP 800-38D), PBKDF2 (RFC 8018), HMAC-SHA-256 (FIPS 198-1/180-4). Nothing bespoke. |
| Standard algorithms **instead of, or in addition to,** using or accessing the encryption within Apple's operating system | **Absent** | Every call is into Apple's own OS frameworks — `CryptoKit`, `CommonCrypto`, `Security`/Keychain. The binary bundles **no** crypto implementation of its own and **no** third-party crypto library. |

The distinction that carries the determination: the app *invokes* encryption for
its own purposes, but it invokes **Apple's**. "In addition to" in Apple's
sentence targets an app shipping its own implementation — a bundled OpenSSL,
libsodium, BoringSSL, CryptoSwift — alongside the OS. Memento links none.

**Verified absent**, 2026-09-24:

```
$ grep -rn 'CryptoSwift\|OpenSSL\|libsodium\|BoringSSL\|Sodium\|TweetNacl' \
    --include='*.swift' --include='*.resolved' --include='*.pbxproj' .
(no matches)
```

The only resolved Swift package is `SupertonicTTS`, local, and no
`Package.resolved` pins a remote dependency.

---

## 2. Algorithm inventory

Everything in the app target that touches cryptography. This is the documentation.

| Purpose | Algorithm | Parameters | API (Apple OS) | Site |
|---|---|---|---|---|
| Journal content at rest | **AES-256-GCM** | 256-bit key, random nonce per seal, combined box | `CryptoKit` `AES.GCM.seal` / `.open` | `EncryptionService.swift:139,160,171,199,284` |
| Data-encryption key (DEK) generation | CSPRNG | 32 bytes (256-bit) | `Security` `SecRandomCopyBytes` | `EncryptionService.swift:118` |
| DEK storage | — (storage, not encryption) | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | `Security` Keychain | `KeychainStoring.swift:52` |
| Salt generation | CSPRNG | 32 bytes (256-bit) | `SecRandomCopyBytes` | `EncryptionService.swift:322` |
| **Legacy** PIN→key derivation, read path only | **PBKDF2-HMAC-SHA-256** | 100,000 iterations, 256-bit salt, 256-bit output | `CommonCrypto` `CCKeyDerivationPBKDF` | `EncryptionService.swift:243–252` |
| App-access gate (biometric/passcode) | — (authentication, not encryption) | — | `LocalAuthentication` | `SecurityService.swift`, `LockScreenView.swift` |
| Content addressing / dedup — **not confidentiality** | SHA-256 digest | — | `CryptoKit` `SHA256` | `SampleContentService.swift:82`, `PassageDownrank.swift:38`, `AskTranscriptPlan.swift:130` |

**Key management.** The DEK is generated once from the system CSPRNG, stored in
the Keychain as `WhenUnlockedThisDeviceOnly`, and never rotated. The PIN is
purely an access gate and is not a key. Journal content that is mirrored through
SwiftData/CloudKit is deliberately **not** wrapped in the DEK — a
ThisDeviceOnly key cannot decrypt on a second device — and relies on Apple's own
protection instead (`@Attribute(.allowsCloudEncryption)`,
`JournalSchema.swift:63`, plus `.completeFileProtection` on every local write).
The PBKDF2 path exists solely to read pre-migration content and must not be used
for new writes; see the header of `EncryptionService.swift`.

**Three SHA-256 sites are digests, not encryption.** They produce stable
identifiers and de-duplicate retrieved passages. A hash is one-way and protects
no confidentiality; it is listed for completeness so the inventory is exhaustive
rather than selective.

---

## 3. Transport

All network egress is HTTPS, and there is exactly one client.

- `NSAppTransportSecurity` → `NSAllowsArbitraryLoads = false` (`Info.plist`).
  No ATS exception of any kind is declared.
- One `URLSession` in the app target: `SupabaseFeedbackClient.swift` (spec 042,
  the opt-in answer-feedback sync). No other file references `URLSession`.
- No cleartext endpoint appears in source:

```
$ grep -rno 'http://[a-zA-Z0-9./_-]*' --include='*.swift' withMemento/ \
    | grep -v 'w3.org\|localhost\|127.0.0.1'
(no matches)
```

**One precision worth recording**, because a future session will otherwise
assume more than the code does: `SupabaseFeedbackClient` validates that its
endpoint has a scheme and a non-empty host
(`SupabaseFeedbackClient.swift:45`) — it does **not** itself require `https`.
Cleartext is blocked by **ATS at the OS level**, not by the client. The
conclusion is the same; the mechanism is the OS, which is the point for
exemption purposes. If ATS were ever relaxed, this row changes.

TLS itself is the OS stack. The app neither implements nor configures it.

---

## 4. What to enter in App Store Connect

| Question | Answer |
|---|---|
| Does your app use encryption? | **Yes** — answer yes even though it is all OS-provided; "no" is for apps with none at all. |
| Does it qualify for any Category 5 Part 2 exemption? | **Yes** |
| Which exemption? | **Only uses or accesses encryption available within Apple's operating system** |
| Upload documentation? | **Not required** — §1 |
| `ITSEncryptionExportComplianceCode` | **None.** Do not add the key; there is no CCATS. |

Because `ITSAppUsesNonExemptEncryption = false` ships in the binary, the
export-compliance prompt should not appear on upload at all. **If App Store
Connect is still asking, the cause is almost always the build, not the answer** —
check in this order:

1. The key is in the **uploaded** build's `Info.plist`, not only in the repo.
   `scripts/ci/check_store_metadata.sh` asserts its presence; `07` §205 records
   that this is exactly what removes the prompt.
2. The panel is informational and attached to an **older** build that predates
   the key.
3. A previously-submitted version had it missing, and the answer is remembered
   per version rather than per app.

Verify the shipped value from the archive rather than the repo:

```
$ plutil -extract ITSAppUsesNonExemptEncryption xml1 -o - \
    "<Memento.xcarchive>/Products/Applications/withMemento.app/Info.plist"
```

---

## 5. Residuals — neither is a submission blocker

**France.** A French encryption declaration is owed when an app supplies
cryptographic functionality *not* provided by the OS. Memento supplies none, so
no declaration. This is the row that flips if a dependency ever bundles crypto.

**BIS annual self-classification report.** An app relying on an exemption may
still owe a year-end self-classification report to the US Bureau of Industry and
Security, due **1 February** for the prior calendar year. `05` §3 flags this
`[verify]` and that flag stands: Apple's documentation does not unambiguously
state whether an app using only OS-provided encryption is in scope. It is not a
submission gate — check it before the first February after launch. This file's
§2 table is the inventory such a report would draw on.

---

## 6. Guards — what would change the answer

Each of these turns `ITSAppUsesNonExemptEncryption` to `true`, and a change to
that key requires a **new build**, not a metadata edit:

- **A dependency that bundles its own crypto.** The dependency-allowlist gate
  (`specs/021` R6, `scripts/ci/check_dependency_allowlist.sh`) is where this
  gets caught. Today the allowlist holds one local package.
- **Hand-rolling a primitive**, or vendoring one, instead of calling CryptoKit
  or CommonCrypto.
- **Relaxing ATS**, which would move transport security out of the OS.
- **Shipping encryption as a user-facing feature** — an encrypted-export format
  or an end-to-end sync the app keys itself — rather than as internal at-rest
  protection.

A grep that would have caught the omission this file was written to fix:

```
$ grep -rn 'AES\.GCM\|CCKeyDerivationPBKDF\|SymmetricKey' --include='*.swift' withMemento/
```

---

## 7. Two corrections to `05` §3, made 2026-09-24

The determination in `05` §3 was right and is unchanged. Its stated evidence was
wrong in two ways, both found by auditing the code rather than re-reading the doc:

1. **AES-256-GCM was not mentioned at all.** §3 cited only "PBKDF2-SHA256 via
   CommonCrypto and key storage in the Keychain". AES-GCM is the app's *primary*
   content encryption and PBKDF2 is a legacy read-only path — the record named
   the lesser mechanism and omitted the greater one. An auditor reading §3 would
   not have learned that journal content is encrypted with AES-256-GCM.
2. **"there is no `URLSession` in the app at all" is no longer true.** Spec 042
   added `SupabaseFeedbackClient`. Transport is still ATS-only HTTPS, so the
   conclusion survives, but the sentence asserted something stronger than the
   code supports.

Both are the failure mode `00`'s preamble exists to prevent: a row whose
conclusion is correct while its evidence has drifted. Fixed in `05` §3, with
this file as the detail.
