//
//  SyncStatusStore.swift
//  MeetMemento
//
//  Spec 015 R2 / 040: passive CloudKit status. Never blocks capture.
//

import CloudKit
import Foundation
import SwiftUI

enum CloudKitSyncStatus: Equatable {
    case available
    case signedOut
    case quotaExceeded
    case offline
    case pendingDeletion
}

@MainActor
final class SyncStatusStore: ObservableObject {
    static let shared = SyncStatusStore()
    private static let pendingDeletionKey = "memento_cloudkit_deletion_pending"

    @Published private(set) var status: CloudKitSyncStatus = .available
    @Published var deletionPending = UserDefaults.standard.bool(forKey: SyncStatusStore.pendingDeletionKey)

    func markDeletionPending() {
        deletionPending = true
        UserDefaults.standard.set(true, forKey: Self.pendingDeletionKey)
    }

    func clearDeletionPending() {
        deletionPending = false
        UserDefaults.standard.removeObject(forKey: Self.pendingDeletionKey)
    }

    var banner: String? {
        if deletionPending {
            return "Deleted locally, iCloud pending."
        }
        switch status {
        case .available, .offline:
            return nil
        case .signedOut:
            return DeviceCopy.signedOutSync
        case .quotaExceeded:
            return DeviceCopy.quotaExceeded
        case .pendingDeletion:
            return "Deleted locally, iCloud pending."
        }
    }

    func refresh() async {
        do {
            let account = try await CKContainer(identifier: JournalSchema.cloudKitContainerID).accountStatus()
            switch account {
            case .available:
                status = .available
            case .noAccount, .restricted, .couldNotDetermine, .temporarilyUnavailable:
                status = .signedOut
            @unknown default:
                status = .signedOut
            }
        } catch let error as CKError where error.code == .quotaExceeded {
            status = .quotaExceeded
        } catch {
            status = .offline
        }
    }
}
