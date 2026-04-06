# LogBook

**ATPL Flight Logbook for macOS** — A native SwiftUI application for professional pilots to track flight hours, aircraft, and statistics in compliance with EASA standards.

## Features

- **Flight Logbook** — Full EASA-format flight log with all required fields: route, times (SE/ME/MP), landings, night/IFR, pilot function (PIC, Co-Pilot, Dual, Instructor), simulator
- **Aircraft Management** — Detailed aircraft database with ICAO type codes, manufacturer, model, variant, engine info, MTOW, and EASA classification (SE/ME/MP)
- **Online Aircraft Lookup** — Auto-fill aircraft details by registration using the free adsbdb.com API + local ICAO DOC8643 database
- **Smart Type Parsing** — Understands free-text like "Airbus A320-271N" and auto-fills manufacturer, model, variant, and ICAO code
- **Statistics Dashboard** — Total hours, landings, time breakdowns by category, monthly charts, per-aircraft summaries
- **Import** — Import flights from PilotLog (.db/.json), LogTen Pro, and any SQLite database
- **Offline-First** — All data stored locally as JSON; works without internet
- **Supabase Sync** — Optional cloud sync via Supabase with offline-first merge strategy (most recent wins)
- **Search & Sort** — Full-text search across all flight fields, sortable table columns

## Architecture

```
LogBook/
  Models/
    Flight.swift          — Flight data model (Codable, snake_case for Supabase)
    Aircraft.swift        — Aircraft model with ICAO types & EASA classification
    FlightStore.swift     — Main store: CRUD, sync, import, statistics, aircraft parsing
  Views/
    ContentView.swift     — NavigationSplitView with sidebar
    LogbookView.swift     — Flight table with sort, search, context menu
    FlightEditorView.swift — Flight editor form with time parsing (hh:mm)
    AircraftListView.swift — Aircraft table with import-from-flights
    AircraftEditorView.swift — Aircraft editor with online lookup & auto-fill
    StatisticsView.swift  — Dashboard with charts (Swift Charts)
    SettingsView.swift    — Pilot info & Supabase credentials
    ImportView.swift      — SQLite/JSON flight importer
  Services/
    LocalStore.swift      — JSON persistence in Application Support
    SupabaseProvider.swift — REST client for Supabase (fetch, save, delete)
    AircraftLookupService.swift — Online + offline aircraft data lookup
    SQLiteImporter.swift  — SQLite flight database parser
  Resources/
    icao_types.json       — ~140 ICAO DOC8643 aircraft types (offline database)
```

**Key patterns:**
- Offline-first: LocalStore saves immediately, Supabase syncs in background
- Merge strategy: `updatedAt` timestamp wins on conflict
- Pending sync queue: flights modified offline are queued and pushed when online
- Network monitor: `NWPathMonitor` triggers sync when connectivity returns

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15.0+
- Swift 5.9+

## Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/marcogenna/LogBook.git
   cd LogBook
   ```

2. Open in Xcode:
   ```bash
   open LogBook.xcodeproj
   ```

3. Build and run (Cmd+R)

### Supabase (Optional)

To enable cloud sync:

1. Create a free project at [supabase.com](https://supabase.com)
2. Run `supabase/schema.sql` in the SQL Editor to create the `flights` and `aircraft` tables
3. In the app, go to Settings and enter your Project URL and Anon Key

## Roadmap

These are features we'd love help with. Pick one and submit a PR!

### High Priority

- [ ] **CSV/PDF Export** — Export logbook to CSV and EASA-format PDF for authority submissions
- [ ] **EASA Logbook PDF** — Generate a printable logbook matching the official EASA format
- [ ] **iCloud Sync** — Replace or complement Supabase with CloudKit for zero-config sync
- [ ] **Unit Tests** — Add XCTest coverage for FlightStore, parsing logic, and merge strategy
- [ ] **String Catalogs** — Migrate hardcoded strings to Xcode String Catalogs for proper i18n

### Medium Priority

- [ ] **Airport Database** — ICAO/IATA airport codes with autocomplete in departure/arrival fields
- [ ] **Approach Type Tracking** — Track ILS, VOR, RNAV, Visual approaches per flight
- [ ] **Crew Management** — Track crew members and roles across flights
- [ ] **Dark Mode** — Full dark mode support with proper color assets
- [ ] **Statistics Improvements** — More charts: cumulative hours, year-over-year comparison, currency tracking
- [ ] **Import from ForeFlight** — Parse ForeFlight CSV export format
- [ ] **Import from myFlightbook** — Parse myFlightbook export format

### Nice to Have

- [ ] **iOS/iPadOS Companion** — Universal app or dedicated mobile version
- [ ] **Multi-User Auth** — Supabase Auth with Row Level Security for shared instances
- [ ] **CI/CD** — GitHub Actions for build verification and test runs
- [ ] **Widgets** — macOS widgets showing recent flights or total hours
- [ ] **Currency Tracking** — Alert when recency requirements are approaching expiry
- [ ] **License & Rating Tracker** — Track licenses, ratings, and their expiry dates
- [ ] **Flight Map** — Visualize routes on a map using airport coordinates

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Run the build to verify (Cmd+B)
5. Commit and push (`git push origin feature/my-feature`)
6. Open a Pull Request

Please follow the existing code style and patterns (SwiftUI, MVVM with ObservableObject, offline-first).

## License

This project is open source. See [LICENSE](LICENSE) for details.
