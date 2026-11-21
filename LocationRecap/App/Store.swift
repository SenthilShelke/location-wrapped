import SwiftUI
import CoreLocation
import MapKit

struct AppleGeocoder: VisitGeocoder {
    func resolve(latitude: Double, longitude: Double) async throws -> Geography {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        if #available(iOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location), let item = try await request.mapItems.first else { throw CLError(.geocodeFoundNoResult) }
            // regionName is the country, NOT the administrative region. The structured
            // placemark is retained for administrativeArea, absent from MKAddress.
            return Geography(city: item.addressRepresentations?.cityName ?? item.placemark.locality, region: item.placemark.administrativeArea, country: item.addressRepresentations?.regionName ?? item.placemark.country, countryCode: item.placemark.isoCountryCode)
        }
        guard let p = try await CLGeocoder().reverseGeocodeLocation(location).first else { throw CLError(.geocodeFoundNoResult) }
        return Geography(city: p.locality, region: p.administrativeArea, country: p.country, countryCode: p.isoCountryCode)
    }
}
@MainActor final class Store: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var data = Archive()
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var precise = false
    @Published var resolving = false
    @Published var persistenceError: String?
    @Published var geographyStatus = "Not running"
    private let manager = CLLocationManager()
    private let geographyManager = CLLocationManager()
    @Published private(set) var geographySession: UUID?
    private var sampling = false
    private var areaRegion: CLCircularRegion?
    private var areaSampleID: UUID?
    private var lastGeocodeAttempt = Date.distantPast
    private var geographyTask: Task<Void, Never>?
    private let geocoder: any VisitGeocoder
    private let url: URL
    init(geocoder: any VisitGeocoder = AppleGeocoder()) {
        self.geocoder = geocoder
        url = URL.applicationSupportDirectory.appending(path: "LocationRecap/history.json")
        super.init()
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let original = try Data(contentsOf: url)
                data = try JSONDecoder().decode(Archive.self, from: original)
                if (data.repairVersion ?? 0) < 1 {
                    let backup = url.deletingLastPathComponent().appending(path: "history-before-repair-v1.json")
                    if !FileManager.default.fileExists(atPath: backup.path) {
                        try original.write(to: backup, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    }
                    Reconciliation.repair(&data, at: Date())
                }
                if (data.repairVersion ?? 0) < 2 {
                    let backup = url.deletingLastPathComponent().appending(path: "history-before-place-dedupe-v2.json")
                    if !FileManager.default.fileExists(atPath: backup.path) {
                        try original.write(to: backup, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    }
                    PlaceNaming.repair(&data)
                }
                if (data.geographyAreaVersion ?? 0) < 1 {
                    let backup = url.deletingLastPathComponent().appending(path: "history-before-geography-area-v1.json")
                    if !FileManager.default.fileExists(atPath: backup.path) {
                        try original.write(to: backup, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    }
                    GeographyAreaTracking.repair(&data, through: Date())
                }
                // A process restart is not evidence the device stayed stationary.
                for i in (data.stationaryStays ?? []).indices where data.stationaryStays?[i].end == nil {
                    data.stationaryStays?[i].end = data.stationaryStays?[i].confirmed
                }
                persist()
            }
        } catch { persistenceError = "Could not read history: \(error.localizedDescription). Capture is paused to protect the file." }
        manager.delegate = self
        geographyManager.delegate = self
        for region in geographyManager.monitoredRegions where region.identifier.hasPrefix("geography.") {
            geographyManager.stopMonitoring(for: region)
        }
        geographyManager.activityType = .other
        geographyManager.pausesLocationUpdatesAutomatically = true
        geographyManager.allowsBackgroundLocationUpdates = true
        geographyManager.showsBackgroundLocationIndicator = true
        refresh()
    }
    func persist() {
        guard persistenceError == nil else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(data).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { persistenceError = "History could not be saved: \(error.localizedDescription)" }
    }
    func log(_ text: String) {
        data.diagnostics.append("\(Date().formatted()) · \(text)")
        data.diagnostics = Array(data.diagnostics.suffix(200))
        persist()
    }
    func enable() {
        guard persistenceError == nil else { return }
        data.enabled = true
        persist()
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if manager.authorizationStatus == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
        refresh()
    }
    func disable() {
        data.enabled = false
        manager.stopMonitoringVisits()
        stopGeography()
        log("Capture disabled")
    }
    private func finishStationary(at time: Date) {
        for i in (data.stationaryStays ?? []).indices where data.stationaryStays?[i].end == nil {
            if let start = data.stationaryStays?[i].start { data.stationaryStays?[i].end = max(start, time) }
        }
        for region in geographyManager.monitoredRegions where region.identifier.hasPrefix("geography.") {
            geographyManager.stopMonitoring(for: region)
        }
        areaRegion = nil
        areaSampleID = nil
        persist()
    }
    private func stopGeography() {
        finishStationary(at: Date())
        geographyManager.stopUpdatingLocation()
        geographyManager.stopMonitoringSignificantLocationChanges()
        geographySession = nil
        sampling = false
        geographyStatus = "Not running"
    }
    func refresh() {
        authorization = manager.authorizationStatus
        precise = manager.accuracyAuthorization == .fullAccuracy
        if data.enabled && persistenceError == nil && (authorization == .authorizedAlways || authorization == .authorizedWhenInUse) { manager.startMonitoringVisits() }
        guard data.enabled, persistenceError == nil, authorization == .authorizedAlways else { stopGeography(); return }
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        geographyManager.desiredAccuracy = lowPower ? kCLLocationAccuracyKilometer : kCLLocationAccuracyHundredMeters
        geographyManager.distanceFilter = lowPower ? 1000 : 250
        if geographySession == nil {
            geographySession = UUID()
            if data.geographyStartedAt == nil { data.geographyStartedAt = Date(); persist() }
            if CLLocationManager.significantLocationChangeMonitoringAvailable() { geographyManager.startMonitoringSignificantLocationChanges() }
        }
        if !sampling {
            sampling = true
            geographyStatus = lowPower ? "Sampling · Low Power Mode" : "Sampling · 100 m accuracy / 250 m movement"
            geographyManager.startUpdatingLocation()
        }
    }
    private var areaAnchor: GeographySample? {
        data.geographySamples?.first { $0.id == areaSampleID }
    }
    private var canMonitorArea: Bool {
        CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) && geographyManager.maximumRegionMonitoringDistance > 0
    }
    private func registerArea(for sample: GeographySample) {
        guard let session = geographySession, canMonitorArea,
              let desired = GeographyAreaTracking.radius(for: sample, now: Date(), session: session) else { return }
        let radius = min(desired, geographyManager.maximumRegionMonitoringDistance)
        guard radius >= 150 else { return }
        let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude),
                                     radius: radius, identifier: "geography.area.\(sample.id.uuidString)")
        region.notifyOnEntry = true
        region.notifyOnExit = true
        areaRegion = region
        areaSampleID = sample.id
        geographyStatus = "Confirming location area"
        geographyManager.startMonitoring(for: region)
    }
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        guard manager === geographyManager, region.identifier == areaRegion?.identifier else { return }
        geographyManager.requestState(for: region)
    }
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard manager === geographyManager, data.enabled, persistenceError == nil,
              region.identifier == areaRegion?.identifier, let anchor = areaAnchor,
              anchor.session == geographySession else { return }
        switch state {
        case .inside:
            let now = Date()
            if let i = data.stationaryStays?.firstIndex(where: { $0.end == nil && $0.session == anchor.session }) {
                data.stationaryStays?[i].confirmed = now
                persist()
            } else {
                if data.stationaryStays == nil { data.stationaryStays = [] }
                data.stationaryStays?.append(GeographyAreaTracking.confirmInside(sample: anchor, radius: areaRegion!.radius, at: now))
                log("Geography area confirmed inside; estimating time until exit or a location change.")
            }
            geographyStatus = "Location area monitored · includes stationary time"
        case .outside:
            finishStationary(at: Date())
            sampling = true
            geographyManager.startUpdatingLocation()
            geographyStatus = "Sampling after location-area exit"
        case .unknown:
            // An unknown state is not evidence of continued presence.
            let confirmed = data.stationaryStays?.last(where: { $0.end == nil })?.confirmed ?? Date()
            finishStationary(at: confirmed)
            sampling = true
            geographyManager.startUpdatingLocation()
            geographyStatus = "Area state unknown · refreshing location"
            log("Geography area state unknown; estimate ended at last confirmation.")
        @unknown default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        guard manager === geographyManager, areaRegion != nil,
              region == nil || region?.identifier == areaRegion?.identifier else { return }
        let confirmed = data.stationaryStays?.last(where: { $0.end == nil })?.confirmed ?? Date()
        finishStationary(at: confirmed)
        geographyStatus = "Area monitoring unavailable · using location readings"
        log("Geography area monitoring failed: \(error.localizedDescription)")
    }
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        guard manager === geographyManager, geographySession != nil else { return }
        sampling = false
        if let region = areaRegion {
            geographyManager.requestState(for: region)
            geographyStatus = "Location sampling paused · area monitoring remains active"
            log("Geography sampling paused; requesting monitored-area state.")
        } else if let sample = data.geographySamples?.last,
                  let session = geographySession,
                  GeographyAreaTracking.radius(for: sample, now: Date(), session: session) != nil {
            registerArea(for: sample)
        } else {
            geographyStatus = "Paused without area evidence · requesting a fresh location"
            geographyManager.requestLocation()
            log("Geography sampling paused without a fresh area anchor; requesting one location fix.")
        }
    }
    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        guard manager === geographyManager else { return }
        sampling = true
        geographyStatus = "Movement detected · awaiting location fix"
    }
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard manager === geographyManager, region.identifier == areaRegion?.identifier else { return }
        geographyManager.requestState(for: region)
    }
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard manager === geographyManager, region.identifier == areaRegion?.identifier, data.enabled else { return }
        finishStationary(at: Date())
        sampling = true
        geographyManager.startUpdatingLocation()
        geographyStatus = "Sampling after location-area exit"
        log("Geography monitored-area exit received; sampling continues.")
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manager === geographyManager, data.enabled, persistenceError == nil, let session = geographySession else { return }
        if !sampling {
            sampling = true
            geographyManager.startUpdatingLocation()
            geographyStatus = "Sampling resumed after movement"
        }
        let now = Date()
        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard location.horizontalAccuracy >= 0, location.timestamp <= now.addingTimeInterval(10), now.timeIntervalSince(location.timestamp) < 300 else { continue }
            let last = data.geographySamples?.last
            if let last, location.timestamp <= last.timestamp { continue }
            let sample = GeographySample(timestamp: location.timestamp, received: now, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, accuracy: location.horizontalAccuracy, session: session)
            if let anchor = areaAnchor, let region = areaRegion {
                switch GeographyAreaTracking.action(for: sample, anchor: anchor, radius: region.radius) {
                case .keep:
                    if let i = data.stationaryStays?.firstIndex(where: { $0.end == nil && $0.session == session }) {
                        data.stationaryStays?[i].confirmed = max(data.stationaryStays![i].confirmed, sample.timestamp)
                    }
                case .replace: finishStationary(at: sample.timestamp)
                case .wait: break
                }
            }
            // Avoid repeatedly registering areas along a fast-moving route.
            // Unknown speed (-1) can still be confirmed by region-state evidence.
            let needsAnchor = location.speed < 2 && areaRegion == nil && canMonitorArea && GeographyAreaTracking.radius(for: sample, now: now, session: session) != nil
            if let last, last.session == session, sample.timestamp.timeIntervalSince(last.timestamp) < 60, !needsAnchor { continue }
            if data.geographySamples == nil { data.geographySamples = [] }
            data.geographySamples?.append(sample)
            if needsAnchor { registerArea(for: sample) }
        }
        persist()
        if geographyTask == nil {
            geographyTask = Task { [weak self] in
                guard let self else { return }
                await self.resolveUnknown()
                self.geographyTask = nil
            }
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { refresh() }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if manager === geographyManager {
            geographyStatus = areaRegion != nil ? "Location reading unavailable · area monitoring remains active" : "Location unavailable: \(error.localizedDescription)"
        }
        log(error.localizedDescription)
    }
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard manager === self.manager, data.enabled, persistenceError == nil else { return }
        let event = Observation(received: Date(), latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude, accuracy: visit.horizontalAccuracy, arrival: visit.arrivalDate == .distantPast ? nil : visit.arrivalDate, departure: visit.departureDate == .distantFuture ? nil : visit.departureDate, source: "Core Location visit")
        data.observations.append(event)
        Reconciliation.ingest(event, into: &data.visits)
        persist()
        log("Received visit; accuracy \(Int(visit.horizontalAccuracy)) m")
        Task { await resolveUnknown() }
    }
    func resolveUnknown() async {
        guard !resolving else { return }
        resolving = true
        defer { resolving = false }
        let ids = data.visits.filter { $0.geography == nil }.map(\.id)
        for id in ids {
            guard let i = data.visits.firstIndex(where: { $0.id == id }) else { continue }
            let v = data.visits[i]
            // Cache only effectively identical coordinates; don't assume a city's boundary.
            if let cached = data.visits.first(where: { $0.geography != nil && Matching.distance(v.latitude, v.longitude, $0.latitude, $0.longitude) < 10 })?.geography {
                data.visits[i].geography = cached; persist(); continue
            }
            do {
                let geo = try await geocoder.resolve(latitude: v.latitude, longitude: v.longitude)
                data.visits[i].geography = geo
                persist()
                try await Task.sleep(for: .seconds(2))
            } catch { log("Geography unresolved; retry later: \(error.localizedDescription)"); break }
        }
        let pending = (data.geographySamples ?? []).filter { $0.geography == nil && $0.accuracy <= 1000 }.sorted {
            if ($0.id == areaSampleID) != ($1.id == areaSampleID) { return $0.id == areaSampleID }
            return $0.timestamp > $1.timestamp
        }.map(\.id)
        for id in pending {
            guard let index = data.geographySamples?.firstIndex(where: { $0.id == id }), let sample = data.geographySamples?[index] else { continue }
            // Only reuse essentially the same point; no city-wide cache or route guessing.
            if let cached = data.geographySamples?.first(where: { $0.geography != nil && Matching.distance(sample.latitude, sample.longitude, $0.latitude, $0.longitude) < 10 })?.geography {
                data.geographySamples?[index].geography = cached
                persist()
                continue
            }
            let wait = 60 - Date().timeIntervalSince(lastGeocodeAttempt)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            lastGeocodeAttempt = Date()
            do {
                let geo = try await geocoder.resolve(latitude: sample.latitude, longitude: sample.longitude)
                data.geographySamples?[index].geography = geo
                persist()
            } catch {
                log("Sample geography unresolved; retry online later: \(error.localizedDescription)")
                break
            }
        }
        // If an actual fresh reading resolves across a city boundary inside
        // the coarse circle, replace the anchor instead of holding its old city.
        if let sample = data.geographySamples?.last, let geo = sample.geography,
           let anchor = areaAnchor, let oldGeo = anchor.geography, geo != oldGeo,
           let session = geographySession, GeographyAreaTracking.radius(for: sample, now: Date(), session: session) != nil {
            finishStationary(at: sample.timestamp)
            registerArea(for: sample)
        }
    }
}

@MainActor final class NearbyPlaceSearch: ObservableObject {
    @Published var suggestions: [PlaceSuggestion] = []
    @Published var loading = false
    @Published var message: String?
    private var search: MKLocalSearch?
    func cancel() { search?.cancel() }
    func load(for visit: Visit) async {
        guard !loading else { return }
        loading = true
        message = nil
        defer { loading = false }
        let center = CLLocationCoordinate2D(latitude: visit.latitude, longitude: visit.longitude)
        let radius = min(1500, max(200, max(0, visit.accuracy) * 2))
        let request = MKLocalPointsOfInterestRequest(center: center, radius: radius)
        let operation = MKLocalSearch(request: request)
        search = operation
        do {
            let response = try await operation.start()
            guard !Task.isCancelled else { return }
            var candidates: [PlaceSuggestion] = []
            for item in response.mapItems {
                guard let name = item.name, !name.isEmpty else { continue }
                let coordinate = item.placemark.coordinate
                let distance = Matching.distance(visit.latitude, visit.longitude, coordinate.latitude, coordinate.longitude)
                guard distance <= radius else { continue }
                let address = [item.placemark.subThoroughfare, item.placemark.thoroughfare, item.placemark.locality].compactMap { $0 }.joined(separator: " ")
                guard !candidates.contains(where: { $0.name == name && Matching.distance($0.latitude, $0.longitude, coordinate.latitude, coordinate.longitude) < 10 }) else { continue }
                var applePlaceID: String?
                if #available(iOS 18, *) { applePlaceID = item.identifier?.rawValue }
                candidates.append(PlaceSuggestion(name: name, address: address, latitude: coordinate.latitude, longitude: coordinate.longitude, distance: distance, applePlaceID: applePlaceID))
            }
            suggestions = Array(candidates.sorted { $0.distance < $1.distance }.prefix(10))
            if suggestions.isEmpty { message = "No nearby named places found. You can still enter a custom name below." }
        } catch {
            if !Task.isCancelled { message = "Suggestions unavailable. Check your connection and retry, or enter a custom name below." }
        }
        search = nil
    }
}
