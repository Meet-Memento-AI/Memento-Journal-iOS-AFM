//
//  NetworkMonitor.swift
//  MeetMemento
//
//  Tracks device connectivity so the app can go local-first when offline
//  and trigger a sync the moment connectivity returns (spec-007 R1).
//

import Foundation
import Network

/// Testable seam over connectivity state, so view models can be unit tested
/// without a real `NWPathMonitor`.
@MainActor
protocol NetworkMonitoring: AnyObject {
    var isConnected: Bool { get }
}

@MainActor
final class NetworkMonitor: ObservableObject, NetworkMonitoring {
    static let shared = NetworkMonitor()

    /// Starts optimistic (assumed online) so launch is never blocked waiting
    /// on the first path update.
    @Published private(set) var isConnected: Bool = true

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.meetmemento.networkmonitor")

    init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
