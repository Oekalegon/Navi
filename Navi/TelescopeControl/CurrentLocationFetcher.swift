//
//  CurrentLocationFetcher.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.1.
//

import CoreLocation

/// Fetches the user's current location once, via a single `CLLocationManager` request — backs
/// the toolbar's "Current Location" quick-create entry (§4.1): visible/enabled only when
/// Location Services access is available, never an error on tap if it isn't (callers should check
/// `isAvailable` before offering this at all).
///
/// `@MainActor` since `CLLocationManagerDelegate` callbacks aren't guaranteed to arrive on any
/// particular thread — each is `nonisolated` and hops back via `Task { @MainActor in ... }`,
/// matching the pattern already used for `TelescopeSessionManager`'s own async callback handling.
@MainActor
final class CurrentLocationFetcher: NSObject, CLLocationManagerDelegate {
    enum FetchError: Error, CustomStringConvertible {
        case authorizationDenied
        case noLocationReturned

        var description: String {
            switch self {
            case .authorizationDenied: return "Location access was denied."
            case .noLocationReturned: return "Couldn't determine your current location."
            }
        }
    }

    static var isAvailable: Bool { CLLocationManager.locationServicesEnabled() }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var isWaitingForAuthorization = false

    override init() {
        super.init()
        manager.delegate = self
    }

    /// Requests location permission if needed, then one location fix.
    func requestCurrentLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                isWaitingForAuthorization = true
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                continuation.resume(throwing: FetchError.authorizationDenied)
                self.continuation = nil
            default:
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard isWaitingForAuthorization else { return }
            switch manager.authorizationStatus {
            case .notDetermined:
                return
            case .denied, .restricted:
                isWaitingForAuthorization = false
                continuation?.resume(throwing: FetchError.authorizationDenied)
                continuation = nil
            default:
                isWaitingForAuthorization = false
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let location = locations.last {
                continuation?.resume(returning: location)
            } else {
                continuation?.resume(throwing: FetchError.noLocationReturned)
            }
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
