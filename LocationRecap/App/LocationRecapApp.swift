import SwiftUI
import MapKit

@main struct LocationRecapApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--map-cluster-preview") {
                    MapClusterPreview()
                } else {
                    ContentView()
                }
#else
                ContentView()
#endif
            }.environmentObject(store)
                .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in store.refresh() }
        }
            .onChange(of: phase) { _, value in if value == .active { store.refresh(); Task { await store.resolveUnknown() } } }
    }
}
func duration(_ seconds: Double) -> String {
    let minutes = max(0, Int(seconds) / 60)
    return minutes < 60 ? "\(minutes) m" : "\(minutes / 60) h \(minutes % 60) m"
}
func detailPercent(_ seconds: Double, total: Double) -> String {
    (total > 0 ? seconds / total : 0).formatted(.percent.precision(.fractionLength(2)))
}
struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var grain: PeriodGrain = .day
    @State private var selectedDate = Date()
    @State private var replay = 0
    @State private var includeTravel = false
    var body: some View {
        TabView {
            Dashboard(grain: $grain, selectedDate: $selectedDate, replay: $replay, includeTravel: $includeTravel).tabItem { Label("Recap", systemImage: "chart.bar.fill") }
            VisitList().tabItem { Label("Visits", systemImage: "mappin.and.ellipse") }
                .badge(PendingVisits.count(store.data.visits, places: store.data.places))
            MapDashboard(grain: $grain, selectedDate: $selectedDate, replay: $replay, includeTravel: $includeTravel)
                .tabItem { Label("Map", systemImage: "map.fill") }
            SettingsView().tabItem { Label("Capture", systemImage: "location.fill") }
        }.tint(.teal)
    }
}
struct Dashboard: View {
    @EnvironmentObject var store: Store
    @Binding var grain: PeriodGrain
    @Binding var selectedDate: Date
    @Binding var replay: Int
    @Binding var includeTravel: Bool
    @State private var editingLayout = false
    @AppStorage("recap.layout.v1") private var layoutValue = ""
    private var cards: [InsightCard] { InsightCard.decodeLayout(layoutValue) }
    private var layoutBinding: Binding<[InsightCard]> {
        Binding(get: { cards }, set: { layoutValue = InsightCard.encodeLayout($0) })
    }
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let start = Calendar.current.startOfDay(for: context.date)
                let fixture = Replay.day(start: start)
                let visits = replay == 1 ? fixture.0 : replay == 2 ? Replay.travel(start: start) : store.data.visits
                let places = replay == 1 ? fixture.1 : replay == 2 ? [] : store.data.places
                let window = replay == 0 ? Aggregation.window(containing: selectedDate, grain: grain, now: context.date) : DateInterval(start: start, duration: 86400)
                let t = Aggregation.totals(visits: visits, places: places, window: window, includeTravel: includeTravel, ongoingUntil: replay == 0 ? context.date : nil)
                let geography = GeographyTimeline.totals(samples: replay == 0 ? (store.data.geographySamples ?? []) : Replay.geography(start: start), window: window, legacyVisits: replay == 0 ? store.data.visits : [], cutover: replay == 0 ? store.data.geographyStartedAt : nil, stationary: replay == 0 ? (store.data.stationaryStays ?? []) : [], activeSession: replay == 0 ? store.geographySession : nil, backfillThrough: replay == 0 ? store.data.geographyBackfillThrough : nil)
                List {
                    Section {
                        Picker("Data", selection: $replay) { Text("My iPhone").tag(0); Text("Sample day").tag(1); Text("Travel replay").tag(2) }
                    }
                    if replay == 0 {
                        RecapPeriodPicker(grain: $grain, selectedDate: $selectedDate, now: context.date, window: window)
                    }
                    Section {
                        Toggle("Include travel time", isOn: $includeTravel)
                    }
                    ForEach(cards) { card in
                        insight(card, totals: t, geography: geography, visits: visits, window: window)
                    }
                    Section { Text("Cities and regions share an independent location timeline. Saved places use visits, optionally including travel. Do not add these views together. ISO calendar, Monday week start, current device time zone: \(TimeZone.current.identifier). Geography estimates the stop location.").font(.caption).foregroundStyle(.secondary) }
                }.navigationTitle("Location Recap")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { editingLayout = true } label: { Image(systemName: "rectangle.3.group") }
                                .accessibilityLabel("Edit layout")
                        }
                    }
                    .sheet(isPresented: $editingLayout) { LayoutEditor(cards: layoutBinding) }
            }
        }
    }
    @ViewBuilder private func insight(_ card: InsightCard, totals t: Totals, geography: GeographyTotals, visits: [Visit], window: DateInterval) -> some View {
        switch card {
        case .summary:
                    Section(replay == 0 ? "Your time, accounted for" : "Synthetic replay · 24 hours") {
                        Text(duration(t.accounted)).font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(.teal)
                        Text("\(duration(t.accounted)) of \(duration(t.elapsed)) elapsed")
                        ProgressView(value: t.elapsed > 0 ? t.accounted / t.elapsed : 0)
                            .accessibilityValue(detailPercent(t.accounted, total: t.elapsed))
                        LabeledContent("Unaccounted for", value: duration(t.missing))
                        if includeTravel {
                            LabeledContent("Visit time", value: duration(t.tracked))
                            LabeledContent("Included travel", value: duration(t.travel))
                        } else if t.travel > 0 {
                            LabeledContent("Travel excluded", value: duration(t.travel))
                        }
                        if t.ongoing > 0 {
                            Label("Includes \(duration(t.ongoing)) ongoing · estimated", systemImage: "clock")
                                .font(.caption.weight(.semibold)).foregroundStyle(.teal)
                        }
                        Text(includeTravel ? "Visit time + estimated travel. Ongoing time is corrected when departure arrives." : "Visit time includes the current stay estimate, updated every minute.").font(.caption).foregroundStyle(.secondary)
                    }
        case .visits:
                    Section {
                        ForEach(t.places.keys.sorted { t.places[$0]! > t.places[$1]! }, id: \.self) { key in
                            VStack(alignment: .leading, spacing: 4) {
                                timeRow(key, seconds: t.places[key]!, total: t.accounted, basis: includeTravel ? "accounted-for time" : "tracked time")
                                if t.ongoingPlaces.contains(key) {
                                    Text("Includes ongoing estimate").font(.caption).foregroundStyle(.teal)
                                }
                            }
                        }
                        if includeTravel {
                            timeRow("Travel", seconds: t.travel, total: t.accounted, basis: "accounted-for time")
                            DisclosureGroup("Travel intervals") {
                                Text("Estimated from time between visits.").font(.caption).foregroundStyle(.secondary)
                                let intervals = Aggregation.travelIntervals(visits: visits, window: window)
                                if intervals.isEmpty { Text("No travel between recorded stops in this period.").font(.caption) }
                                ForEach(intervals, id: \.start) { interval in
                                    VStack(alignment: .leading) {
                                        Text("\(interval.start.formatted(date: .abbreviated, time: .shortened)) → \(interval.end.formatted(date: .abbreviated, time: .shortened))")
                                        Text(duration(interval.duration)).foregroundStyle(.secondary)
                                    }.font(.caption)
                                }
                            }
                        }
                        Text(includeTravel ? "All accounted-for time: visits, ongoing estimates and estimated travel. Unaccounted time is shown above. Percentages may differ slightly from 100% due to rounding." : "Visits include the current stay estimate. Turn on Include travel time to add time between visits.")
                            .font(.caption).foregroundStyle(.secondary)
                    } header: {
                        breakdownHeader("Visits Breakdown")
                    }
                    if t.accounted == 0 { ContentUnavailableView("No visits in this period", systemImage: "calendar", description: Text("Choose another period to see earlier history. A current stay counts as estimated time until departure is reported. Your saved places are listed in Capture.")) }
        case .geography:
                    Section {
                        if geography.visitEstimated > 0 {
                            Text("Includes \(duration(geography.visitEstimated)) estimated from recorded visits to restore earlier coverage.").font(.caption).foregroundStyle(.secondary)
                        }
                        if geography.stationaryEstimated > 0 {
                            Text("Includes \(duration(geography.stationaryEstimated)) estimated within monitored location areas.").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Cities").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(geography.cities.keys.sorted { geography.cities[$0]! > geography.cities[$1]! }, id: \.self) { key in
                            timeRow(key, seconds: geography.cities[key]!, total: geography.covered, basis: "location-covered time")
                        }
                        Text("Regions").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(geography.regions.keys.sorted { geography.regions[$0]! > geography.regions[$1]! }, id: \.self) { key in
                            timeRow(key, seconds: geography.regions[key]!, total: geography.covered, basis: "location-covered time")
                        }
                    } header: {
                        breakdownHeader("Geography Breakdown")
                    }
        case .countries:
            geographicCard("Country Breakdown", values: geography.countries, total: geography.covered)
        case .continents:
            geographicCard("Continent Breakdown", values: geography.continents, total: geography.covered)

        }
    }
    private func geographicCard(_ title: String, values: [String: Double], total: Double) -> some View {
        Section {
            if values.isEmpty { Text("No geography recorded in this period.").foregroundStyle(.secondary) }
            ForEach(values.keys.sorted { values[$0]! > values[$1]! }, id: \.self) { key in
                timeRow(key, seconds: values[key]!, total: total, basis: "location-covered time")
            }
        } header: { breakdownHeader(title) }
    }
    private func breakdownHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .textCase(nil)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
    private func timeRow(_ name: String, seconds: Double, total: Double, basis: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
            Text("\(duration(seconds)) · \(detailPercent(seconds, total: total)) of \(basis)")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
    func rows(_ title: String, values: [String: Double], total: Double, basis: String? = nil) -> some View {
        Section(title) {
            ForEach(values.keys.sorted { values[$0]! > values[$1]! }, id: \.self) { key in
                VStack(alignment: .leading, spacing: 6) {
                    Text(key)
                    Text("\(duration(values[key]!)) · \(detailPercent(values[key]!, total: total)) of \(basis ?? (includeTravel ? "accounted-for time" : "tracked time"))").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
        }
    }
}
struct RecapPeriodPicker: View {
    @Binding var grain: PeriodGrain
    @Binding var selectedDate: Date
    let now: Date
    let window: DateInterval
    var body: some View {
        Section("Period") {
            Picker("Group by", selection: $grain) {
                ForEach(PeriodGrain.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                Button { selectedDate = grain.shifted(from: selectedDate, by: -1) } label: {
                    Image(systemName: "chevron.left").padding(8)
                }.buttonStyle(.borderless).accessibilityLabel("Previous \(grain.rawValue.lowercased())")
                Spacer()
                Text(periodLabel).font(.headline).multilineTextAlignment(.center)
                Spacer()
                Button { selectedDate = grain.shifted(from: selectedDate, by: 1) } label: {
                    Image(systemName: "chevron.right").padding(8)
                }.buttonStyle(.borderless)
                    .accessibilityLabel("Next \(grain.rawValue.lowercased())")
                    .disabled(grain.interval(containing: selectedDate).end > now)
            }
            DatePicker(grain == .day ? "Choose day" : "Choose date in \(grain.rawValue.lowercased())", selection: $selectedDate, in: ...now, displayedComponents: .date)
            Button("Go to current \(grain.rawValue.lowercased())") { selectedDate = now }
                .disabled(grain.interval(containing: selectedDate).start == grain.interval(containing: now).start)
            Text("\(window.start.formatted(date: .abbreviated, time: .shortened)) → \(window.end.formatted(date: .abbreviated, time: .shortened)) · \(TimeZone.current.identifier)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var periodLabel: String { Self.label(grain: grain, date: selectedDate) }
    static func label(grain: PeriodGrain, date: Date) -> String {
        let period = grain.interval(containing: date)
        let lastDay = PeriodGrain.calendar().date(byAdding: .day, value: -1, to: period.end)!
        switch grain {
        case .day: return period.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        case .week: return "\(period.start.formatted(.dateTime.month(.abbreviated).day().year())) – \(lastDay.formatted(.dateTime.month(.abbreviated).day().year()))"
        case .month: return period.start.formatted(.dateTime.month(.wide).year())
        case .year: return period.start.formatted(.dateTime.year())
        }
    }
}
struct LayoutEditor: View {
    @Binding var cards: [InsightCard]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Period picker and travel toggle stay at the top", systemImage: "pin.fill")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Visible insights · drag to reorder") {
                    if cards.isEmpty { Text("Add an insight below to build your layout.").foregroundStyle(.secondary) }
                    ForEach(cards) { card in
                        HStack(alignment: .top, spacing: 12) {
                            Button {
                                withAnimation { cards.removeAll { $0 == card } }
                            } label: {
                                Image(systemName: "minus.circle.fill").font(.title2).foregroundStyle(.red)
                            }.buttonStyle(.borderless).accessibilityLabel("Hide \(card.title)")
                            Text(card.title).font(.headline).padding(.top, 3)
                        }.padding(.vertical, 8)
                    }.onMove { from, to in cards.move(fromOffsets: from, toOffset: to) }
                }
                Section("Available insights") {
                    ForEach(InsightCard.allCases.filter { !cards.contains($0) }) { card in
                        HStack(alignment: .top, spacing: 12) {
                            Button {
                                withAnimation { cards.append(card) }
                            } label: {
                                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.teal)
                            }.buttonStyle(.borderless).accessibilityLabel("Add \(card.title)")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.title).font(.headline)
                                if card == .countries || card == .continents {
                                    Text("Uses your geography timeline").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.top, 3)
                        }.padding(.vertical, 8)
                    }
                }
                Section { Button("Reset to default layout") { withAnimation { cards = InsightCard.defaults } } }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
struct VisitList: View {
    @EnvironmentObject var store: Store
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
            List {
                if store.data.visits.isEmpty { Text("No visits received yet. Core Location detects stops, not every movement.") }
                ForEach(Reconciliation.canonical(store.data.visits).reversed()) { visit in
                    NavigationLink { VisitDetail(id: visit.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            if PendingVisits.needsName(visit, places: store.data.places) {
                                Label("Name this visit", systemImage: "exclamationmark.circle.fill")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                            }
                            if case .assigned(let placeID) = Matching.place(visit, in: store.data.places),
                               let place = store.data.places.first(where: { $0.id == placeID }) {
                                Text(place.name).font(.headline)
                                Text(visit.geography?.cityKey ?? "Unknown geography").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(visit.geography?.cityKey ?? "Unknown geography").font(.headline)
                            }
                            Text("Arrival: \(visit.arrival?.formatted() ?? "Not reported")").font(.subheadline)
                            Text("Departure: \(visit.departure?.formatted() ?? "Not reported yet")").font(.subheadline).foregroundStyle(.secondary)
                            if visit.departure == nil {
                                let latestArrival = store.data.visits.compactMap(\.arrival).max()
                                if let arrival = visit.arrival, arrival == latestArrival {
                                    Label("Latest detected stop", systemImage: "location.fill")
                                        .font(.caption.weight(.semibold)).foregroundStyle(.teal)
                                    if Aggregation.ongoingVisit(visits: store.data.visits, now: context.date)?.id == visit.id {
                                        Text("\(duration(context.date.timeIntervalSince(arrival))) so far · estimated")
                                            .font(.caption).foregroundStyle(.teal)
                                    }
                                } else {
                                    Label("Awaiting departure update", systemImage: "clock")
                                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                    .listRowBackground(rowBackground(visit))
                }
            }.navigationTitle("Recorded visits")
            }
        }
    }
    private func rowBackground(_ visit: Visit) -> Color {
        if isLatestStop(visit) { return Color(uiColor: .systemGray4) }
        if PendingVisits.needsName(visit, places: store.data.places) { return Color.orange.opacity(0.12) }
        return Color(uiColor: .secondarySystemGroupedBackground)
    }
    private func isLatestStop(_ visit: Visit) -> Bool {
        guard visit.departure == nil, let arrival = visit.arrival else { return false }
        return arrival == store.data.visits.compactMap(\.arrival).max()
    }
}
struct VisitDetail: View {
    @EnvironmentObject var store: Store
    let id: UUID
    @State private var name = ""
    @State private var radius = 150.0
    @StateObject private var nearby = NearbyPlaceSearch()
    @State private var pendingSuggestion: PlaceSuggestion?
    @State private var duplicatePlaceID: UUID?
    var body: some View {
        if let index = store.data.visits.firstIndex(where: { $0.id == id }) {
            let v = store.data.visits[index]
            let center = CLLocationCoordinate2D(latitude: v.latitude, longitude: v.longitude)
            Form {
                Section {
                    Map(initialPosition: .region(MKCoordinateRegion(center: center, latitudinalMeters: 2000, longitudinalMeters: 2000))) {
                        Marker("Visit", coordinate: center)
                        MapCircle(center: center, radius: radius).foregroundStyle(.teal.opacity(0.2))
                        ForEach(nearby.suggestions) { suggestion in
                            Marker(suggestion.name, coordinate: CLLocationCoordinate2D(latitude: suggestion.latitude, longitude: suggestion.longitude)).tint(.orange)
                        }
                    }.frame(height: 260)
                    Text("Accuracy: ±\(Int(v.accuracy)) m · \(v.latitude), \(v.longitude)").font(.caption)
                }
                if PlaceSuggestions.canSuggest(v, places: store.data.places) {
                    Section("Suggested places · Apple Maps") {
                        Text("Nearby options, not a confirmed location. Choose a name to save and assign this visit, or enter your own below.").font(.caption).foregroundStyle(.secondary)
                        if nearby.loading { ProgressView("Finding nearby places…") }
                        ForEach(nearby.suggestions) { suggestion in
                            Button { pendingSuggestion = suggestion } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(suggestion.name).font(.headline)
                                    Text("\(Int(suggestion.distance.rounded())) m from visit · \(suggestion.address)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let message = nearby.message { Text(message).font(.caption) }
                        Button("Retry nearby search") { Task { await nearby.load(for: v) } }.disabled(nearby.loading)
                        Text("Search sends this visit’s coordinates to Apple. Saved places change only when you confirm. New circles use the radius below.").font(.caption).foregroundStyle(.secondary)
                    }
                    .task(id: id) { await nearby.load(for: v) }
                    .onDisappear { nearby.cancel() }
                }
                Section("Save a custom place at this visit") {
                    TextField("Home, Work, Gym…", text: $name)
                    Slider(value: $radius, in: 25...1000, step: 25)
                    Text("Radius: \(Int(radius)) meters")
                    Button("Save and assign") {
                        var updated = store.data
                        switch PlaceNaming.saveCustom(name: name, visitID: id, radius: radius, visits: &updated.visits, places: &updated.places) {
                        case .saved:
                            store.data = updated
                            store.persist()
                            name = ""
                        case .duplicate(let placeID): duplicatePlaceID = placeID
                        case .invalid: break
                        }
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Section("Correct this visit") {
                    Text("Automatic match: \(matchLabel(v))").font(.caption)
                    Picker("Assignment", selection: Binding(get: { v.manualUnassigned ? "none" : v.manualPlaceID?.uuidString ?? "auto" }, set: { value in
                        store.data.visits[index].manualUnassigned = value == "none"
                        store.data.visits[index].manualPlaceID = UUID(uuidString: value)
                        store.persist()
                    })) {
                        Text("Automatic").tag("auto")
                        Text("No saved place").tag("none")
                        ForEach(store.data.places) { Text($0.name).tag($0.id.uuidString) }
                    }
                }
            }.navigationTitle("Visit details")
                .alert("Save and assign this place?", isPresented: Binding(get: { pendingSuggestion != nil }, set: { if !$0 { pendingSuggestion = nil } })) {
                    Button("Save and assign") {
                        if let suggestion = pendingSuggestion {
                            var updated = store.data
                            if PlaceSuggestions.confirm(suggestion, visitID: id, radius: radius, visits: &updated.visits, places: &updated.places) {
                                store.data = updated
                                store.persist()
                            }
                        }
                        pendingSuggestion = nil
                    }
                    Button("Cancel", role: .cancel) { pendingSuggestion = nil }
                } message: {
                    Text("\(pendingSuggestion?.name ?? "")\n\(pendingSuggestion?.address ?? "")\nAn existing saved location with this name will be reused; its circle stays unchanged.")
                }
                .alert("Location already exists", isPresented: Binding(get: { duplicatePlaceID != nil }, set: { if !$0 { duplicatePlaceID = nil } })) {
                    Button("Use existing location") {
                        if let placeID = duplicatePlaceID {
                            store.data.visits[index].manualPlaceID = placeID
                            store.data.visits[index].manualUnassigned = false
                            store.persist()
                            name = ""
                        }
                        duplicatePlaceID = nil
                    }
                    Button("Cancel", role: .cancel) { duplicatePlaceID = nil }
                } message: {
                    Text("A location named \"\(store.data.places.first(where: { $0.id == duplicatePlaceID })?.name ?? name)\" already exists. Use it for this visit or choose a different name.")
                }
        }
    }
    func matchLabel(_ v: Visit) -> String {
        switch Matching.place(v, in: store.data.places) {
        case .none: return "No saved place"
        case .ambiguous: return "Ambiguous · confirm below"
        case .assigned(let id): return store.data.places.first(where: { $0.id == id })?.name ?? "Unknown"
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject var store: Store
    var permission: String {
        switch store.authorization {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "While using · enable Always in Settings"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        default: return "Not requested"
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section("Background capture") {
                    Text("Allow Always access so iOS can deliver stops while your phone is locked. Visits stay on this iPhone. Apple receives coordinates when resolving geography or searching for nearby place suggestions.")
                    LabeledContent("Permission", value: permission)
                    LabeledContent("Accuracy", value: store.precise ? "Precise" : "Reduced")
                    LabeledContent("Capture requested", value: store.data.enabled ? "Enabled" : "Disabled")
                    Text("Background readiness: \(store.data.enabled && store.authorization == .authorizedAlways ? "Ready for device trial" : "Setup required")")
                    Button("Enable capture / request Always", action: store.enable)
                    Button("Disable capture", action: store.disable)
                    Link("Open app Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    Text("Force-quitting, shutdown, revoked permission and delayed delivery can leave gaps. Reopen to resume; missing time is never inferred.").font(.caption)
                }
                if let error = store.persistenceError { Section("Storage error") { Text(error).foregroundStyle(.red) } }
                Section("Geography") {
                    LabeledContent("Sampler", value: store.geographyStatus)
                    LabeledContent("Location readings", value: "\(store.data.geographySamples?.count ?? 0)")
                    if let repaired = store.data.supersededVisits, !repaired.isEmpty {
                        LabeledContent("Archived duplicate visits", value: "\(repaired.count)")
                    }
                    if let sample = store.data.geographySamples?.last {
                        Text("Last reading: \(sample.timestamp.formatted()) · ±\(Int(sample.accuracy)) m").font(.caption)
                    }
                    if let resolved = store.data.geographySamples?.last(where: { $0.geography != nil }) {
                        Text("Last resolved geography: \(resolved.geography!.cityKey) at \(resolved.timestamp.formatted())").font(.caption)
                    }
                    Text("Fresh readings establish a low-power monitored area, so city time can continue while stationary. Area exits and new readings update it. Time is estimated; delayed updates, restarts or unavailable monitoring can leave gaps. Low Power Mode uses coarser readings.").font(.caption).foregroundStyle(.secondary)
                    Button(store.resolving ? "Resolving…" : "Retry unknown geography") { Task { await store.resolveUnknown() } }.disabled(store.resolving)
                }
                Section("Saved places") {
                    ForEach(store.data.places) { p in
                        VStack(alignment: .leading) { Text(p.name); Text("\(Int(p.radius)) m radius").font(.caption)
                            Slider(value: Binding(get: { p.radius }, set: { value in if let i = store.data.places.firstIndex(where: { $0.id == p.id }) { store.data.places[i].radius = value; store.persist() } }), in: 25...1000, step: 25)
                        }
                    }
                }
                Section("Raw observations · \(store.data.observations.count)") {
                    ForEach(store.data.observations.reversed()) { o in
                        VStack(alignment: .leading) {
                            Text("Received \(o.received.formatted())")
                            Text("\(o.source) · \(o.latitude), \(o.longitude) ±\(Int(o.accuracy)) m")
                            Text("Arrival: \(o.arrival?.formatted() ?? "unknown")\nDeparture: \(o.departure?.formatted() ?? "open")")
                        }.font(.caption)
                    }
                }
                Section("Diagnostics") { ForEach(Array(store.data.diagnostics.reversed().enumerated()), id: \.offset) { _, text in Text(text).font(.caption) } }
            }.navigationTitle("Capture & diagnostics")
        }
    }
}
