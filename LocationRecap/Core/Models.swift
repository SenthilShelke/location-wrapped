import Foundation

struct Geography: Codable, Equatable {
    var city: String?
    var region: String?
    var country: String?
    var countryCode: String?
    var countryKey: String { country ?? "Unknown country" }
    var continentKey: String {
        let code = countryCode ?? Self.countryCodes[country?.lowercased() ?? ""]
        guard let code, let continent = Locale.Region(code).continent else { return "Unknown continent" }
        // Foundation groups the Americas together; split using its subcontinent.
        if continent.identifier == "019" {
            return Locale.Region(code).containingRegion?.identifier == "005" ? "South America" : "North America"
        }
        return Locale(identifier: "en").localizedString(forRegionCode: continent.identifier) ?? "Unknown continent"
    }
    private static let countryCodes: [String: String] = {
        var result: [String: String] = [:]
        for region in Locale.Region.isoRegions {
            for locale in [Locale(identifier: "en"), Locale.current] {
                if let name = locale.localizedString(forRegionCode: region.identifier) { result[name.lowercased()] = region.identifier }
            }
            result[region.identifier.lowercased()] = region.identifier
        }
        return result
    }()
    var cityKey: String { [city ?? "Unknown city", region ?? "Unknown region", country ?? "Unknown country"].joined(separator: ", ") }
    var regionKey: String { [region ?? "Unknown region", country ?? "Unknown country"].joined(separator: ", ") }
}
struct Observation: Codable, Identifiable {
    var id = UUID()
    var received: Date
    var latitude: Double
    var longitude: Double
    var accuracy: Double
    var arrival: Date?
    var departure: Date?
    var source: String
}
struct Visit: Codable, Identifiable {
    var id = UUID()
    var latitude: Double
    var longitude: Double
    var accuracy: Double
    var arrival: Date?
    var departure: Date?
    var geography: Geography?
    var manualPlaceID: UUID?
    var manualUnassigned = false
}
struct SavedPlace: Codable, Identifiable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double
    var applePlaceID: String?
}
enum PlaceMatch: Equatable { case assigned(UUID), ambiguous, none }
enum Matching {
    static func distance(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        let p = Double.pi / 180
        let x = pow(sin((c-a)*p/2), 2) + cos(a*p)*cos(c*p)*pow(sin((d-b)*p/2), 2)
        return 6_371_000 * 2 * atan2(sqrt(x), sqrt(max(0, 1-x)))
    }
    static func place(_ visit: Visit, in places: [SavedPlace]) -> PlaceMatch {
        if visit.manualUnassigned { return .none }
        if let id = visit.manualPlaceID { return .assigned(id) }
        guard visit.accuracy >= 0 else { return .ambiguous }
        let possible = places.filter { distance(visit.latitude, visit.longitude, $0.latitude, $0.longitude) <= $0.radius + visit.accuracy }
        guard !possible.isEmpty else { return .none }
        if possible.count == 1, let p = possible.first,
           distance(visit.latitude, visit.longitude, p.latitude, p.longitude) + visit.accuracy <= p.radius { return .assigned(p.id) }
        return .ambiguous
    }
}
enum Reconciliation {
    static func ingest(_ event: Observation, into visits: inout [Visit]) {
        if let i = visits.firstIndex(where: { $0.arrival == event.arrival && event.arrival != nil }) {
            // Arrival timestamps identify updates even when Apple's coordinate changes.
            // Never let a delayed arrival-only callback erase a completed departure.
            if event.departure != nil || visits[i].departure == nil {
                if Matching.distance(visits[i].latitude, visits[i].longitude, event.latitude, event.longitude) > 10 { visits[i].geography = nil }
                visits[i].latitude = event.latitude
                visits[i].longitude = event.longitude
                visits[i].accuracy = event.accuracy
            }
            if let departure = event.departure { visits[i].departure = departure }
            return
        }
        visits.append(Visit(latitude: event.latitude, longitude: event.longitude, accuracy: event.accuracy, arrival: event.arrival, departure: event.departure))
    }
    static func canonical(_ visits: [Visit]) -> [Visit] {
        var result: [Visit] = []
        for visit in visits {
            guard let arrival = visit.arrival, let i = result.firstIndex(where: { $0.arrival == arrival }) else { result.append(visit); continue }
            // Keep the completed record's identity and manual decision. Unmerged
            // originals remain in the repair archive for inspection.
            let preferNew = (result[i].departure == nil && visit.departure != nil) ||
                (result[i].departure != nil && visit.departure != nil && visit.departure! > result[i].departure!)
            if preferNew { result[i] = visit }
        }
        return result.sorted {
            let a = $0.arrival ?? $0.departure ?? .distantPast
            let b = $1.arrival ?? $1.departure ?? .distantPast
            return a == b ? $0.id.uuidString < $1.id.uuidString : a < b
        }
    }
    static func repair(_ archive: inout Archive, at now: Date) {
        guard (archive.repairVersion ?? 0) < 1 else { return }
        let canonicalVisits = canonical(archive.visits)
        let retained = Set(canonicalVisits.map(\.id))
        archive.supersededVisits = (archive.supersededVisits ?? []) + archive.visits.filter { !retained.contains($0.id) }
        archive.visits = canonicalVisits
        // Replay complete raw observations to recover refined coordinates without
        // replacing the chosen record's manually confirmed place.
        for event in archive.observations.sorted(by: { $0.received < $1.received }) where event.departure != nil && event.arrival != nil {
            ingest(event, into: &archive.visits)
        }
        archive.geographyBackfillThrough = now
        archive.repairVersion = 1
    }
}
struct Totals {
    var elapsed: TimeInterval
    var tracked: TimeInterval = 0
    var ongoing: TimeInterval = 0
    var ongoingPlaces: Set<String> = []
    var cities: [String: TimeInterval] = [:]
    var regions: [String: TimeInterval] = [:]
    var countries: [String: TimeInterval] = [:]
    var continents: [String: TimeInterval] = [:]
    var places: [String: TimeInterval] = [:]
    var savedPlaceSeconds: [UUID: TimeInterval] = [:]
    var savedPlaceVisitIDs: [UUID: Set<UUID>] = [:]
    var travel: TimeInterval = 0
    var includesTravel = false
    var accounted: TimeInterval { tracked + (includesTravel ? travel : 0) }
    var missing: TimeInterval { max(0, elapsed - tracked - travel) }
}
enum PeriodGrain: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week", month = "Month", year = "Year"
    var id: String { rawValue }
    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }
    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        return calendar
    }
    func interval(containing date: Date, timeZone: TimeZone = .current) -> DateInterval {
        Self.calendar(timeZone: timeZone).dateInterval(of: component, for: date)!
    }
    func shifted(from date: Date, by count: Int, timeZone: TimeZone = .current) -> Date {
        let start = interval(containing: date, timeZone: timeZone).start
        return Self.calendar(timeZone: timeZone).date(byAdding: component, value: count, to: start)!
    }
}
enum Aggregation {
    static func window(now: Date, weekly: Bool, timeZone: TimeZone = .current) -> DateInterval {
        window(containing: now, grain: weekly ? .week : .day, now: now, timeZone: timeZone)
    }
    static func window(containing date: Date, grain: PeriodGrain, now: Date, timeZone: TimeZone = .current) -> DateInterval {
        let period = grain.interval(containing: date, timeZone: timeZone)
        // Historical periods are complete; the current period only includes elapsed time.
        return DateInterval(start: period.start, end: max(period.start, min(period.end, now)))
    }
    // Infer bounded gaps only. An open arrival can end travel, but never starts it.
    // Subtract all observed stays (including open stays) and union duplicate gaps.
    static func travelIntervals(visits: [Visit], window: DateInterval) -> [DateInterval] {
        let valid = Reconciliation.canonical(visits).filter { v in
            if let a = v.arrival, let d = v.departure { return d > a }
            return true
        }
        let arrivals = valid.compactMap(\.arrival).sorted()
        let candidates: [DateInterval] = valid.compactMap { v in
            guard let d = v.departure, let a = arrivals.first(where: { $0 >= d }), a > d else { return nil }
            let start = max(d, window.start), end = min(a, window.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }
        guard !candidates.isEmpty else { return [] }
        let stays: [DateInterval] = valid.compactMap { v in
            guard let a = v.arrival else { return nil }
            let nextArrival = arrivals.first(where: { $0 > a })
            let inferredEnd = v.departure ?? nextArrival ?? window.end
            let start = max(a, window.start), end = min(inferredEnd, window.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }
        let edges = Set((candidates + stays).flatMap { [$0.start, $0.end] }).sorted()
        var result: [DateInterval] = []
        for i in 0..<(edges.count - 1) {
            let start = edges[i], end = edges[i+1]
            guard candidates.contains(where: { $0.start < end && $0.end > start }),
                  !stays.contains(where: { $0.start < end && $0.end > start }) else { continue }
            if let last = result.last, last.end == start {
                result[result.count - 1] = DateInterval(start: last.start, end: end)
            } else { result.append(DateInterval(start: start, end: end)) }
        }
        return result
    }
    static func ongoingVisit(visits: [Visit], now: Date) -> Visit? {
        let eligible = visits.filter { ($0.arrival ?? .distantFuture) <= now }
        guard let latest = eligible.compactMap(\.arrival).max(),
              !eligible.contains(where: { $0.arrival == latest && $0.departure != nil }) else { return nil }
        return eligible.first { $0.arrival == latest && $0.departure == nil }
    }
    static func totals(visits: [Visit], places: [SavedPlace], window: DateInterval, includeTravel: Bool = false, ongoingUntil: Date? = nil) -> Totals {
        var input = visits
        var ongoingID: UUID?
        if let now = ongoingUntil, let open = ongoingVisit(visits: visits, now: now), let index = input.firstIndex(where: { $0.id == open.id }), now > open.arrival! {
            input[index].departure = now
            ongoingID = open.id
        }
        let usable = input.filter { v in
            guard let a = v.arrival, let d = v.departure else { return false }
            return d > a && d > window.start && a < window.end
        }
        let edges = Set(usable.flatMap { [max($0.arrival!, window.start), min($0.departure!, window.end)] }).sorted()
        var result = Totals(elapsed: window.duration)
        result.includesTravel = includeTravel
        result.travel = travelIntervals(visits: visits, window: window).reduce(0) { $0 + $1.duration }
        guard edges.count > 1 else { return result }
        for i in 0..<(edges.count-1) {
            let a = edges[i], b = edges[i+1]
            let active = usable.filter { $0.arrival! < b && $0.departure! > a }
            guard !active.isEmpty else { continue }
            let seconds = b.timeIntervalSince(a)
            result.tracked += seconds
            let isOngoing = active.contains { $0.id == ongoingID } && !active.contains { $0.id != ongoingID }
            if isOngoing { result.ongoing += seconds }
            func consensus(_ labels: [String]) -> String { Set(labels).count == 1 ? labels[0] : "Unknown · conflicting visits" }
            let city = consensus(active.map { $0.geography?.cityKey ?? "Unknown geography" })
            let region = consensus(active.map { $0.geography?.regionKey ?? "Unknown geography" })
            let place = consensus(active.map { v in
                switch Matching.place(v, in: places) {
                case .none: return "No saved place"
                case .ambiguous: return "Ambiguous place"
                case .assigned(let id): return places.first(where: { $0.id == id })?.name ?? "Unknown place"
                }
            })
            result.cities[city, default: 0] += seconds
            result.regions[region, default: 0] += seconds
            result.countries[consensus(active.map { $0.geography?.countryKey ?? "Unknown country" }), default: 0] += seconds
            result.continents[consensus(active.map { $0.geography?.continentKey ?? "Unknown continent" }), default: 0] += seconds
            result.places[place, default: 0] += seconds
            let assignedIDs = active.compactMap { v -> UUID? in
                if case .assigned(let id) = Matching.place(v, in: places), places.contains(where: { $0.id == id }) { return id }
                return nil
            }
            if assignedIDs.count == active.count, Set(assignedIDs).count == 1, let id = assignedIDs.first {
                result.savedPlaceSeconds[id, default: 0] += seconds
                result.savedPlaceVisitIDs[id, default: []].formUnion(active.map(\.id))
            }
            if isOngoing { result.ongoingPlaces.insert(place) }
        }
        return result
    }
}
enum Replay {
    static func day(start: Date) -> ([Visit], [SavedPlace]) {
        let gym = SavedPlace(name: "Gym", latitude: 43.65, longitude: -79.38, radius: 150)
        let geo = Geography(city: "Toronto", region: "Ontario", country: "Canada")
        return ([Visit(latitude: 43.65, longitude: -79.38, accuracy: 10, arrival: start, departure: start.addingTimeInterval(7200), geography: geo), Visit(latitude: 43.7, longitude: -79.4, accuracy: 10, arrival: start.addingTimeInterval(7200), departure: start.addingTimeInterval(28800), geography: geo)], [gym])
    }
    static func travel(start: Date) -> [Visit] {
        [Visit(latitude: 43.65, longitude: -79.38, accuracy: 20, arrival: start, departure: start.addingTimeInterval(7200), geography: Geography(city: "Toronto", region: "Ontario", country: "Canada")), Visit(latitude: 51.5, longitude: -0.12, accuracy: 20, arrival: start.addingTimeInterval(36000), departure: start.addingTimeInterval(50400), geography: Geography(city: "London", region: "England", country: "United Kingdom"))]
    }
}

protocol VisitGeocoder {
    func resolve(latitude: Double, longitude: Double) async throws -> Geography
}
struct StubGeocoder: VisitGeocoder {
    var result: Result<Geography, Error>
    func resolve(latitude: Double, longitude: Double) async throws -> Geography { try result.get() }
}

struct PlaceSuggestion: Identifiable {
    var id = UUID()
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var distance: Double
    var applePlaceID: String?
}
enum PlaceSuggestions {
    static func canSuggest(_ visit: Visit, places: [SavedPlace]) -> Bool {
        guard visit.manualPlaceID == nil, !visit.manualUnassigned else { return false }
        if case .assigned = Matching.place(visit, in: places) { return false }
        return true
    }
    // A confirmation cannot overwrite an existing manual decision or edit a saved circle.
    @discardableResult static func confirm(_ suggestion: PlaceSuggestion, visitID: UUID, radius: Double, visits: inout [Visit], places: inout [SavedPlace]) -> Bool {
        guard let index = visits.firstIndex(where: { $0.id == visitID }), canSuggest(visits[index], places: places) else { return false }
        let existing = places.first {
            (suggestion.applePlaceID != nil && $0.applePlaceID == suggestion.applePlaceID) ||
            PlaceNaming.key($0.name) == PlaceNaming.key(suggestion.name)
        }
        let place = existing ?? SavedPlace(name: suggestion.name, latitude: suggestion.latitude, longitude: suggestion.longitude, radius: radius, applePlaceID: suggestion.applePlaceID)
        if existing == nil { places.append(place) }
        else if let i = places.firstIndex(where: { $0.id == place.id }), places[i].applePlaceID == nil {
            places[i].applePlaceID = suggestion.applePlaceID
        }
        visits[index].manualPlaceID = place.id
        visits[index].manualUnassigned = false
        return true
    }
}

// Independent geography observations; never converted to visits.
struct GeographySample: Codable, Identifiable {
    var id = UUID()
    var timestamp: Date
    var received: Date
    var latitude: Double
    var longitude: Double
    var accuracy: Double
    var session: UUID
    var geography: Geography?
}
struct GeographyTotals {
    var elapsed: TimeInterval
    var covered: TimeInterval = 0
    var cities: [String: TimeInterval] = [:]
    var regions: [String: TimeInterval] = [:]
    var countries: [String: TimeInterval] = [:]
    var continents: [String: TimeInterval] = [:]
    var stationaryEstimated: TimeInterval = 0
    var visitEstimated: TimeInterval = 0
    var missing: TimeInterval { max(0, elapsed - covered) }
}
struct StationaryStay: Codable, Identifiable {
    var id = UUID()
    var start: Date
    var confirmed: Date
    var end: Date?
    var sampleID: UUID
    var session: UUID
}
enum GeographyTimeline {
    static let maximumGap: TimeInterval = 15 * 60
    private struct Segment {
        var interval: DateInterval
        var geography: Geography?
        var priority: Int // observations, stationary evidence, historical, visit backfill
    }
    static func totals(samples: [GeographySample], window: DateInterval, legacyVisits: [Visit] = [], cutover: Date? = nil, stationary: [StationaryStay] = [], activeSession: UUID? = nil, backfillThrough: Date? = nil) -> GeographyTotals {
        var result = GeographyTotals(elapsed: window.duration)
        var segments: [Segment] = []
        func add(_ start: Date, _ end: Date, _ geography: Geography?, _ priority: Int) {
            let a = max(start, window.start), b = min(end, window.end)
            if b > a { segments.append(Segment(interval: DateInterval(start: a, end: b), geography: geography, priority: (geography == nil && priority < 2) ? 4 : priority)) }
        }
        let boundary = cutover ?? window.end
        let visits = Reconciliation.canonical(legacyVisits)
        for v in visits {
            if let a = v.arrival, let d = v.departure, d > a { add(a, min(d, boundary), v.geography, 2) }
        }
        let sampleStart = max(window.start, cutover ?? window.start)
        let ordered = samples.filter { $0.accuracy >= 0 && $0.accuracy <= 1000 }.sorted { $0.timestamp < $1.timestamp }
        var unique: [GeographySample] = []
        for sample in ordered where unique.last?.timestamp != sample.timestamp { unique.append(sample) }
        if unique.count > 1 {
            for i in 0..<(unique.count - 1) {
                let a = unique[i], b = unique[i+1]
                let gap = b.timestamp.timeIntervalSince(a.timestamp)
                guard a.session == b.session, gap > 0, gap <= maximumGap else { continue }
                let midpoint = a.timestamp.addingTimeInterval(gap / 2)
                add(max(a.timestamp, sampleStart), midpoint, a.geography, 0)
                add(max(midpoint, sampleStart), b.timestamp, b.geography, 0)
            }
        }
        let byID = Dictionary(uniqueKeysWithValues: samples.map { ($0.id, $0) }.uniquedByKey())
        for stay in stationary {
            guard let sample = byID[stay.sampleID], sample.accuracy >= 0, sample.accuracy <= 1000 else { continue }
            // Only a live monitoring session can extend a stationary estimate.
            let end = stay.end ?? (stay.session == activeSession ? window.end : stay.confirmed)
            add(max(stay.start, sampleStart), end, sample.geography, 1)
        }
        if let backfill = backfillThrough {
            let current = Aggregation.ongoingVisit(visits: visits, now: backfill)
            for v in visits {
                guard let a = v.arrival, let end = v.departure ?? (v.id == current?.id ? backfill : nil) else { continue }
                add(max(a, sampleStart), min(end, backfill), v.geography, 3)
            }
        }
        let edges = Set(segments.flatMap { [$0.interval.start, $0.interval.end] }).sorted()
        guard edges.count > 1 else { return result }
        for i in 0..<(edges.count - 1) {
            let a = edges[i], b = edges[i+1]
            let active = segments.filter { $0.interval.start < b && $0.interval.end > a }
            guard let priority = active.map(\.priority).min() else { continue }
            let chosen = active.filter { $0.priority == priority }
            let seconds = b.timeIntervalSince(a)
            result.covered += seconds
            if priority == 1 { result.stationaryEstimated += seconds }
            if priority == 3 { result.visitEstimated += seconds }
            func consensus(_ values: [String]) -> String { Set(values).count == 1 ? values[0] : "Unknown · conflicting evidence" }
            result.cities[consensus(chosen.map { $0.geography?.cityKey ?? "Unknown geography" }), default: 0] += seconds
            result.regions[consensus(chosen.map { $0.geography?.regionKey ?? "Unknown geography" }), default: 0] += seconds
            result.countries[consensus(chosen.map { $0.geography?.countryKey ?? "Unknown country" }), default: 0] += seconds
            result.continents[consensus(chosen.map { $0.geography?.continentKey ?? "Unknown continent" }), default: 0] += seconds
        }
        return result
    }
}
private extension Array where Element == (UUID, GeographySample) {
    func uniquedByKey() -> [(UUID, GeographySample)] {
        var seen = Set<UUID>()
        return filter { seen.insert($0.0).inserted }
    }
}

extension Replay {
    static func geography(start: Date) -> [GeographySample] {
        let session = UUID()
        return (0...60).map { minute in
            GeographySample(timestamp: start.addingTimeInterval(Double(minute) * 60), received: start.addingTimeInterval(Double(minute) * 60), latitude: 43.4, longitude: -80.5 + Double(minute) * 0.001, accuracy: 100, session: session, geography: Geography(city: minute < 30 ? "Waterloo" : "Kitchener", region: "Ontario", country: "Canada"))
        }
    }
}

struct Archive: Codable {
    var visits: [Visit] = []
    var observations: [Observation] = []
    var places: [SavedPlace] = []
    var enabled = false
    var diagnostics: [String] = []
    // Optional fields decode archives written before geography capture existed.
    var geographySamples: [GeographySample]?
    var geographyStartedAt: Date?
    var stationaryStays: [StationaryStay]?
    var geographyBackfillThrough: Date?
    var supersededVisits: [Visit]?
    var supersededPlaces: [SavedPlace]?
    var repairVersion: Int?
}

enum InsightCard: String, CaseIterable, Identifiable {
    case summary, visits, geography, countries, continents
    var id: String { rawValue }
    var title: String {
        switch self {
        case .summary: return "Your time, accounted for"
        case .visits: return "Visits Breakdown"
        case .geography: return "Geography Breakdown"
        case .countries: return "Country Breakdown"
        case .continents: return "Continent Breakdown"
        }
    }
    static let defaults: [InsightCard] = [.summary, .visits, .geography]
    static func decodeLayout(_ value: String) -> [InsightCard] {
        if value.isEmpty { return defaults }
        if value == "none" { return [] }
        var seen = Set<String>()
        return value.split(separator: ",").compactMap { raw in
            guard seen.insert(String(raw)).inserted else { return nil }
            return InsightCard(rawValue: String(raw))
        }
    }
    static func encodeLayout(_ cards: [InsightCard]) -> String {
        cards.isEmpty ? "none" : cards.map(\.rawValue).joined(separator: ",")
    }
}

enum PendingVisits {
    static func needsName(_ visit: Visit, places: [SavedPlace]) -> Bool {
        // Explicitly choosing "No saved place" is a completed user decision.
        if visit.manualUnassigned { return false }
        if case .assigned(let id) = Matching.place(visit, in: places),
           let place = places.first(where: { $0.id == id }),
           !place.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return true
    }
    static func count(_ visits: [Visit], places: [SavedPlace]) -> Int {
        Set(visits.filter { needsName($0, places: places) }.map(\.id)).count
    }
}

enum CustomPlaceResult: Equatable { case saved(UUID), duplicate(UUID), invalid }
enum PlaceNaming {
    static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    static func saveCustom(name: String, visitID: UUID, radius: Double, visits: inout [Visit], places: inout [SavedPlace]) -> CustomPlaceResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key(trimmed).isEmpty, let i = visits.firstIndex(where: { $0.id == visitID }) else { return .invalid }
        if let existing = places.first(where: { key($0.name) == key(trimmed) }) { return .duplicate(existing.id) }
        let v = visits[i]
        let place = SavedPlace(name: trimmed, latitude: v.latitude, longitude: v.longitude, radius: radius)
        places.append(place)
        visits[i].manualPlaceID = place.id
        visits[i].manualUnassigned = false
        return .saved(place.id)
    }
    static func repair(_ archive: inout Archive) {
        guard (archive.repairVersion ?? 0) < 2 else { return }
        let groups = Dictionary(grouping: archive.places, by: { key($0.name) })
        let references = Dictionary(grouping: archive.visits.compactMap(\.manualPlaceID), by: { $0 }).mapValues(\.count)
        var places: [SavedPlace] = []
        var redirects: [UUID: UUID] = [:]
        var originals: [SavedPlace] = []
        var handled = Set<String>()
        for first in archive.places where handled.insert(key(first.name)).inserted {
            let group = groups[key(first.name)]!
            // Prefer the circle most often explicitly confirmed on active visits.
            // Ties retain the original saved record.
            var canonical = group[0]
            for place in group.dropFirst() where references[place.id, default: 0] > references[canonical.id, default: 0] { canonical = place }
            if canonical.applePlaceID == nil { canonical.applePlaceID = group.compactMap(\.applePlaceID).first }
            places.append(canonical)
            for place in group where place.id != canonical.id {
                redirects[place.id] = canonical.id
                originals.append(place)
            }
        }
        // Redirect explicit assignments; preserve circles on the original records.
        for i in archive.visits.indices {
            let v = archive.visits[i]
            if let id = v.manualPlaceID, let canonical = redirects[id] { archive.visits[i].manualPlaceID = canonical }
        }
        archive.supersededPlaces = (archive.supersededPlaces ?? []) + originals
        archive.places = places
        archive.repairVersion = 2
    }
}
