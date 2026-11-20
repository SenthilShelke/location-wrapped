import SwiftUI
import MapKit

struct MapDashboard: View {
    @EnvironmentObject var store: Store
    @Binding var grain: PeriodGrain
    @Binding var selectedDate: Date
    @Binding var replay: Int
    @Binding var includeTravel: Bool
    @State private var choosingPeriod = false
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let start = Calendar.current.startOfDay(for: context.date)
                let fixture = Replay.day(start: start)
                let visits = replay == 1 ? fixture.0 : replay == 2 ? Replay.travel(start: start) : store.data.visits
                let places = replay == 1 ? fixture.1 : replay == 2 ? [] : store.data.places
                let window = replay == 0 ? Aggregation.window(containing: selectedDate, grain: grain, now: context.date) : DateInterval(start: start, duration: 86400)
                let totals = Aggregation.totals(visits: visits, places: places, window: window, includeTravel: includeTravel, ongoingUntil: replay == 0 ? context.date : nil)
                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        Button { choosingPeriod = true } label: {
                            HStack {
                                Label(replay == 0 ? RecapPeriodPicker.label(grain: grain, date: selectedDate) : replay == 1 ? "Sample day" : "Travel replay", systemImage: "calendar")
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                            }.frame(minHeight: 44)
                        }.accessibilityHint("Choose day, week, month or year")
                        Toggle("Include travel time", isOn: $includeTravel).font(.subheadline)
                    }.padding(.horizontal).padding(.bottom, 12)
                    PlacesMapInsight(items: PlaceMapItem.items(places: places, totals: totals), total: totals.accounted,
                        travel: includeTravel ? totals.travel : nil,
                        unmapped: max(0, totals.tracked - totals.savedPlaceSeconds.values.reduce(0, +)),
                        framingKey: "\(replay)-\(grain.rawValue)-\(window.start.timeIntervalSince1970)")
                }
                .sheet(isPresented: $choosingPeriod) {
                    NavigationStack {
                        List {
                            Section {
                                Picker("Data", selection: $replay) { Text("My iPhone").tag(0); Text("Sample day").tag(1); Text("Travel replay").tag(2) }
                            }
                            if replay == 0 {
                                RecapPeriodPicker(grain: $grain, selectedDate: $selectedDate, now: context.date, window: window)
                            }
                        }
                        .navigationTitle("Map period").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { choosingPeriod = false } } }
                    }.tint(.teal)
                }
            }.navigationTitle("Map").navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct PlaceMapItem: Identifiable, Equatable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let seconds: Double
    let visitCount: Int
    let ongoing: Bool
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    static func items(places: [SavedPlace], totals: Totals) -> [Self] {
        places.compactMap { place in
            guard let seconds = totals.savedPlaceSeconds[place.id], seconds > 0,
                  CLLocationCoordinate2DIsValid(.init(latitude: place.latitude, longitude: place.longitude)) else { return nil }
            return Self(id: place.id, name: place.name, latitude: place.latitude, longitude: place.longitude,
                        seconds: seconds, visitCount: totals.savedPlaceVisitIDs[place.id]?.count ?? 0,
                        ongoing: totals.ongoingPlaces.contains(place.name))
        }.sorted { $0.seconds == $1.seconds ? $0.name < $1.name : $0.seconds > $1.seconds }
    }
}
private func mapPercent(_ seconds: Double, total: Double) -> String {
    "\(total > 0 ? Int((seconds / total * 100).rounded()) : 0)%"
}
#if DEBUG
// Isolated rendering fixture; never writes visits or saved places.
struct MapClusterPreview: View {
    private let items: [PlaceMapItem] = [
        ("Home", 43.47, -80.52), ("Cafe", 43.47, -80.52),
        ("Station", 43.46, -80.49), ("Shop", 43.645, -79.38), ("Office", 43.646, -79.383)
    ].map { PlaceMapItem(id: UUID(), name: $0.0, latitude: $0.1, longitude: $0.2, seconds: 3600, visitCount: 1, ongoing: false) }
    var body: some View {
        NavigationStack {
            PlacesMapInsight(items: items, total: 18000, travel: nil, unmapped: 0, framingKey: "cluster-preview")
            .navigationTitle("Map preview")
        }.tint(.teal)
    }
}
#endif
struct PlacesMapInsight: View {
    let items: [PlaceMapItem]
    let total: Double
    let travel: Double?
    let unmapped: Double
    let framingKey: String
    @State private var selectedID: UUID?
    @State private var focusIDs: [UUID] = []
    @State private var groupIDs: [UUID] = []
    @State private var fitRevision = 0
    private var selected: PlaceMapItem? { items.first { $0.id == selectedID } }
    private var group: [PlaceMapItem] { items.filter { groupIDs.contains($0.id) } }
    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                ContentUnavailableView("No saved-place time", systemImage: "map", description: Text("Choose another period or assign recorded visits to saved places."))
            } else {
            SavedPlacesMap(items: items, total: total, framingKey: "\(framingKey)-\(fitRevision)", interactive: true, selectedID: $selectedID, focusIDs: focusIDs, onCluster: openGroup)
                .overlay(alignment: .topTrailing) {
                    Button {
                        selectedID = nil; groupIDs = []; focusIDs = []; fitRevision += 1
                    } label: {
                        Image(systemName: "scope").frame(width: 44, height: 44)
                            .background(.background, in: Circle())
                    }.accessibilityLabel("Show all places").padding(12)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                if !group.isEmpty {
                    Text("\(group.count) places in this group").font(.headline)
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(group) { place in
                                Button { selectPlace(place.id) } label: {
                                    HStack {
                                        Text(place.name).multilineTextAlignment(.leading)
                                        Spacer()
                                        Text("\(duration(place.seconds)) · \(detailPercent(place.seconds, total: total))").monospacedDigit()
                                    }.font(.subheadline).frame(minHeight: 44)
                                }.buttonStyle(.plain).accessibilityHint("Selects and zooms to this place")
                                if place.id != group.last?.id { Divider() }
                            }
                        }
                    }.frame(maxHeight: 180)
                }
                if !items.isEmpty {
                selectionDetails
                Menu {
                    ForEach(items) { place in
                        Button("\(place.name) · \(detailPercent(place.seconds, total: total))") { selectPlace(place.id) }
                    }
                } label: { Label("Choose a place", systemImage: "list.bullet").frame(minHeight: 44) }
                }
                if let travel { legend("Travel", seconds: travel, icon: "tram.fill") }
                if unmapped > 0 { legend("Unassigned / ambiguous", seconds: unmapped, icon: "questionmark.circle") }
                Text(travel == nil ? "Percentages of visit time" : "Percentages of visits + travel")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .onChange(of: framingKey) { _, _ in focusIDs = []; groupIDs = []; selectedID = nil }
    }
    private func openGroup(_ ids: [UUID]) {
        selectedID = nil
        groupIDs = ids
        focusIDs = ids
    }
    private func selectPlace(_ id: UUID) {
        selectedID = id
        groupIDs = []
        focusIDs = [id]
    }
    @ViewBuilder private var selectionDetails: some View {
        if let place = selected {
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name).font(.headline)
                Text("\(duration(place.seconds)) · \(detailPercent(place.seconds, total: total)) · \(place.visitCount) \(place.visitCount == 1 ? "visit" : "visits")")
                    .font(.subheadline).foregroundStyle(.secondary)
                if place.ongoing { Text("Includes ongoing estimate").font(.caption).foregroundStyle(.teal) }
            }.accessibilityElement(children: .combine)
        } else {
            Text("Tap a place for time and visit details.").font(.subheadline).foregroundStyle(.secondary)
        }
    }
    private func legend(_ name: String, seconds: Double, icon: String) -> some View {
        HStack {
            Label(name, systemImage: icon).lineLimit(2)
            Spacer()
            Text("\(duration(seconds)) · \(detailPercent(seconds, total: total))").monospacedDigit()
        }.font(.subheadline).accessibilityElement(children: .combine)
    }
}

private final class PlaceMapAnnotation: NSObject, MKAnnotation {
    let item: PlaceMapItem
    let total: Double
    var coordinate: CLLocationCoordinate2D { item.coordinate }
    var title: String? { "\(item.name) · \(mapPercent(item.seconds, total: total))" }
    init(_ item: PlaceMapItem, total: Double) { self.item = item; self.total = total }
}
private final class PlacePercentageView: MKAnnotationView {
    private let label = UILabel()
    private let dot = UIView()
    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.backgroundColor = .secondarySystemGroupedBackground
        label.textAlignment = .center
        label.layer.cornerRadius = 12
        label.layer.borderWidth = 1.5
        label.layer.borderColor = UIColor.systemTeal.cgColor
        label.clipsToBounds = true
        dot.backgroundColor = .systemTeal
        dot.layer.cornerRadius = 4
        addSubview(label); addSubview(dot)
        collisionMode = .rectangle
        clusteringIdentifier = "savedPlaces"
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure() {
        let text: String
        if let place = annotation as? PlaceMapAnnotation {
            clusteringIdentifier = "savedPlaces"
            text = place.title ?? place.item.name
            accessibilityHint = "Shows time and visit details"
            displayPriority = .defaultHigh
        } else if let cluster = annotation as? MKClusterAnnotation {
            clusteringIdentifier = nil
            let members = cluster.memberAnnotations.compactMap { $0 as? PlaceMapAnnotation }
            text = "\(members.count) places · \(mapPercent(members.reduce(0) { $0 + $1.item.seconds }, total: members.first?.total ?? 0))"
            accessibilityHint = "Zooms to these places and shows a list with their times"
            displayPriority = .required
        } else { return }
        label.text = text
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        let width = min(220, max(80, label.intrinsicContentSize.width + 24))
        let height = max(36, label.intrinsicContentSize.height + 16)
        frame.size = CGSize(width: width, height: height + 10)
        label.frame = CGRect(x: 0, y: 0, width: width, height: height)
        dot.frame = CGRect(x: width / 2 - 4, y: height + 2, width: 8, height: 8)
        centerOffset = CGPoint(x: 0, y: -frame.height / 2)
        accessibilityLabel = text
        accessibilityTraits = .button
    }
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        label.layer.borderWidth = selected ? 3 : 1.5
    }
}
private final class SizedPlacesMapView: MKMapView {
    var onLayout: ((SizedPlacesMapView) -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}
private struct SavedPlacesMap: UIViewRepresentable {
    let items: [PlaceMapItem]
    let total: Double
    let framingKey: String
    let interactive: Bool
    @Binding var selectedID: UUID?
    var focusIDs: [UUID] = []
    var onCluster: ([UUID]) -> Void = { _ in }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> SizedPlacesMapView {
        let map = SizedPlacesMapView()
        map.delegate = context.coordinator
        map.onLayout = { [weak coordinator = context.coordinator] map in coordinator?.fitIfNeeded(map) }
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        map.pointOfInterestFilter = .excludingAll
        map.showsUserLocation = false
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.isScrollEnabled = interactive
        map.isZoomEnabled = interactive
        map.register(PlacePercentageView.self, forAnnotationViewWithReuseIdentifier: "percentage")
        return map
    }
    func updateUIView(_ map: SizedPlacesMapView, context: Context) {
        let c = context.coordinator
        c.parent = self
        let geometry = framingKey + items.map { "\($0.id):\($0.latitude):\($0.longitude)" }.sorted().joined() + focusIDs.map(\.uuidString).sorted().joined()
        if c.items != items || c.total != total {
            c.items = items; c.total = total
            map.removeAnnotations(map.annotations)
            map.addAnnotations(items.map { PlaceMapAnnotation($0, total: total) })
        }
        c.geometry = geometry
        c.fitIfNeeded(map)
        map.setNeedsLayout()
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: SavedPlacesMap
        var items: [PlaceMapItem] = []
        var total = -1.0
        var geometry = ""
        private var appliedGeometry = ""
        private var fittedSize = CGSize.zero
        init(_ parent: SavedPlacesMap) { self.parent = parent }
        func fitIfNeeded(_ map: MKMapView) {
            // SwiftUI may first update a map at zero or provisional size. Fit
            // again at its actual size, without resetting ordinary pan/zoom.
            guard map.bounds.width > 0, map.bounds.height > 0,
                  geometry != appliedGeometry || map.bounds.size != fittedSize else { return }
            // Use MapKit's native pan/zoom glide after the initial framing.
            // Keep subsequent layout corrections animated too, so a changing
            // details panel does not interrupt recentering with a jump.
            let animate = !appliedGeometry.isEmpty && !UIAccessibility.isReduceMotionEnabled
            appliedGeometry = geometry
            fittedSize = map.bounds.size
            let points = parent.items.filter { parent.focusIDs.isEmpty || parent.focusIDs.contains($0.id) }
            if points.count == 1, let first = points.first {
                let distance = parent.focusIDs.isEmpty ? 2000.0 : 400.0
                map.setRegion(MKCoordinateRegion(center: first.coordinate, latitudinalMeters: distance, longitudinalMeters: distance), animated: animate)
            } else if !points.isEmpty {
                var rect = MKMapRect.null
                for place in points {
                    let point = MKMapPoint(place.coordinate)
                    rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
                }
                let minimum = (parent.focusIDs.isEmpty ? 250.0 : 80.0) * MKMapPointsPerMeterAtLatitude(points[0].latitude)
                rect = rect.insetBy(dx: -max(0, minimum - rect.width) / 2, dy: -max(0, minimum - rect.height) / 2)
                let horizontal = min(115, map.bounds.width * 0.25)
                let vertical = min(65, map.bounds.height * 0.2)
                map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal), animated: animate)
            }
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard annotation is PlaceMapAnnotation || annotation is MKClusterAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "percentage", for: annotation) as! PlacePercentageView
            view.annotation = annotation
            view.configure()
            return view
        }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let place = view.annotation as? PlaceMapAnnotation {
                parent.selectedID = place.item.id
            } else if let cluster = view.annotation as? MKClusterAnnotation {
                let ids = cluster.memberAnnotations.compactMap { ($0 as? PlaceMapAnnotation)?.item.id }
                mapView.deselectAnnotation(cluster, animated: false)
                parent.onCluster(ids)
            }
        }
    }
}
