# Verification · 2026-11-14

- PASS: Xcode 26.6 / iOS 26.5 SDK unsigned arm64 iPhone build, deployment target iOS 17.0 (`BUILD SUCCEEDED`).
- PASS: 8 XCTest cases in the shared RecapCore Swift package, zero failures. Uses the same source files compiled into the app.
- PASS: sample day arithmetic: 8 tracked hours, 16 missing, Gym 25%, city 100%.
- PASS: duplicate interval union, open-visit exclusion, later departure reconciliation, midnight clipping, conflicting overlap attribution, overlapping circles and manual overrides, offline stub failure, border itinerary and Toronto DST boundary.
- NOT RUN: simulator UI launch. CoreSimulator's runtime service was unavailable in this environment.
- NOT RUN: signed installation, actual permission prompt flow, locked-device visit delivery, relaunch recovery on hardware, live Apple geocoder behavior, and battery impact. Follow README's physical trial checklist.

Build output had an informational App Intents metadata warning because this app has no App Intents dependency. Initial SwiftPM invocation encountered restricted global cache directories; tests passed using temporary local caches. No signing team was selected.

## Period navigation update · 2026-11-16

- PASS: unsigned iPhone build with Day / Week / Month / Year selection, date selection, previous/next navigation, current-period shortcut and explicit date bounds.
- PASS: 11 shared-core tests, zero failures, including historical Sunday vs new Monday week, month/year and leap-year durations, month/year navigation and a 25-hour DST day.
- Existing archive schema, storage path and bundle identifier retained.
- Before installation, downloaded and parsed the phone history: 4 visits, 3 saved places, 6 raw observations. Xcode reported a container-transfer warning; history.json was successfully copied and validated. Backup: /private/tmp/LocationRecap-before-period-picker.xcappdata.
- PASS: Xcode installed and launched the update on the connected iPhone. Post-install history snapshot confirms every original visit, saved place and observation is preserved; capture enabled state is unchanged.

## Nearby place suggestions · 2026-11-16

- PASS: iPhone build and launch through Xcode. 12 shared-core tests passed, including confirmation, duplicate-place reuse, and preservation of saved circles and manual decisions.
- PASS: before/after device history snapshots preserve all 4 visits, 3 places, 6 observations and enabled state. Xcode container export reports a transfer warning but history.json copies successfully and parses.
- New candidates are fetched on opening unconfirmed visits, displayed with map pins and require confirmation. Custom naming remains available. No archive schema changes.
- Still requires exercising the actual suggestions list and confirmation on an unconfirmed visit on the phone; existing confirmed visits intentionally do not show it. Apple network search failure, no results and retries have UI handling but were not exercised end to end here.

## Travel toggle · 2026-11-16

- PASS: unsigned iPhone build; 14 core tests, zero failures. New checks cover default/off and enabled denominators, coverage, travel ending at open arrival, open stays excluded, duplicate gap union, overlapping stop subtraction, historical-window clipping and initial setup exclusion.
- No archive or capture changes; travel is derived at display time.

## Independent geography capture · 2026-11-16

- PASS: 17 shared-core tests, including migration from legacy archives, round-trip sample storage, city transitions/midpoint attribution, midnight clipping, duplicate samples, unknown geography, rejected poor fixes, 15-minute gap cutoff and session discontinuities. Existing visit/travel tests still pass.
- PASS: unsigned device build and Xcode signed installation/launch. Built Info.plist includes location background mode.
- PASS: before/after phone snapshot confirms existing 6 visits, 4 saved places and 11 raw visit observations preserved. Xcode container transfer reports an error but the history file successfully copies and parses.
- Device sampler receipt/resolution counts are recorded in the handoff. Full locked-device movement/stationary/resumption, offline lookup retry and battery effects still require a new physical trial. No claim of uninterrupted capture or complete stationary coverage.

## Historical geography cutover · 2026-11-16

- PASS: 18 tests, zero failures; unsigned iPhone build passes. New test covers historical-only periods, new-only periods, straddling visits/readings and an exact cutoff without double counting.
- Legacy geography is derived from preserved completed visits strictly before geographyStartedAt. New independent observations apply at/after that timestamp. No archive mutation or inferred historical travel.

## Layout editor and country/continent cards · 2026-11-16

- PASS: 20 core tests, zero failures. Covers default layout, custom order persistence, all-hidden state, duplicate/unknown layout identifiers, country/continent mapping and legacy/new timeline aggregation.
- PASS: unsigned iPhone build. Optional countryCode decodes from existing archives without requiring a migration rewrite. Capture and saved-place matching are unchanged.
- Layout interactions (drag, hide/add, reset and relaunch persistence) still require manual UI exercise on the physical phone; only compilation/core preference serialization is verified here.

## Pending visit naming · 2026-11-16

- PASS: iPhone build and 21 core tests. Pending naming counts distinct visit IDs, includes open and ambiguous visits, ignores confident/confirmed named matches and explicit No saved place decisions, and becomes zero after assignment.
- Visits tab uses the native numeric badge (zero is hidden). Pending rows show an orange Name this visit alert and warm tint; latest-stop gray remains intact.
- Custom Save and assign now confirms the current visit in the same action so naming clears its pending state even when the accuracy radius is ambiguous. No automatic edits to existing records.

## Ongoing visit estimates · 2026-11-16

- PASS: 23 tests, zero failures; unsigned iPhone build passes. New checks cover clock growth, duplicate/overlap-safe coverage, travel separation, midnight clipping, superseded open events, unchanged raw visits and final reconciliation to completed totals.
- Estimates are computed in memory only. No history schema or capture changes.

## Unaccounted time independent of travel toggle

- PASS: 23 tests with revised gap expectations and assertions that missing time stays fixed across toggle states, including a current ongoing visit. Visit time + inferred travel + missing time equals elapsed time in the tested bounded-trip case.

## Commute repair · 2026-11-19

- PASS: 28 tests; unsigned iPhone build. Regressions cover a 274 m arrival/departure coordinate correction, delayed arrival callbacks, assignment preservation, repair idempotence and archived originals, stale-open travel suppression, stationary intervals and session restarts, and cutoff-limited gap backfill without double counting.
- PASS: replay of the actual Nov 19 snapshot in memory: 13 active visits become 12 active plus one archived duplicate; saved-place IDs and raw event count remain intact. Restored travel is approximately 240.35 minutes and visit-model missing time becomes zero for the inspected day/window. This does not establish accuracy of all Apple timestamps.
- Fresh external backup verified before installation: 13 visits, 35 raw observations, 10 saved places. An additional full original backup is created on-device by the migration before any repair writes.
- Geography stationary state and labeled backfill are estimates; they do not invent the missing morning station/office boundary. Locked-phone/battery validation remains required.

- PASS after signed installation: actual phone archive has 12 active visits and 1 archived duplicate. All 10 saved places, 35 raw observations and surviving manual place assignments preserved. On-device history-before-repair-v1.json matches the fresh external original exactly. Repair version is 1; all active visit geographies resolved. Stationary-state lifecycle remains to be exercised by the next physical trial.

## Duplicate saved places · 2026-11-19

- PASS: 32 tests and unsigned iPhone build. New regressions verify suggestion reuse beyond 50 m, normalized-name uniqueness and nonmutation on rejected custom saves, stable circle/label preservation, Apple identity reuse, idempotent consolidation and visit-time preservation.
- Fresh backup before installation: 12 active visits, 35 raw observations and 11 saved circles, including pairs of Kitchener Station, Union Station and Work. External snapshot: /private/tmp/LocationRecap-before-place-dedupe.xcappdata.
- PASS after signed installation on the connected iPhone: 8 unique saved places and 3 archived original circles; one Kitchener Station, Union Station and Work each. All 12 visit IDs/timestamps and 35 raw observations unchanged, assignment names preserved, and geography backfill cutoff unchanged. The on-device history-before-place-dedupe-v2.json matches the external pre-install archive exactly. All original place IDs remain active or archived. Duplicate-alert UI is compiled; interaction behavior is covered by core tests rather than a live duplicate save on personal data.

## Places Map insight · 2026-11-19

- PASS: 34 core tests, including saved-place ID totals/counts, period clipping, ongoing stays, identical percentage denominators with the travel toggle, duplicate observation IDs and exclusion of ambiguous/conflicting time from pins. Unsigned iPhone build succeeds.
- The implementation adds no archive fields or capture changes. Layout addition uses UserDefaults and preserves existing nonempty layout ordering; an explicitly empty layout stays empty.
- PASS in iPhone 17 Pro iOS 26.5 simulator: sample-day map shows Gym · 25%, agreeing with Visits Breakdown; selecting the annotation shows 2 h, 25%, 1 visit. Unassigned remainder is 75%. Expanded map opens with the same details and a Choose a place control. Visually checked compact/expanded layout and compact dark appearance. Map tiles load, labels remain legible, and the page scrolls past the fixed compact map. Crowded clustering, large accessibility type and long labels have implementation handling but were not exhaustively exercised on-device.
- PASS: final signed build installed and launched on Senthil’s connected iPhone through Xcode after the touch-target refinement. Same bundle/container; no history migration or capture changes in this feature.

## Map cluster drill-down · 2026-11-19

- PASS: unsigned iPhone build; signed simulator build. No changes to aggregation, capture, or persisted history.
- PASS: interactive five-place DEBUG fixture in iPhone 17 Pro simulator (dark appearance). Tapping a three-place cluster fits that group's bounds and separates Office from a two-place cluster; member list shows Home, Cafe and Office with 1 h / 20% each. Tapping the coincident Home/Cafe pair fits to street/building scale and lists both. Selecting Cafe shows 1 h / 20% / 1 visit, dismisses the member list and focuses its location. Group lists remain available when geometry prevents separate labels. Shared scheme preview argument disabled after verification.
- PASS: final signed update launched on Senthil’s connected iPhone with the fixture argument disabled. Same bundle and history container retained.
- PASS: Release iPhone build, excluding DEBUG fixture code. Confirmed preview launch checkbox off in Xcode Scheme editor and on disk (`isEnabled = "NO"`), then relaunched the normal app on the connected iPhone.

## Dedicated Map tab · 2026-11-19

- PASS: 34 core tests and unsigned iPhone build. Legacy placesMap layout tokens are ignored, remaining cards keep their order, default Recap layout returns to summary/visits/geography. No persistence/capture changes.
- PASS in iPhone 17 Pro simulator: visible tab order Recap, Visits, Map, Capture. Map has its own interactive viewport and date/travel controls. Choosing Nov 18 in Map's calendar sheet changes Recap's date to Nov 18; selecting Sample day in Recap shows Gym · 25% in Map; enabling travel in Map shows the toggle enabled in Recap. Empty-period state and full-map dark layout inspected. Edit layout contains no map option. Existing cluster/member-list implementation is retained.
- PASS: final signed build launched on Senthil’s connected iPhone with preview argument disabled. Bundle/container retained; existing visits and saved locations require no migration.

## Map initial framing / missing labels · 2026-11-19

- Diagnosis: the Nov 19 post-dedupe phone snapshot yields saved-place map totals for Home, Kitchener Station, Union Station, Work and Georgetown Station; Kitchener's 2% is not the sole saved-place time. Xcode's phone console reports a zero-width/height map drawable during initialization. Camera fitting previously ran once in updateUIView, before final map layout.
- Fix: native layout callback fits again when bounds settle/change; explicit annotation identity refresh and nonclustered cluster views; Show all places control. Pan/zoom remains untouched when bounds and framing identity are unchanged. No history/aggregation/capture changes.
- PASS: unsigned iPhone build and signed simulator build. Cold launch of five-place Waterloo/Toronto fixture shows both 60% and 40% groups at Southern Ontario scale, rather than one pin at continental scale. Group tap lists all three Waterloo members; Show all places returns to both groups. Coincident pair retained in fixture.
- PASS: signed final update launched on Senthil’s connected iPhone. Fixture argument disabled in Xcode and confirmed on disk. Same history container and totals retained.

## Smooth map recentering · 2026-11-20

- Native MapKit animated region/visible-rect transitions replace immediate camera movement after initial fitting; subsequent layout corrections also animate. Reduce Motion retains immediate transitions. Capture, saved history and time calculations unchanged.
- PASS: unsigned iPhone build and final signed update launched on Senthil’s connected iPhone. Native animation is enabled in both single-place and multi-place fitting paths; animation timing has not been measured on the physical device.

## Percentage precision · 2026-11-20

- Text details now use a shared locale-aware percent formatter with exactly two fractional digits. Map annotations retain their existing whole-number formatter. Applies to Recap visits/geography, member lists, selected-place details, place chooser, legends and progress accessibility value. Calculations and persisted data unchanged.
- PASS: unsigned iPhone build and signed update launched on the connected iPhone. Source audit confirms only annotation/cluster labels use whole-number mapPercent; all explicit detail percentages use detailPercent. No new tests for this formatting-only change.
