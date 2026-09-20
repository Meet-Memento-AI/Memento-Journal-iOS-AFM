import XCTest
@testable import MeetMemento

/// In-memory keychain so encryption tests never touch the real Keychain
/// (unit tests don't have the entitlements for it anyway) and each test
/// gets an isolated store.
final class InMemoryKeychainStore: KeychainStoring {
    private var storage: [String: Data] = [:]

    func data(forAccount account: String) -> Data? {
        storage[account]
    }

    @discardableResult
    func save(_ data: Data, forAccount account: String) -> Bool {
        storage[account] = data
        return true
    }

    func delete(forAccount account: String) {
        storage.removeValue(forKey: account)
    }
}

final class EncryptionServiceTests: XCTestCase {
    private func makeService() -> EncryptionService {
        EncryptionService(keychain: InMemoryKeychainStore())
    }

    func test_encryptThenDecrypt_returnsOriginalPlaintext() {
        let service = makeService()
        let cases = ["", "hello", "😀🔥 emoji test", String(repeating: "a very long journal entry. ", count: 200)]

        for plaintext in cases {
            let encrypted = service.encrypt(plaintext, withPIN: "1234")
            XCTAssertNotNil(encrypted, "encryption should succeed for: \(plaintext.prefix(20))")

            let decrypted = encrypted.flatMap { service.decrypt($0, withPIN: "1234") }
            XCTAssertEqual(decrypted, plaintext)
        }
    }

    func test_decryptWithWrongPIN_fails() {
        let service = makeService()
        guard let encrypted = service.encrypt("secret content", withPIN: "1234") else {
            return XCTFail("encryption should succeed")
        }

        XCTAssertNil(service.decrypt(encrypted, withPIN: "9999"))
    }

    func test_validatePIN_trueForCorrectPIN_falseForWrong() {
        let service = makeService()
        guard let encrypted = service.encrypt("content", withPIN: "1234") else {
            return XCTFail("encryption should succeed")
        }

        XCTAssertTrue(service.validatePIN("1234", against: encrypted))
        XCTAssertFalse(service.validatePIN("0000", against: encrypted))
    }

    func test_saltPersistsAcrossCalls_viaKeychainMock() {
        let keychain = InMemoryKeychainStore()
        let service = EncryptionService(keychain: keychain)

        // Deriving twice with the same PIN must use the same persisted salt,
        // producing the same ciphertext-decryptability — i.e. a value
        // encrypted by one call must decrypt via a key derived by another.
        guard let encrypted = service.encrypt("stable content", withPIN: "1234") else {
            return XCTFail("encryption should succeed")
        }
        XCTAssertEqual(service.decrypt(encrypted, withPIN: "1234"), "stable content")

        // A fresh EncryptionService instance sharing the same keychain store
        // (simulating a relaunch) must read the persisted salt, not
        // generate a new one, or the same PIN would fail to decrypt.
        let relaunchedService = EncryptionService(keychain: keychain)
        XCTAssertEqual(relaunchedService.decrypt(encrypted, withPIN: "1234"), "stable content")
    }

    func test_deriveKey_isDeterministicForSamePINAndSalt() {
        let service = makeService()
        let key1 = service.deriveKey(from: "1234")
        let key2 = service.deriveKey(from: "1234")

        XCTAssertNotNil(key1)
        XCTAssertEqual(key1, key2)
    }

    func test_deriveKey_differsForDifferentPINs() {
        let service = makeService()
        let key1 = service.deriveKey(from: "1234")
        let key2 = service.deriveKey(from: "5678")

        XCTAssertNotEqual(key1, key2)
    }

    func test_deleteSalt_thenReEncrypt_rotatesSaltSoOldCiphertextNoLongerDecrypts() {
        let keychain = InMemoryKeychainStore()
        let service = EncryptionService(keychain: keychain)

        guard let encrypted = service.encrypt("content", withPIN: "1234") else {
            return XCTFail("encryption should succeed")
        }
        service.deleteSalt()

        // A new salt gets generated on next use, so the old ciphertext
        // (sealed under the old salt-derived key) must no longer decrypt.
        XCTAssertNil(service.decrypt(encrypted, withPIN: "1234"))
    }
}
