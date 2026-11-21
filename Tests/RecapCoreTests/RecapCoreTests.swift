import XCTest
@testable import RecapCore
final class RecapCoreTests: XCTestCase {
    let start = ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z")!
    func testMapPlaceTotalsShareVisitDenominatorAndIncludeOngoing() {
        let home = SavedPlace(name: "Home", latitude: 0, longitude: 0, radius: 150)
        let work = SavedPlace(name: "Work", latitude: 1, longitude: 1, radius: 150)
        let first = Visit(latitude: 0, longitude: 0, accuracy: 10, arrival: start.addingTimeInterval(-3600), departure: start.addingTimeInterval(3600), manualPlaceID: home.id)
        let second = Visit(latitude: 1, longitude: 1, accuracy: 10, arrival: start.addingTimeInterval(7200), manualPlaceID: work.id)
        let now = start.addingTimeInterval(10800)
        let window = DateInterval(start: start, end: now)
        let off = Aggregation.totals(visits: [first, first, second], places: [home, work], window: window, ongoingUntil: now)
        let on = Aggregation.totals(visits: [first, first, second], places: [home, work], window: window, includeTravel: true, ongoingUntil: now)
        XCTAssertEqual(off.savedPlaceSeconds, [home.id: 3600, work.id: 3600])
        XCTAssertEqual(off.savedPlaceSeconds, on.savedPlaceSeconds)
        XCTAssertEqual(off.savedPlaceVisitIDs[home.id], [first.id])
        XCTAssertEqual(off.savedPlaceVisitIDs[work.id], [second.id])
        XCTAssertEqual(off.savedPlaceSeconds[home.id]! / off.accounted, 0.5)
        XCTAssertEqual(on.savedPlaceSeconds[home.id]! / on.accounted, 1.0 / 3, accuracy: 0.00001)
        XCTAssertEqual(on.savedPlaceSeconds.values.reduce(0, +) + on.travel, on.accounted)
        XCTAssertEqual(on.ongoingPlaces, ["Work"])
    }
    func testMapDoesNotAttributeAmbiguousOrConflictingTimeToPins() {
        let home = SavedPlace(name: "Home", latitude: 0, longitude: 0, radius: 150)
        let other = SavedPlace(name: "Other", latitude: 0, longitude: 0, radius: 150)
        var visit = Visit(latitude: 0, longitude: 0, accuracy: 10, arrival: start, departure: start.addingTimeInterval(3600))
        let window = DateInterval(start: start, duration: 3600)
        let ambiguous = Aggregation.totals(visits: [visit], places: [home, other], window: window)
        XCTAssertEqual(ambiguous.tracked, 3600)
        XCTAssertTrue(ambiguous.savedPlaceSeconds.isEmpty)
        visit.manualPlaceID = home.id
        var conflict = visit; conflict.id = UUID(); conflict.manualPlaceID = other.id
        let conflicting = Aggregation.totals(visits: [visit, conflict], places: [home, other], window: window)
        XCTAssertTrue(conflicting.savedPlaceSeconds.isEmpty)
        XCTAssertEqual(conflicting.tracked, 3600)
    }
    func testExampleDayAndDuplicateUnion() {
        let (visits, places) = Replay.day(start: start)
        let t = Aggregation.totals(visits: visits + visits, places: places, window: DateInterval(start: start, duration: 86400))
        XCTAssertEqual(t.tracked, 28800)
        XCTAssertEqual(t.missing, 57600)
        XCTAssertEqual(t.cities.values.first, 28800)
        XCTAssertEqual(t.places["Gym"]! / t.tracked, 0.25)
    }
    func testReconcileOpenThenDepartureAndDuplicate() {
        var visits: [Visit] = []
        var e = Observation(received: start, latitude: 1, longitude: 1, accuracy: 10, arrival: start, source: "fixture")
        Reconciliation.ingest(e, into: &visits)
        XCTAssertEqual(Aggregation.totals(visits: visits, places: [], window: DateInterval(start: start, duration: 86400)).tracked, 0)
        e.departure = start.addingTimeInterval(3600)
        Reconciliation.ingest(e, into: &visits)
        Reconciliation.ingest(e, into: &visits)
        XCTAssertEqual(visits.count, 1)
        XCTAssertEqual(visits[0].departure, e.departure)
    }
    func testMidnightClippingAndUnknownGeography() {
        let v = Visit(latitude: 1, longitude: 1, accuracy: 10, arrival: start.addingTimeInterval(-3600), departure: start.addingTimeInterval(3600))
        let t = Aggregation.totals(visits: [v], places: [], window: DateInterval(start: start, duration: 86400))
        XCTAssertEqual(t.tracked, 3600)
        XCTAssertEqual(t.cities["Unknown geography"], 3600)
        XCTAssertEqual(t.missing, 82800)
    }
    func testAmbiguousCirclesAndManualCorrection() {
        var (visits, places) = Replay.day(start: start)
        var second = places[0]; second.id = UUID(); second.name = "Work"
        places.append(second)
        XCTAssertEqual(Matching.place(visits[0], in: places), .ambiguous)
        visits[0].manualPlaceID = second.id
        XCTAssertEqual(Matching.place(visits[0], in: places), .assigned(second.id))
        visits[0].manualUnassigned = true
        XCTAssertEqual(Matching.place(visits[0], in: places), .none)
        var edge = visits[1]; edge.latitude = places[0].latitude; edge.longitude = places[0].longitude; edge.accuracy = 200
        XCTAssertEqual(Matching.place(edge, in: [places[0]]), .ambiguous)
    }
    func testConflictingAttribution() {
        let (v, p) = Replay.day(start: start)
        var other = v[0]; other.geography = Geography(city: "Other", region: "Elsewhere", country: "Other")
        let t = Aggregation.totals(visits: v + [other], places: p, window: DateInterval(start: start, duration: 86400))
        XCTAssertEqual(t.tracked, 28800)
        XCTAssertEqual(t.cities["Unknown · conflicting visits"], 7200)
    }
    func testBorderTravelFlightGapAndZone() {
        let t = Aggregation.totals(visits: Replay.travel(start: start), places: [], window: DateInterval(start: start, duration: 86400))
        XCTAssertEqual(t.tracked, 21600)
        XCTAssertEqual(t.missing, 36000)
        XCTAssertEqual(t.cities.count, 2)
        // Arrival 10:00 UTC is 10:00 London, after departing 02:00 UTC / previous evening Toronto.
        XCTAssertEqual(t.cities["London, England, United Kingdom"], 14400)
        let now = start.addingTimeInterval(18*3600)
        let toronto = Aggregation.window(now: now, weekly: false, timeZone: TimeZone(identifier: "America/Toronto")!)
        XCTAssertEqual(toronto.start, start.addingTimeInterval(4*3600)) // DST transition day
        XCTAssertEqual(toronto.end, now)
    }
    func testStubGeocoderFailurePreservesUnknown() async {
        enum Offline: Error { case unavailable }
        let stub = StubGeocoder(result: .failure(Offline.unavailable))
        var visits = Replay.travel(start: start)
        visits[0].geography = nil
        do {
            visits[0].geography = try await stub.resolve(latitude: 43, longitude: -79)
            XCTFail("Expected offline failure")
        } catch { XCTAssertNil(visits[0].geography) }
        let t = Aggregation.totals(visits: visits, places: [], window: DateInterval(start: start, duration: 86400))
        XCTAssertEqual(t.cities["Unknown geography"], 7200)
        XCTAssertEqual(t.tracked, 21600)
    }
    func testHistoricalSundayAndMondayWeekReset() {
        let f = ISO8601DateFormatter()
        let now = f.date(from: "2026-11-16T17:00:00Z")!
        let sunday = f.date(from: "2026-11-15T17:00:00Z")!
        let zone = TimeZone(identifier: "America/Toronto")!
        let day = Aggregation.window(containing: sunday, grain: .day, now: now, timeZone: zone)
        XCTAssertEqual(day.start, f.date(from: "2026-11-15T05:00:00Z"))
        XCTAssertEqual(day.duration, 86400)
        let week = Aggregation.window(containing: sunday, grain: .week, now: now, timeZone: zone)
        XCTAssertEqual(week.start, f.date(from: "2026-11-09T05:00:00Z"))
        XCTAssertEqual(week.end, day.end)
        let fixture = Replay.day(start: day.start)
        XCTAssertEqual(Aggregation.totals(visits: fixture.0, places: fixture.1, window: day).tracked, 28800)
        let current = Aggregation.window(containing: now, grain: .week, now: now, timeZone: zone)
        XCTAssertEqual(current.start, day.end)
        XCTAssertEqual(current.end, now)
        XCTAssertEqual(Aggregation.totals(visits: fixture.0, places: fixture.1, window: current).tracked, 0)
    }
    func testMonthYearLeapAndNavigationBoundaries() {
        let f = ISO8601DateFormatter()
        let zone = TimeZone(secondsFromGMT: 0)!
        let leap = f.date(from: "2024-02-29T12:00:00Z")!
        let now = f.date(from: "2026-11-16T17:00:00Z")!
        let month = Aggregation.window(containing: leap, grain: .month, now: now, timeZone: zone)
        XCTAssertEqual(month.duration, 29 * 86400)
        let year = Aggregation.window(containing: leap, grain: .year, now: now, timeZone: zone)
        XCTAssertEqual(year.duration, 366 * 86400)
        XCTAssertEqual(PeriodGrain.month.shifted(from: leap, by: 1, timeZone: zone), month.end)
        let january = f.date(from: "2026-01-31T12:00:00Z")!
        XCTAssertEqual(PeriodGrain.month.shifted(from: january, by: -1, timeZone: zone), f.date(from: "2025-12-01T00:00:00Z"))
        for grain in PeriodGrain.allCases {
            let current = Aggregation.window(containing: now, grain: grain, now: now, timeZone: zone)
            XCTAssertEqual(current.end, now)
        }
    }
    func testSelectedDayDSTUsesCalendarDuration() {
        let zone = TimeZone(identifier: "America/Toronto")!
        let now = start.addingTimeInterval(2 * 86400)
        let day = Aggregation.window(containing: start.addingTimeInterval(12 * 3600), grain: .day, now: now, timeZone: zone)
        XCTAssertEqual(day.duration, 25 * 3600)
    }
    func testSuggestionConfirmationPreservesExistingPlacesAndOverrides() {
        var (visits, places) = Replay.day(start: start)
        let original = places[0]
        let candidate = PlaceSuggestion(name: "Store", address: "Example", latitude: visits[1].latitude, longitude: visits[1].longitude, distance: 0)
        XCTAssertTrue(PlaceSuggestions.canSuggest(visits[1], places: places))
        XCTAssertTrue(PlaceSuggestions.confirm(candidate, visitID: visits[1].id, radius: 150, visits: &visits, places: &places))
        XCTAssertEqual(places.count, 2)
        XCTAssertEqual(places[0].id, original.id)
        XCTAssertEqual(places[0].radius, original.radius)
        let assigned = visits[1].manualPlaceID
        XCTAssertFalse(PlaceSuggestions.confirm(candidate, visitID: visits[1].id, radius: 400, visits: &visits, places: &places))
        XCTAssertEqual(visits[1].manualPlaceID, assigned)
        XCTAssertEqual(places.count, 2)
        // A repeat visit near an existing circle may be ambiguous, but confirming
        // the same suggestion reuses the place without changing its radius.
        var repeatVisit = visits[1]
        repeatVisit.id = UUID(); repeatVisit.manualPlaceID = nil; repeatVisit.accuracy = 500
        visits.append(repeatVisit)
        XCTAssertTrue(PlaceSuggestions.confirm(candidate, visitID: repeatVisit.id, radius: 900, visits: &visits, places: &places))
        XCTAssertEqual(places.count, 2)
        XCTAssertEqual(places[1].radius, 150)
        XCTAssertEqual(visits[2].manualPlaceID, assigned)
        visits[2].manualPlaceID = nil; visits[2].manualUnassigned = true
        XCTAssertFalse(PlaceSuggestions.canSuggest(visits[2], places: places))
        XCTAssertFalse(PlaceSuggestions.canSuggest(visits[0], places: places))
    }
    func testTravelToggleDenominatorAndOpenStay() {
        let v = Replay.travel(start: start)
        var open = v[1]; open.departure = nil
        let window = DateInterval(start: start, duration: 86400)
        let off = Aggregation.totals(visits: v, places: [], window: window)
        let on = Aggregation.totals(visits: v + v, places: [], window: window, includeTravel: true)
        XCTAssertEqual(off.tracked, 6 * 3600)
        XCTAssertEqual(off.travel, 8 * 3600)
        XCTAssertEqual(off.accounted, 6 * 3600)
        XCTAssertEqual(off.missing, 10 * 3600)
        XCTAssertEqual(off.missing, on.missing)
        XCTAssertEqual(on.accounted, 14 * 3600)
        XCTAssertEqual(on.missing, 10 * 3600)
        XCTAssertEqual(on.cities.values.reduce(0, +), on.tracked)
        let pending = Aggregation.totals(visits: [v[0], open], places: [], window: window, includeTravel: true)
        XCTAssertEqual(pending.travel, 8 * 3600)
        XCTAssertEqual(pending.tracked, 2 * 3600)
        XCTAssertEqual(pending.missing, 14 * 3600) // current stay is never travel
        XCTAssertEqual(Aggregation.totals(visits: [open], places: [], window: window, includeTravel: true).travel, 0)
    }
    func testTravelClippingAndOverlaps() {
        let v = Replay.travel(start: start)
        let clipped = DateInterval(start: start.addingTimeInterval(4 * 3600), duration: 8 * 3600)
        XCTAssertEqual(Aggregation.totals(visits: v, places: [], window: clipped, includeTravel: true).travel, 6 * 3600)
        var overlap = v[0]
        overlap.departure = start.addingTimeInterval(11 * 3600)
        XCTAssertEqual(Aggregation.totals(visits: [v[0], overlap, v[1]], places: [], window: DateInterval(start: start, duration: 86400), includeTravel: true).travel, 0)
        var departureOnly = v[0]; departureOnly.arrival = nil
        let t = Aggregation.totals(visits: [departureOnly, v[1]], places: [], window: DateInterval(start: start, duration: 86400), includeTravel: true)
        XCTAssertEqual(t.travel, 8 * 3600)
        XCTAssertEqual(t.tracked, 4 * 3600)
        XCTAssertEqual(t.missing, 12 * 3600) // setup gap stays missing
    }
    func testGeographyIsIndependentAndClipsAtMidnight() {
        let session = UUID()
        let a = Geography(city: "A", region: "R", country: "C")
        let b = Geography(city: "B", region: "S", country: "C")
        func sample(_ offset: Double, _ geo: Geography?) -> GeographySample {
            GeographySample(timestamp: start.addingTimeInterval(offset), received: start, latitude: 0, longitude: 0, accuracy: 100, session: session, geography: geo)
        }
        let samples = [sample(-300, a), sample(300, b), sample(600, b)]
        let t = GeographyTimeline.totals(samples: samples + samples, window: DateInterval(start: start, duration: 3600))
        XCTAssertEqual(t.covered, 600)
        XCTAssertNil(t.cities[a.cityKey])
        XCTAssertEqual(t.cities[b.cityKey], 600)
        XCTAssertEqual(t.missing, 3000)
        let full = GeographyTimeline.totals(samples: samples, window: DateInterval(start: start.addingTimeInterval(-300), duration: 900))
        XCTAssertEqual(full.cities[a.cityKey], 300)
        XCTAssertEqual(full.cities[b.cityKey], 600)
    }
    func testGeographyGapsSessionsAccuracyAndOffline() {
        let session = UUID()
        let a = GeographySample(timestamp: start, received: start, latitude: 0, longitude: 0, accuracy: 100, session: session)
        var b = a; b.id = UUID(); b.timestamp = start.addingTimeInterval(300)
        let window = DateInterval(start: start, duration: 3600)
        XCTAssertEqual(GeographyTimeline.totals(samples: [a,b], window: window).cities["Unknown geography"], 300)
        b.session = UUID()
        XCTAssertEqual(GeographyTimeline.totals(samples: [a,b], window: window).covered, 0)
        b.session = session; b.timestamp = start.addingTimeInterval(901)
        XCTAssertEqual(GeographyTimeline.totals(samples: [a,b], window: window).covered, 0)
        b.timestamp = start.addingTimeInterval(300); b.accuracy = 2000
        XCTAssertEqual(GeographyTimeline.totals(samples: [a,b], window: window).covered, 0)
        XCTAssertEqual(GeographyTimeline.totals(samples: [a], window: window).covered, 0)
    }
    func testLegacyArchiveMigrationAndRoundTrip() throws {
        let original = Archive(visits: Replay.day(start: start).0, places: Replay.day(start: start).1, enabled: true)
        let encoded = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "geographySamples")
        object.removeValue(forKey: "geographyStartedAt")
        let migrated = try JSONDecoder().decode(Archive.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(migrated.visits.map(\.id), original.visits.map(\.id))
        XCTAssertEqual(migrated.places.map(\.id), original.places.map(\.id))
        XCTAssertTrue(migrated.enabled)
        XCTAssertNil(migrated.geographySamples)
        var updated = migrated
        updated.geographySamples = Replay.geography(start: start)
        let restored = try JSONDecoder().decode(Archive.self, from: JSONEncoder().encode(updated))
        XCTAssertEqual(restored.geographySamples?.count, 61)
        XCTAssertEqual(restored.visits.map(\.id), original.visits.map(\.id))
    }
    func testLegacyGeographyCutoverNoDoubleCounting() {
        let visits = Replay.day(start: start).0
        let cutoff = start.addingTimeInterval(3600)
        let session = UUID()
        let geo = Geography(city: "Kitchener", region: "ON", country: "Canada")
        let samples = [0.0, 3600, 3900, 4200].map {
            GeographySample(timestamp: start.addingTimeInterval($0), received: start, latitude: 0, longitude: 0, accuracy: 100, session: session, geography: geo)
        }
        let t = GeographyTimeline.totals(samples: samples, window: DateInterval(start: start, duration: 86400), legacyVisits: visits, cutover: cutoff)
        XCTAssertEqual(t.covered, 4200)
        XCTAssertEqual(t.cities[visits[0].geography!.cityKey], 3600)
        XCTAssertEqual(t.cities[geo.cityKey], 600)
        let past = GeographyTimeline.totals(samples: samples, window: DateInterval(start: start, duration: 1800), legacyVisits: visits, cutover: cutoff)
        XCTAssertEqual(past.covered, 1800)
        XCTAssertNil(past.cities[geo.cityKey])
        let future = GeographyTimeline.totals(samples: samples, window: DateInterval(start: cutoff, duration: 3600), legacyVisits: visits, cutover: cutoff)
        XCTAssertEqual(future.covered, 600)
        XCTAssertNil(future.cities[visits[0].geography!.cityKey])
        let notStarted = GeographyTimeline.totals(samples: [], window: DateInterval(start: start, duration: 86400), legacyVisits: visits)
        XCTAssertEqual(notStarted.covered, 28800)
    }
    func testLayoutDefaultsPersistenceAndHiddenCards() {
        XCTAssertEqual(InsightCard.decodeLayout(""), [.summary, .visits, .geography])
        let custom: [InsightCard] = [.continents, .visits, .countries]
        XCTAssertEqual(InsightCard.decodeLayout(InsightCard.encodeLayout(custom)), custom)
        XCTAssertEqual(InsightCard.decodeLayout(InsightCard.encodeLayout([])), [])
        XCTAssertEqual(InsightCard.decodeLayout("visits,visits,unknown,placesMap,countries"), [.visits, .countries])
        XCTAssertFalse(InsightCard.defaults.contains(.countries))
        XCTAssertFalse(InsightCard.defaults.contains(.continents))
    }
    func testCountriesContinentsAndLegacyGeography() {
        let canada = Geography(city: "Waterloo", region: "ON", country: "Canada")
        XCTAssertEqual(canada.continentKey, "North America")
        XCTAssertEqual(Geography(country: "Brazil", countryCode: "BR").continentKey, "South America")
        XCTAssertEqual(Geography(country: "United Kingdom", countryCode: "GB").continentKey, "Europe")
        XCTAssertEqual(Geography(country: "India", countryCode: "IN").continentKey, "Asia")
        XCTAssertEqual(Geography(country: "Unrecognized").continentKey, "Unknown continent")
        let visits = Replay.day(start: start).0
        let cutoff = start.addingTimeInterval(86400)
        let t = GeographyTimeline.totals(samples: [], window: DateInterval(start: start, duration: 86400), legacyVisits: visits, cutover: cutoff)
        XCTAssertEqual(t.countries["Canada"], 28800)
        XCTAssertEqual(t.continents["North America"], 28800)
        let samples = Replay.geography(start: start)
        let new = GeographyTimeline.totals(samples: samples, window: DateInterval(start: start, duration: 86400))
        XCTAssertEqual(new.countries["Canada"], 3600)
        XCTAssertEqual(new.continents["North America"], 3600)
    }
    func testPendingVisitBadgeAndResolution() {
        var (visits, places) = Replay.day(start: start)
        XCTAssertFalse(PendingVisits.needsName(visits[0], places: places))
        XCTAssertEqual(PendingVisits.count(visits + visits, places: places), 1)
        visits[1].departure = nil
        XCTAssertEqual(PendingVisits.count(visits, places: places), 1)
        let place = SavedPlace(name: "Store", latitude: visits[1].latitude, longitude: visits[1].longitude, radius: 25)
        places.append(place)
        visits[1].accuracy = 100 // circle is uncertain until confirmed
        XCTAssertEqual(PendingVisits.count(visits, places: places), 1)
        visits[1].manualPlaceID = place.id
        XCTAssertEqual(PendingVisits.count(visits, places: places), 0)
        visits[1].manualPlaceID = nil; visits[1].manualUnassigned = true
        XCTAssertEqual(PendingVisits.count(visits, places: places), 0)
        XCTAssertEqual(PendingVisits.count([], places: places), 0)
    }
    func testOngoingVisitUpdatesAndReconcilesWithoutChangingHistory() {
        let completed = Visit(latitude: 0, longitude: 0, accuracy: 10, arrival: start, departure: start.addingTimeInterval(7200))
        var open = Visit(latitude: 1, longitude: 1, accuracy: 10, arrival: start.addingTimeInterval(10800))
        let now = start.addingTimeInterval(18000)
        let window = DateInterval(start: start, end: now)
        let live = Aggregation.totals(visits: [completed, open], places: [], window: window, includeTravel: true, ongoingUntil: now)
        XCTAssertEqual(live.ongoing, 7200)
        XCTAssertEqual(live.tracked, 14400)
        XCTAssertEqual(live.travel, 3600)
        XCTAssertEqual(live.accounted, 18000)
        XCTAssertEqual(live.missing, 0)
        let withoutTravel = Aggregation.totals(visits: [completed, open], places: [], window: window, ongoingUntil: now)
        XCTAssertEqual(withoutTravel.missing, live.missing)
        XCTAssertEqual(withoutTravel.accounted, 14400)
        XCTAssertEqual(withoutTravel.tracked + withoutTravel.travel + withoutTravel.missing, withoutTravel.elapsed)
        XCTAssertNil(open.departure)
        let later = now.addingTimeInterval(60)
        XCTAssertEqual(Aggregation.totals(visits: [completed, open], places: [], window: DateInterval(start: start, end: later), ongoingUntil: later).ongoing, 7260)
        open.departure = now.addingTimeInterval(-300)
        let final = Aggregation.totals(visits: [completed, open], places: [], window: window, ongoingUntil: now)
        let original = Aggregation.totals(visits: [completed, open], places: [], window: window)
        XCTAssertEqual(final.ongoing, 0)
        XCTAssertEqual(final.tracked, original.tracked)
        XCTAssertEqual(final.tracked, 14100)
    }
    func testOngoingClipsAtMidnightAndExcludesStaleOpenVisit() {
        let old = Visit(latitude: 0, longitude: 0, accuracy: 10, arrival: start.addingTimeInterval(-7200))
        let current = Visit(latitude: 1, longitude: 1, accuracy: 10, arrival: start.addingTimeInterval(-3600))
        let now = start.addingTimeInterval(3600)
        let yesterday = Aggregation.totals(visits: [old, current], places: [], window: DateInterval(start: start.addingTimeInterval(-86400), end: start), ongoingUntil: now)
        let today = Aggregation.totals(visits: [old, current], places: [], window: DateInterval(start: start, end: now), ongoingUntil: now)
        XCTAssertEqual(yesterday.ongoing, 3600)
        XCTAssertEqual(today.ongoing, 3600)
        var newer = current; newer.id = UUID(); newer.arrival = start; newer.departure = now
        XCTAssertNil(Aggregation.ongoingVisit(visits: [old, current, newer], now: now))
        XCTAssertEqual(Aggregation.totals(visits: [old, current, newer], places: [], window: DateInterval(start: start, end: now), ongoingUntil: now).ongoing, 0)
    }
    func testCoordinateCorrectionCompletesVisitAndPreservesAssignment() {
        let place = UUID()
        var visits = [Visit(latitude: 43.645, longitude: -79.3824, accuracy: 102, arrival: start, manualPlaceID: place)]
        let id = visits[0].id
        let event = Observation(received: start.addingTimeInterval(30000), latitude: 43.646, longitude: -79.3855, accuracy: 50, arrival: start, departure: start.addingTimeInterval(29000), source: "fixture")
        Reconciliation.ingest(event, into: &visits)
        XCTAssertEqual(visits.count, 1)
        XCTAssertEqual(visits[0].id, id)
        XCTAssertEqual(visits[0].manualPlaceID, place)
        XCTAssertEqual(visits[0].latitude, event.latitude)
        var late = event; late.departure = nil; late.latitude = 0
        Reconciliation.ingest(late, into: &visits)
        XCTAssertEqual(visits[0].departure, event.departure)
        XCTAssertEqual(visits[0].latitude, event.latitude)
    }
    func testRepairIsIdempotentAndRetainsOriginalRecords() {
        let open = Visit(latitude: 43.645, longitude: -79.3824, accuracy: 102, arrival: start, manualPlaceID: UUID())
        let completed = Visit(latitude: 43.646, longitude: -79.3855, accuracy: 50, arrival: start, departure: start.addingTimeInterval(3600), manualPlaceID: UUID())
        var archive = Archive(visits: [open, completed])
        Reconciliation.repair(&archive, at: start.addingTimeInterval(7200))
        XCTAssertEqual(archive.visits.count, 1)
        XCTAssertEqual(archive.visits[0].id, completed.id)
        XCTAssertEqual(archive.visits[0].manualPlaceID, completed.manualPlaceID)
        XCTAssertEqual(archive.supersededVisits?.first?.id, open.id)
        let cut = archive.geographyBackfillThrough
        Reconciliation.repair(&archive, at: start.addingTimeInterval(9999))
        XCTAssertEqual(archive.supersededVisits?.count, 1)
        XCTAssertEqual(archive.geographyBackfillThrough, cut)
    }
    func testStaleOpenDoesNotSuppressLaterTravel() {
        let v = Replay.travel(start: start)
        var stale = v[0]; stale.id = UUID(); stale.departure = nil
        let window = DateInterval(start: start, duration: 86400)
        XCTAssertEqual(Aggregation.travelIntervals(visits: [stale] + v, window: window).reduce(0) { $0 + $1.duration }, 28800)
        let later = Visit(latitude: 1, longitude: 1, accuracy: 10, arrival: start.addingTimeInterval(60000), departure: start.addingTimeInterval(65000))
        let next = Visit(latitude: 2, longitude: 2, accuracy: 10, arrival: start.addingTimeInterval(70000))
        XCTAssertTrue(Aggregation.travelIntervals(visits: [stale, later, next], window: window).contains { $0.start == later.departure && $0.end == next.arrival })
    }
    func testStationaryEvidenceSurvivesSparseReadingsButNotRestart() {
        let sample = GeographySample(timestamp: start, received: start, latitude: 0, longitude: 0, accuracy: 10, session: UUID(), geography: Geography(city: "Waterloo", region: "ON", country: "Canada"))
        let stay = StationaryStay(start: start, confirmed: start.addingTimeInterval(900), sampleID: sample.id, session: sample.session)
        let window = DateInterval(start: start, duration: 7200)
        let active = GeographyTimeline.totals(samples: [sample], window: window, stationary: [stay], activeSession: sample.session)
        XCTAssertEqual(active.covered, 7200)
        XCTAssertEqual(active.stationaryEstimated, 7200)
        let restarted = GeographyTimeline.totals(samples: [sample], window: window, stationary: [stay], activeSession: UUID())
        XCTAssertEqual(restarted.covered, 900)
        var finished = stay; finished.end = start.addingTimeInterval(3600)
        XCTAssertEqual(GeographyTimeline.totals(samples: [sample], window: window, stationary: [finished]).covered, 3600)
    }
    func testFreshAreaAnchorDoesNotRequirePauseOrVisit() {
        let session = UUID()
        var sample = GeographySample(timestamp: start, received: start, latitude: 43.47, longitude: -80.5, accuracy: 8, session: session)
        XCTAssertEqual(GeographyAreaTracking.radius(for: sample, now: start, session: session), 200)
        XCTAssertNil(GeographyAreaTracking.radius(for: sample, now: start.addingTimeInterval(1800), session: session))
        XCTAssertNil(GeographyAreaTracking.radius(for: sample, now: start, session: UUID()))
        sample.accuracy = 1000
        XCTAssertNil(GeographyAreaTracking.radius(for: sample, now: start, session: session))
        sample.accuracy = 200
        XCTAssertEqual(GeographyAreaTracking.radius(for: sample, now: start, session: session), 450)
    }
    func testConfirmedAreaCoversQuietDayFromConfirmationAndStopsAtExit() {
        let sample = GeographySample(timestamp: start, received: start, latitude: 43.47, longitude: -80.5, accuracy: 8, session: UUID(), geography: Geography(city: "Waterloo", region: "ON", country: "Canada"))
        let confirmed = start.addingTimeInterval(10)
        var stay = GeographyAreaTracking.confirmInside(sample: sample, radius: 200, at: confirmed)
        let end = start.addingTimeInterval(18 * 3600)
        let live = GeographyTimeline.totals(samples: [sample], window: DateInterval(start: start, end: end), stationary: [stay], activeSession: sample.session)
        XCTAssertEqual(live.cities[sample.geography!.cityKey], 18 * 3600 - 10)
        XCTAssertEqual(live.missing, 10)
        stay.end = end
        let later = GeographyTimeline.totals(samples: [sample], window: DateInterval(start: start, duration: 20 * 3600), stationary: [stay], activeSession: sample.session)
        XCTAssertEqual(later.covered, live.covered)
        XCTAssertEqual(later.missing, 2 * 3600 + 10)
    }
    func testAreaFixKeepsLocalEvidenceAndReplacesOutsideOrAccurateEdge() {
        let sample = GeographySample(timestamp: start, received: start, latitude: 43.47, longitude: -80.5, accuracy: 8, session: UUID())
        var fresh = sample; fresh.id = UUID(); fresh.latitude += 0.0001
        XCTAssertEqual(GeographyAreaTracking.action(for: fresh, anchor: sample, radius: 200), .keep)
        fresh.latitude += 0.01
        XCTAssertEqual(GeographyAreaTracking.action(for: fresh, anchor: sample, radius: 200), .replace)
        fresh.latitude = sample.latitude; fresh.accuracy = 1000
        XCTAssertEqual(GeographyAreaTracking.action(for: fresh, anchor: sample, radius: 200), .wait)
        fresh.accuracy = -1
        XCTAssertEqual(GeographyAreaTracking.action(for: fresh, anchor: sample, radius: 200), .wait)
    }
    func testAreaEvidenceDoesNotInventTravelOrBridgeRestart() {
        let session = UUID()
        let home = GeographySample(timestamp: start, received: start, latitude: 43.47, longitude: -80.5, accuracy: 8, session: session, geography: Geography(city: "Waterloo", region: "ON", country: "Canada"))
        let away = GeographySample(timestamp: start.addingTimeInterval(19 * 3600), received: start, latitude: 43.4, longitude: -80.3, accuracy: 10, session: session, geography: Geography(city: "Cambridge", region: "ON", country: "Canada"))
        var first = GeographyAreaTracking.confirmInside(sample: home, radius: 200, at: start)
        first.end = start.addingTimeInterval(18 * 3600)
        let second = GeographyAreaTracking.confirmInside(sample: away, radius: 200, at: away.timestamp)
        let window = DateInterval(start: start, duration: 20 * 3600)
        let t = GeographyTimeline.totals(samples: [home, away], window: window, stationary: [first, second], activeSession: session)
        XCTAssertEqual(t.cities[home.geography!.cityKey], 18 * 3600)
        XCTAssertEqual(t.cities[away.geography!.cityKey], 3600)
        XCTAssertEqual(t.missing, 3600)
        let restarted = GeographyTimeline.totals(samples: [home, away], window: window, stationary: [first, second], activeSession: UUID())
        XCTAssertEqual(restarted.covered, 18 * 3600)
    }
    func testAreaRepairPreservesRawHistoryAndOnlyAdvancesCutoffOnce() throws {
        let (visits, places) = Replay.day(start: start)
        let samples = Replay.geography(start: start)
        var archive = Archive(visits: visits, places: places, enabled: true, geographySamples: samples, geographyStartedAt: start, geographyBackfillThrough: start)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let beforeVisits = try encoder.encode(archive.visits), beforeSamples = try encoder.encode(samples)
        let cutoff = start.addingTimeInterval(4 * 3600)
        GeographyAreaTracking.repair(&archive, through: cutoff)
        GeographyAreaTracking.repair(&archive, through: cutoff.addingTimeInterval(3600))
        XCTAssertEqual(archive.geographyBackfillThrough, cutoff)
        XCTAssertEqual(archive.geographyAreaVersion, 1)
        XCTAssertEqual(try encoder.encode(archive.visits), beforeVisits)
        XCTAssertEqual(try encoder.encode(archive.geographySamples!), beforeSamples)
        let t = GeographyTimeline.totals(samples: samples, window: DateInterval(start: start, duration: 8 * 3600), legacyVisits: visits, cutover: start, backfillThrough: archive.geographyBackfillThrough)
        XCTAssertEqual(t.covered, 4 * 3600)
        XCTAssertGreaterThan(t.visitEstimated, 0)
    }
    func testBackfillOnlyFillsUncoveredTimeUntilFixedCutoff() {
        let v = Replay.day(start: start).0
        let samples = Replay.geography(start: start)
        let cutoff = start.addingTimeInterval(14400)
        let t = GeographyTimeline.totals(samples: samples, window: DateInterval(start: start, duration: 28800), legacyVisits: v, cutover: start, backfillThrough: cutoff)
        XCTAssertEqual(t.covered, 14400)
        XCTAssertEqual(t.visitEstimated, 10800)
        XCTAssertEqual(t.cities.values.reduce(0, +), t.covered)
        XCTAssertEqual(t.countries.values.reduce(0, +), t.covered)
        XCTAssertEqual(t.missing, 14400)
    }
    func testSuggestedNameReusesExistingPlaceBeyondOldFiftyMeterLimit() {
        var visits = [Visit(latitude: 1, longitude: 1, accuracy: 500, arrival: start)]
        let saved = SavedPlace(name: "Kitchener Station", latitude: 0, longitude: 0, radius: 150)
        var places = [saved]
        let suggestion = PlaceSuggestion(name: "  kitchener   STATION ", address: "Station", latitude: 1, longitude: 1, distance: 0, applePlaceID: "station-id")
        XCTAssertTrue(PlaceSuggestions.confirm(suggestion, visitID: visits[0].id, radius: 500, visits: &visits, places: &places))
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(visits[0].manualPlaceID, saved.id)
        XCTAssertEqual(places[0].radius, 150)
        XCTAssertEqual(places[0].latitude, 0)
        XCTAssertEqual(places[0].applePlaceID, "station-id")
        XCTAssertEqual(places[0].name, "Kitchener Station")
    }
    func testCustomDuplicateNameRejectedWithoutMutatingVisit() {
        var visits = Replay.day(start: start).0
        var places = [SavedPlace(name: "Union Station", latitude: 1, longitude: 1, radius: 150)]
        let result = PlaceNaming.saveCustom(name: " UNION   station ", visitID: visits[0].id, radius: 900, visits: &visits, places: &places)
        XCTAssertEqual(result, .duplicate(places[0].id))
        XCTAssertEqual(places.count, 1)
        XCTAssertNil(visits[0].manualPlaceID)
        XCTAssertEqual(PlaceNaming.saveCustom(name: "New place", visitID: visits[0].id, radius: 150, visits: &visits, places: &places), .saved(places.last!.id))
        XCTAssertEqual(places.count, 2)
        XCTAssertEqual(visits[0].manualPlaceID, places[1].id)
    }
    func testDuplicatePlaceRepairPreservesTimeAndRedirectsAssignments() {
        var visits = Replay.day(start: start).0
        let a = SavedPlace(name: "Union Station", latitude: 0, longitude: 0, radius: 100)
        let b = SavedPlace(name: "union station", latitude: 1, longitude: 1, radius: 200)
        visits[0].manualPlaceID = a.id; visits[1].manualPlaceID = b.id
        var archive = Archive(visits: visits, places: [a,b], repairVersion: 1)
        PlaceNaming.repair(&archive)
        XCTAssertEqual(archive.places.count, 1)
        XCTAssertEqual(archive.places[0].id, a.id)
        XCTAssertEqual(archive.visits.map(\.manualPlaceID), [a.id,a.id])
        XCTAssertEqual(archive.supersededPlaces?.first?.id, b.id)
        let t = Aggregation.totals(visits: archive.visits, places: archive.places, window: DateInterval(start: start, duration: 86400))
        XCTAssertEqual(t.places["Union Station"], 28800)
        PlaceNaming.repair(&archive)
        XCTAssertEqual(archive.supersededPlaces?.count, 1)
        XCTAssertEqual(archive.repairVersion, 2)
    }
    func testApplePlaceIdentityReusesCustomName() {
        var visits = [Visit(latitude: 1, longitude: 1, accuracy: 500, arrival: start)]
        let saved = SavedPlace(name: "My station", latitude: 0, longitude: 0, radius: 150, applePlaceID: "station-id")
        var places = [saved]
        let suggestion = PlaceSuggestion(name: "Official Station", address: "Station", latitude: 1, longitude: 1, distance: 0, applePlaceID: "station-id")
        XCTAssertTrue(PlaceSuggestions.confirm(suggestion, visitID: visits[0].id, radius: 500, visits: &visits, places: &places))
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places[0].name, "My station")
        XCTAssertEqual(visits[0].manualPlaceID, saved.id)
    }
    func testEmptyAndUnknownArrival() {
        let v = Visit(latitude: 0, longitude: 0, accuracy: 10, departure: start.addingTimeInterval(3600))
        let t = Aggregation.totals(visits: [v], places: [], window: DateInterval(start: start, duration: 86400))
        XCTAssertEqual(t.tracked, 0)
        XCTAssertEqual(t.missing, 86400)
    }
}
