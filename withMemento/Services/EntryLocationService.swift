//
//  EntryLocationService.swift
//  MeetMemento
//
//  Per-entry place name (spec 018 R6 / REQ-CAP-011). One-shot
//  reduced-accuracy Core Location, on-device MapKit reverse geocode, then
//  the CLLocation is dropped. Only a short display string is returned.
//

import CoreLocation
import Foundation
import MapKit
import os

/// Formats a short journal place string. Extracted so tests can pin
/// `Dallas` + `TX` → `Dallas, TX` without hitting Core Location.
enum PlaceNameFormatter {
    /// `locality` + `administrativeArea` → `"Dallas, TX"`. Falls back to
    /// locality alone, then `name`. Empty / whitespace inputs are skipped.
    static func format(
        locality: String?,
        administrativeArea: String?,
        name: String? = nil
    ) -> String? {
        let city = Self.trimmed(locality)
        let region = Self.trimmed(administrativeArea)
        if let city, let region {
            return "\(city), \(region)"
        }
        if let city { return city }
        return Self.trimmed(name)
    }

    static func placeName(from mapItem: MKMapItem) -> String? {
        let representations = mapItem.addressRepresentations
        // `cityWithContext` is already "Dallas, TX" — prefer it over composing.
        if let composed = trimmed(representations?.cityWithContext) {
            return composed
        }
        return format(
            locality: representations?.cityName,
            administrativeArea: nil,
            name: mapItem.name
        )
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// One-shot reduced-accuracy location → short place name. Never persists
/// coordinates; callers keep only the returned string.
final class EntryLocationService: NSObject, CLLocationManagerDelegate {
    static let shared = EntryLocationService()

    enum ResolveError: Error, Equatable {
        /// When-in-use was denied or restricted.
        case denied
        /// System Location Services are off.
        case servicesDisabled
        /// Fix or reverse-geocode failed.
        case failed
    }

    private let manager = CLLocationManager()
    private let inFlight = OSAllocatedUnfairLock<Task<String, Error>?>(initialState: nil)
    private let authWaiter = OSAllocatedUnfairLock<CheckedContinuation<CLAuthorizationStatus, Never>?>(initialState: nil)
    private let locationWaiter = OSAllocatedUnfairLock<CheckedContinuation<CLLocation, Error>?>(initialState: nil)

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        manager.distanceFilter = kCLDistanceFilterNone
    }

    /// Requests when-in-use if needed, takes one reduced-accuracy fix, reverse
    /// geocodes on-device, and returns a short place string. The `CLLocation`
    /// never leaves this method.
    func resolvePlaceName() async throws -> String {
        let task = inFlight.withLock { slot -> Task<String, Error> in
            if let existing = slot { return existing }
            let created = Task { try await self.performResolve() }
            slot = created
            return created
        }

        do {
            let value = try await task.value
            inFlight.withLock { $0 = nil }
            return value
        } catch {
            inFlight.withLock { $0 = nil }
            throw error
        }
    }

    private func performResolve() async throws -> String {
        let status = await resolvedAuthorization()
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .denied, .restricted, .notDetermined:
            throw ResolveError.denied
        @unknown default:
            throw ResolveError.denied
        }

        let servicesOn = await MainActor.run { CLLocationManager.locationServicesEnabled() }
        guard servicesOn else {
            throw ResolveError.servicesDisabled
        }

        let location = try await oneShotLocation()
        return try await reverseGeocode(location)
    }

    // MARK: - Authorization

    private func resolvedAuthorization() async -> CLAuthorizationStatus {
        let current = await MainActor.run { manager.authorizationStatus }
        if current != .notDetermined { return current }

        return await withCheckedContinuation { continuation in
            authWaiter.withLock { $0 = continuation }
            Task { @MainActor in
                self.manager.requestWhenInUseAuthorization()
            }
        }
    }

    // MARK: - One-shot fix

    private func oneShotLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            locationWaiter.withLock { $0 = continuation }
            Task { @MainActor in
                self.manager.requestLocation()
            }
        }
    }

    // MARK: - Reverse geocode

    private func reverseGeocode(_ location: CLLocation) async throws -> String {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            throw ResolveError.failed
        }
        let items = try await request.mapItems
        guard let item = items.first,
              let name = PlaceNameFormatter.placeName(from: item) else {
            throw ResolveError.failed
        }
        return name
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // The first callback after `requestWhenInUseAuthorization` is often
        // still `.notDetermined`. Resuming on that would treat a pending prompt
        // as a denial.
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        let waiter = authWaiter.withLock { slot -> CheckedContinuation<CLAuthorizationStatus, Never>? in
            let taken = slot
            slot = nil
            return taken
        }
        waiter?.resume(returning: status)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let waiter = locationWaiter.withLock { slot -> CheckedContinuation<CLLocation, Error>? in
            let taken = slot
            slot = nil
            return taken
        }
        if let location = locations.last {
            waiter?.resume(returning: location)
        } else {
            waiter?.resume(throwing: ResolveError.failed)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let waiter = locationWaiter.withLock { slot -> CheckedContinuation<CLLocation, Error>? in
            let taken = slot
            slot = nil
            return taken
        }
        waiter?.resume(throwing: error)
    }
}
