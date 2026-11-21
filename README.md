# Location Recap · iPhone proof of concept

A native SwiftUI app using Core Location visits, Apple maps, and a local JSON archive. No account or backend. Open **LocationRecap.xcodeproj** in Xcode and run the **LocationRecap** scheme.

## Install on your iPhone

1. Use Xcode 26 or later. This build was compiled with Xcode 26.6 and the iOS 26.5 SDK. Deployment target is **iOS 17.0**, supporting SwiftUI Map and a broad set of personal iPhones. The actual phone OS was not supplied; verify it is 17 or newer.
2. Connect and unlock the iPhone, trust the Mac, and enable Developer Mode under Settings → Privacy & Security if requested.
3. Select the project → LocationRecap target → Signing & Capabilities. Choose your personal development team and change `com.example.LocationRecap` to a unique bundle identifier. Automatic signing is configured; no team credentials are stored in this project.
4. Select your iPhone as the run destination and Run. If required, trust the developer profile in Settings → General → VPN & Device Management.
5. Open Capture, tap Enable capture, and grant While Using. Tap Enable capture / request Always again to request the upgrade. If iOS defers that prompt, use Open app Settings → Location → Always. Enable Precise Location for useful place matching. Confirm permission shows Always and background readiness says Ready.
6. Stop the Xcode run, then launch from the phone's home screen. Disconnect the cable/debugger and lock the screen for the physical trial.

Visit monitoring uses `startMonitoringVisits`, not continuous GPS. Visit monitoring alone does not require `UIBackgroundModes=location`. The independent geography sampler added below does require background-location mode and enables `allowsBackgroundLocationUpdates`. Always permission supports background delivery. The location manager is recreated and assigned a delegate on app startup, including a system background relaunch. Enable state survives launch. The app re-registers on foreground entry. There is no promise of uninterrupted capture after force-quit, shutdown, or denied permission.

## Explore without traveling

Recap → Data → **Sample day** shows a completed synthetic 24-hour window: 8 hours in Toronto, 2 at Gym, 16 unaccounted. Toronto is 100% and Gym 25% of tracked time. **Travel replay** shows 2 hours Toronto, an 8-hour flight gap, and 4 hours London: 6 visit hours, 8 estimated travel hours and 10 unaccounted hours in the 24-hour window. Stops use absolute timestamps; Toronto and London have different local time zones. Replays run instantly and never write to real history. The Day / Week / Month / Year selector applies to My iPhone; replay windows are fixed at 24 hours. Choose a date within the desired period or use the previous/next arrows. Weeks start Monday. The current period ends at now; previous periods include their full calendar duration. The displayed range and device time zone make the active filter explicit.

Xcode Debug → Simulate Location can exercise map positioning, but changing simulated coordinates does not guarantee a CLVisit. These fixtures validate aggregation, not locked-device event delivery.

## Data and calculation rules

- `Core/Models.swift` holds reconciliation, circle matching, time aggregation, fixtures and injectable geocoder contracts. `App/Store.swift` handles capture, atomic persistence and Apple geocoding. `App/LocationRecapApp.swift` contains the UI.
- Archive: Application Support/LocationRecap/history.json, protected until first device unlock after reboot. Raw callbacks are appended and saved before geocoding; receipt time, source, accuracy and optional arrival/departure are retained. A storage failure is visible in Capture. No raw events are deleted or exported by this POC.
- Reconcile matching absolute arrival timestamps within 200 m; a later departure updates the original visit. Original callback observations remain inspectable. Events with unknown arrival stay unusable for duration; no guessed start time. Large coordinate corrections outside the reconciliation tolerance remain separate; the interval union still avoids duplicate time.
- Only valid completed intervals contribute. Open visits are provisional. Clip each interval to the window, split at every endpoint, and count each occupied segment once. Conflicting labels become unknown within the affected independent view. Missing time is elapsed minus that interval union, distinct from unknown geography and no saved place.
- Boundaries use an ISO 8601 calendar, Monday week start and the device's current time zone, shown in Recap. Changing time zones changes the display window, never stored timestamps. DST days use their actual elapsed duration. Percentages always divide by accounted-for time; views must not be added together.
- Circle matching uses spherical distance in meters. An accuracy disk must be fully inside exactly one circle with no other possible circle. Boundary uncertainty and overlaps are ambiguous. Visits → a visit lets you confirm a place or explicitly choose no place; manual overrides survive rematching. Saved-place radius sliders remain editable in Capture. Only visits represent stops; there is no pass-by location feed.
- iOS 26 uses MKReverseGeocodingRequest; older systems use CLGeocoder. The installed SDK exposes cityName and regionName on addressRepresentations; **regionName is country**, not province/state. Administrative region uses the returned map item's structured placemark.administrativeArea (a compatibility API), with placemark fallbacks for missing city/country. No address string parsing or polygon claims.
- Successful geographies are persisted and reused within 10 m. Unresolved visits remain unknown offline. Requests run sequentially with a 2-second spacing; the batch stops on the first error to avoid hammering a rate limit. Retry unknown geography manually or reopen the app. Background geocoding is best effort; foreground retry handles interrupted requests. Capture does not depend on network availability.

## Verification

Run deterministic checks from this folder:

```sh
swift test
```

For a restricted workspace with unwritable global compiler caches:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/recap-modules SWIFTPM_MODULECACHE_OVERRIDE=/tmp/recap-modules swift test --disable-sandbox --cache-path /tmp/recap-cache --scratch-path /tmp/recap-tests
```

Unsigned device compilation:

```sh
xcodebuild -project LocationRecap.xcodeproj -scheme LocationRecap -sdk iphoneos -derivedDataPath /tmp/recap-build CODE_SIGNING_ALLOWED=NO build
```

Tests cover the example day, duplicate union and event reconciliation, open/unknown arrivals, midnight clipping, unknown geography after stub failure, overlapping circles, manual corrections, conflicting attribution, border travel/flight gaps and a DST time-zone boundary.

## Physical-device trial checklist · still required

- [ ] Confirm Always, Precise, capture enabled; launch without debugger and lock the phone.
- [ ] Note independent arrival/departure times for a long indoor stop, normal stops and a short errand. Record expected place and approximate battery level at start/end.
- [ ] After a day, compare delivered visits and receipt delays, timing error, false/missed stops, ambiguous/wrong place matches, tracked hours, and battery change. Save notes alongside raw diagnostics; a short errand may never become a visit.
- [ ] Create a place from a real visit, adjust the radius and verify a later stop; resolve an ambiguous visit manually.
- [ ] Go offline for a stop; verify raw observations survive. Reconnect and Retry unknown geography.
- [ ] Force-quit, spend time at a stop, reopen and confirm monitoring resumes and stored history survives. Do not assume the gap is recoverable. Also test permission revocation and restoration.
- [ ] Repeat for a normal week if promising. Document sparse visits and timing errors before introducing a higher-frequency API.

A successful replay is not proof of background capture. Locked-phone delivery, authorization prompts, network recovery on device, visual behavior, battery use and signing require the actual iPhone. No physical-device trial or simulator UI trial has been performed here.

## Apple references

- [Visit monitoring and relaunch behavior](https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoringvisits())
- [MapKit reverse geocoding](https://developer.apple.com/documentation/mapkit/mkreversegeocodingrequest)
- [Running on a device](https://developer.apple.com/documentation/xcode/building-and-running-an-app)

## Nearby place suggestions

Opening an unassigned or ambiguous visit searches Apple Maps for up to ten nearby named places. Orange map pins correspond to the candidates, sorted by distance. Suggestions are possibilities, not proof of a visit. Search uses a radius based on location accuracy (200–1500 meters), requires connectivity, and offers retry or a custom name when unavailable. Selecting a candidate opens a confirmation that saves a circle centered on that candidate and assigns the visit in one action. The radius slider controls a new circle. An existing same-name place within 50 meters is reused without changing its circle. Existing manual assignments, explicit no-place decisions, and confident automatic matches suppress suggestions. No candidate is applied automatically. Candidate results remain in memory; the archive format is unchanged.

## Include travel time

Recap has an Include travel time toggle immediately below the main card, off on app launch. Off preserves visit-only totals and percentages. On adds inferred travel to the saved-place coverage and denominator only. City/region percentages now use the independent geography timeline below. Travel is shown separately with inspectable intervals. Gaps run from a recorded departure to the next recorded arrival, clipped to the selected window and unioned to avoid duplicates. All observed stays, including open ones, are subtracted. No time before the first departure or after the last arrival is inferred as travel. A departure without a known arrival can still start a trip. There is no inferred travel mode and gaps may contain missed stops; this is a testing estimate, not motion detection. Toggling recalculates in memory and never edits history.

## Independent geography timeline · 2026-11-16

City/region totals use timestamped GeographySample observations from the persisted geographyStartedAt cutoff onward. Before that cutoff, completed visits supply the original city/region totals. The two sources are clipped at that exact boundary so they never double count. Past travel gaps are not reconstructed. The main card remains the visit/saved-place coverage; geography has its own coverage, unknown duration and percentage denominator. Unknown reverse geocodes count as location-covered time with unknown labels; missing/poor/sparse readings do not. Replay geography is explicitly synthetic (a one-hour sequence crossing Waterloo/Kitchener), independent of replay visits.

A separate CLLocationManager requests 100 m accuracy, a 250 m distance filter, automatic stationary pauses, and significant-change resumption. Low Power Mode requests 1 km accuracy / 1 km movement. Actual precision and timing are OS-controlled. At most one received reading per minute is retained, promptly saved; this reduces processing and lookup traffic, not necessarily sensor energy. Significant-change monitoring can resume standard updates after a pause; reopening also restarts them. Existing visit monitoring remains separately registered. A visible background location indicator is enabled. Always authorization and location background mode are required. No polling timer or navigation-grade accuracy request.

Pairs of usable readings (accuracy at most 1 km, same capture session, no more than 15 minutes apart) establish covered time. A label change is estimated at the timestamp midpoint; this is sampling-based attribution, not polygon boundary detection. Equal city names on distant trip endpoints are never used to bridge a long gap. No extrapolation after the latest reading, no bridging process restarts/disable periods. All durations clip to the selected calendar window. This conservative version may show missing stationary time when iOS pauses; do not interpret its coverage as a complete 24-hour presence record. Tuning this against stationary and commute trials remains necessary.

Raw samples persist offline. The shared serial geocoder resolves sample points at most once per minute, caching successes only within 10 meters. Unresolved backlog can be retried from Capture or on foreground entry; network failure stops the batch. Coordinates are sent to Apple for these lookups. Samples include fix timestamp, receipt time, accuracy and session identity. Capture shows sample count, sampler state, last reading and last resolved geography. Disable capture stops both visit and geography services.

Device checks still needed: after enabling Always/Precise, watch sample count grow while walking, confirm geographic totals remain fixed when toggling travel, test locked-phone commute and stationary pause/resumption, switch Low Power Mode, go offline and retry, disable/re-enable and reopen after force-quit, compare battery usage against the visit-only build. Geography needs at least two usable readings before showing covered duration. Full foreground launch and a live reading do not prove locked-phone delivery or battery behavior.

## Recap layout editor

Use the layout icon at the top right of Recap to open Edit layout. Drag the handles to reorder visible insight cards, tap a minus to hide one, or use a plus under Available insights to add it. Done returns to Recap. Reset restores the original overview, Visits Breakdown and Geography Breakdown order. The data/period controls always remain above the configurable cards. Layout is stored separately in UserDefaults (`recap.layout.v1`) and never changes captured data.

Country Breakdown and Continent Breakdown are available but hidden initially. Both use the same geography timeline/denominator and historical cutoff as Cities and Regions. New lookups retain ISO country codes; legacy country names are matched against Foundation English/current-locale names where possible, otherwise continent stays unknown. Continent uses Foundation's country-region hierarchy, splitting the Americas into North and South America. It is a country-level classification, so transcontinental countries are not subdivided by coordinates.

## Ongoing visit estimates

Recap now includes the latest open visit with a known arrival, estimated through the current time and clipped to the selected period. It refreshes every minute and is labeled ongoing/estimated in the overview, place breakdown and Visits row. Older open visits superseded by a newer arrival are not extrapolated. At midnight, each calendar day receives only its portion of the ongoing interval. No fake departure is persisted: when Core Location supplies a departure, its timestamps replace the temporary calculation and final totals equal completed-only aggregation. Delayed departures can temporarily overcount a place; this version labels the uncertainty rather than cutting visits based on noisy geography readings. It adds no location requests. Travel remains only bounded gaps, never the current stay. The independent geography timeline and historical geography cutoff retain their original rules; they do not use these ongoing estimates.

## Missing time versus excluded travel

Unaccounted time is elapsed minus visit time (including ongoing estimates) minus inferred travel, regardless of the Include travel time toggle. Turning the toggle off excludes travel from the main total and Visits Breakdown denominator; it does not turn travel into missing data. The main card shows Travel excluded to explain the difference. A visit with known timestamps but unknown city/place still has counted duration. Independent geography coverage follows its own rules.

## Commute repair and stationary continuity · 2026-11-19

Arrival timestamp is now the identity for a CLVisit update, even when Apple refines its coordinate by more than 200 meters. Departure updates refresh coordinate/accuracy, invalidate stale geocoding when necessary and preserve the retained record's manual assignment. Arrival-only callbacks never reopen a completed visit. Visits display by arrival time, with departure-only events using departure as their sorting timestamp. Only the dedicated visit manager handles visit callbacks, avoiding duplicate raw callback storage from the geography manager.

The one-time repair saves the full original JSON on-device as history-before-repair-v1.json, canonicalizes same-arrival duplicate records, and replays completed raw observations. A completed record is preferred over an open duplicate; its identity and assignment survive. Superseded originals, including their assignments, are retained in supersededVisits; saved circles and raw observations are retained. Repair is versioned/idempotent. The external pre-repair container snapshot is at /private/tmp/LocationRecap-before-commute-repair.xcappdata on the development Mac.

Travel inference independently canonicalizes duplicates, and stale open intervals end at the next observed arrival rather than masking every later trip. These are inferred intervals based on reported timestamps, not proof of transport mode or exact walking times. The missing morning Union-to-office split is not invented.

When Core Location explicitly pauses geography updates, the app records a stationary-state interval linked to its latest usable fix (no older than 30 minutes), registers a 150–500 m exit-monitoring circle and keeps significant-change monitoring. Region exit or a fresh movement fix ends the interval and resumes standard sampling. These intervals are labeled stationary estimates. They can extend to now only while the same in-process monitoring session remains active. On disable or restart, they stop; an abandoned session is capped at its last confirmation, never silently bridged across a restart. Detection latency can still temporarily overestimate stationary presence. No polling timer is used.

Historical geography backfill is limited to a persisted repair-time cutoff. It uses recorded completed visits and the latest open stay estimate before that cutoff, filling only intervals without higher-priority geography evidence. It is explicitly labeled as visit-estimated time, not recovered raw location. Future geography continues independently using samples and explicit stationary state. Priority is resolved sample evidence, resolved stationary evidence, original pre-geography visit history, then cutoff-limited visit backfill; unresolved samples remain unknown if nothing more informative exists. Segment splitting prevents double counting. Countries/continents use the same resulting timeline.

A physical locked-phone trial is still needed for stationary resumption, geofence exit delay, restart handling and battery use.

## Saved-place identity and duplicate names · 2026-11-19

Suggestions reuse an existing saved place when the Apple Maps place identifier matches or its normalized name matches. The old 50 m name-match restriction is removed. Names are compared without case, accents, width or repeated/outer whitespace differences. A custom save with an existing name is rejected with Location already exists; Use existing location explicitly assigns that record instead. Use distinct labels for different branches if you want separate saved places. Reusing a suggestion keeps the saved circle and label intact; a missing Apple identity can be attached for future matching.

Repair version 2 consolidates pre-existing same-name saved records. It prefers the circle with the most active manual confirmations, retaining the first record on ties. Active visit assignments are redirected to that record. Other original circles are archived in supersededPlaces, and the complete input archive is saved on-device as history-before-place-dedupe-v2.json before migration. Visit timestamps, raw observations and geography samples are unaffected. Choosing a name has never represented a timestamp edit; the earlier save flow created additional records rather than renaming an existing one.

## Places Map insight · 2026-11-19

Recap includes a Places Map after Visits Breakdown, with the same section heading style. Each saved-place annotation shows its name and rounded percentage of accounted-for time for the selected period. With travel off this is visit time; with travel on it includes inferred travel. Travel is shown separately under the map, and unassigned/ambiguous visit time is a separate remainder rather than attributed to a pin. Tapping a pin shows duration, distinct visit count intersecting that period, and an ongoing-estimate label when applicable. Nearby annotations cluster with a combined percentage; tapping a compact-map cluster opens the expanded map. Expand map supports pan/zoom and a Choose a place menu for coincident or crowded pins. The compact map stays fixed for smooth page scrolling. The map fits the period's visited saved locations, and never draws an inferred route or requests current-location access.

The insight can be hidden/reordered using Edit layout. A one-time UserDefaults flag adds the map after Visits Breakdown in existing nonempty layouts, without resetting their order or other hidden cards; an explicitly empty layout is preserved. No capture, persisted history or saved-place changes are required. Map tiles use Apple Maps; saved-place annotation labels and statistics are calculated locally.

Cluster selection fits the tapped members' coordinate bounds instead of applying a fixed zoom step. The expanded map also lists the members with duration and percentage; choosing one focuses that place and shows its visit details. This handles coincident pins without requiring repeated zoom taps. A DEBUG-only --map-cluster-preview launch argument renders a five-place fixture (including two coincident pins) without writing history; it is disabled in the shared scheme by default.

## Map tab · 2026-11-19

The map now lives in its own bottom tab: Recap, Visits, Map, Capture. This replaces the Recap map card; legacy `placesMap` entries in saved layouts are ignored while other visible/hidden cards retain their order. The map is no longer an addable layout insight. Its full-screen interactive view preserves percentage labels, cluster drill-down/member lists, place details and the travel/unassigned legends. Tap the calendar/date at the top to choose day/week/month/year and a specific period. The selected period, data source and Include travel time setting are shared with Recap. Existing history and capture are unchanged.

Map fitting is deferred/repeated when the native map receives its actual layout size, avoiding an initial continent-scale camera caused by zero/provisional bounds. Ordinary panning does not reset the camera. Saved-place and cluster annotation views explicitly refresh their annotation identity; only individual pins join clusters. Show all places (scope icon) resets the view to the period's locations. The DEBUG fixture now spans Waterloo/Toronto and retains a coincident pair.

After initial framing, camera changes use MapKit's native animated pan/zoom (including Show all places, cluster drill-down and place selection). Layout changes preserve animated movement rather than interrupting it with an immediate camera reset. Reduce Motion disables the animation.

Text percentages outside the map use two decimal places with locale-aware formatting (including trailing zeros). This applies to Recap breakdowns, map details, group member lists, the place chooser and travel/unassigned legends. Map pin and cluster labels keep whole-number percentages for readability; underlying calculations are unchanged.

## Stationary geography via monitored areas · 2026-11-20

This supersedes the pause-only stationary capture behavior. A fresh geography fix (at most two minutes old, accuracy within 250 m, current process session) can register one 200–500 m location-area circle. The app requests its state after Core Location confirms registration. An inside-state callback starts an estimated geography interval at the confirmation time, independently of visits, saved places and pause callbacks. Quiet distance-filter periods therefore continue to count. Fixes inside the circle update the last confirmation; a new outside fix, region exit, unknown region state, monitoring failure or capture disable ends it. Resolved sample-pair evidence still takes priority, and a fresh reading resolved in a different city replaces an old anchor even inside the coarse circle. An area can straddle a city boundary, so this is bounded location estimation, not exact administrative-boundary detection.

Only one app geography area is monitored at a time. Known speeds of 2 m/s or more avoid repeatedly registering areas along a moving route; normal moderate-accuracy sampling and significant-change monitoring remain in use. No timer polls for movement. A pause without an area/fresh anchor requests one fresh fix instead of claiming monitoring started. A restart closes abandoned intervals at their last actual confirmation and removes obsolete app regions; it does not assume the phone remained in the same city across an unknown restart gap. An unresolved anchor's city can fill in after geocoding succeeds.

A separate one-time geographyAreaVersion migration backs up the input to history-before-geography-area-v1.json and advances the historical visit-backfill cutoff to installation time. Known completed/current visits repair earlier gaps as explicitly labeled visit-based estimates, without rewriting raw observations or visit/place records. The cutoff then stays fixed. Future ongoing city attribution uses independent location-area evidence, not saved-place visits. Existing stationaryStays is retained as the backward-compatible storage field for monitored-area intervals, with optional radius metadata. Physical locked-phone departure, overnight continuity and battery use still need a sustained field trial.
