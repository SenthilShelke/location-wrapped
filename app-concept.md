# App Concept: "Location Wrapped"

## One-line pitch
A personal app that quietly tracks the places you go, then generates Spotify-Wrapped-style recaps of your location habits — daily, weekly, monthly, and yearly — showing top places, time distribution, streaks, and fun stats, entirely on your own device.

## Goals
- Give users a fun, shareable recap of where they spent their time, at multiple time scales: end of day, end of week, end of month, and end of year
- Make every recap feel like Spotify Wrapped: a sequence of visually engaging stat cards/slides, not a boring dashboard — with the yearly one being the biggest, most celebratory version, and daily/weekly/monthly being smaller, quicker versions of the same idea
- Keep the MVP at zero ongoing cost — no cloud backend, no paid APIs, no server bills

## Non-goals (for MVP)
- No social features (friends, leaderboards, sharing to a feed) — just personal stats
- No cloud sync / multi-device support
- No real-time "live" tracking dashboard — this is a retrospective, not a tracker app
- No monetization/ads in the MVP

## Core constraint driving every decision
Everything must run **on-device**. No data leaves the phone, no backend server, no paid third-party services. This isn't just a cost-saving measure — it also makes the app trustworthy for something as sensitive as location history, and it's the same approach existing "wrapped for travel" apps use successfully.

## Core user flow

1. **Onboarding**
   - Explain what the app does and why it needs location permission
   - Be upfront that all data stays on the device
   - Request "always allow" location access (with a clear explanation of why)

2. **Background collection (ongoing, invisible to the user)**
   - Periodically record the user's location in the background
   - Group nearby/repeated points into "visits" to a place (e.g., recognizing "you were near this spot for 2 hours" rather than storing raw noisy pings)
   - Attach a human-readable place name to each visit where possible
   - Store all of this locally on the device

3. **Everyday use (optional, secondary)**
   - A simple screen where a user can browse recent visits/places if curious
   - Not the main focus — this app is primarily about the eventual reveal, not daily engagement

4. **The "Wrapped" reveals (the core feature) — four cadences**
   - The same underlying idea repeats at four time scales, each sized to fit the occasion:
     - **Daily recap**: a quick, lightweight summary delivered at end of day (e.g., top place today, number of places visited, time distribution across the day)
     - **Weekly recap**: a slightly bigger version at end of week (top places this week, busiest day, any new places explored)
     - **Monthly recap**: a bigger version still, at end of month (top 5–10 places, time distribution, comparison to previous month if easy)
     - **Yearly recap**: the biggest, most celebratory version at year-end — this is the "main event" and should get the most visual polish, e.g.:
       - Top 10 most-visited places
       - % of time spent at each top location
       - Total number of distinct places visited
       - Longest streak at one place / most "new places explored"
       - A fun superlative or two ("night owl," "homebody," "explorer," etc. based on patterns)
   - All four should share a consistent visual template (same card style, just scaled in length/depth) so it feels like one coherent feature, not four separate ones
   - Each card should feel designed, not like a spreadsheet — playful colors, big numbers, simple animations
   - Should be easy to screenshot/export as an image to share
   - Users should also be able to manually pull up "today so far" / "this week so far" / "this month so far" recaps anytime, not just wait for a notification

5. **Data control**
   - Clear way to view what's being tracked
   - Clear way to delete all data
   - Since this is sensitive personal data, trust and transparency matter as much as the fun factor

## Cost-driving design decisions to preserve (important to hand off clearly)
- Location tracking, storage, and all stat computation happen locally on the phone — no backend, no database hosting
- Place-name lookup uses the phone's built-in OS-level location services rather than a paid third-party mapping/geocoding service
- No interactive live map is required for MVP — the "wrapped" experience is stat cards, not cartography, which keeps things simple and avoids map SDK costs
- Push notifications (e.g., "your day is wrapped!", "your year is wrapped!") should use the platform's free native notification system, not a third-party service — frequency (daily vs. yearly) doesn't add cost since these are local/scheduled notifications, not per-message billed
- Consider letting users turn off the more frequent notifications (e.g., keep weekly/monthly/yearly, mute daily) so the app doesn't feel naggy — this is a UX choice, not a cost one
- If launching on both major mobile platforms creates added cost or complexity, it's fine to ship to one platform first for MVP

## Suggested MVP scope (in priority order)
1. Location permission + background visit-logging that works reliably
2. Visit clustering logic (turning raw location pings into meaningful "you were here for X time" entries)
3. Local storage of visit history
4. Stats engine that computes the wrapped-style numbers from stored visits, parameterized by time window (day/week/month/year) so one engine serves all four cadences
5. The wrapped reveal UI/UX using one shared visual template scaled across the four cadences (this is the emotional core of the app — worth the most polish, especially the yearly version)
6. Scheduled local notifications for each cadence (end of day/week/month/year), with the ability to mute the more frequent ones
7. Data view + delete-my-data screen
8. (Stretch) Custom date range wrapped (any arbitrary range, not just the four fixed cadences)
9. (Stretch) Comparisons between periods (e.g., "busier than last month")
10. (Stretch, post-MVP) Cloud sync, social features, multiple platforms

## Success criteria for MVP
- Can run for at least a few weeks of real background tracking without draining battery noticeably or crashing
- Produces a wrapped reveal that feels genuinely fun/shareable, not just a table of numbers
- Zero recurring monetary cost to operate, other than the one-time/annual app store publishing fees