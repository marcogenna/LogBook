import SwiftUI
import Charts

struct StatisticsView: View {

    @EnvironmentObject private var store: FlightStore
    @State private var selectedYear: Int? = nil

    private var years: [Int] { store.availableYears }
    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    private var displayYear: Int { selectedYear ?? currentYear }

    private var yearTotals: FlightTotals {
        selectedYear == nil ? store.totals : store.totals(forYear: displayYear)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Year picker
                HStack {
                    Text("Statistiche")
                        .font(.largeTitle.bold())
                    Spacer()
                    Picker("Anno", selection: $selectedYear) {
                        Text("Tutti").tag(nil as Int?)
                        ForEach(years, id: \.self) { year in
                            Text(String(year)).tag(year as Int?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }

                // Summary cards
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    StatCard(title: "Voli Totali", value: "\(yearTotals.flightCount)", unit: "voli", color: .blue)
                    StatCard(title: "Ore Totali", value: yearTotals.totalFlightTime.hoursMinutes, unit: "hh:mm", color: .indigo)
                    StatCard(title: "Atterraggi Diurni", value: "\(yearTotals.dayLandings)", unit: "att.", color: .orange)
                    StatCard(title: "Atterraggi Notturni", value: "\(yearTotals.nightLandings)", unit: "att.", color: .purple)
                }

                // Time breakdown
                GroupBox("Ripartizione Tempi di Volo") {
                    VStack(spacing: 0) {
                        TimeRow(label: "Monomotore Monopilota (SE)", hours: yearTotals.seSinglePilotTime, color: .cyan)
                        Divider()
                        TimeRow(label: "Multimotore Monopilota (ME)", hours: yearTotals.meSinglePilotTime, color: .teal)
                        Divider()
                        TimeRow(label: "Multipilota (MP)", hours: yearTotals.multiPilotTime, color: .blue)
                        Divider()
                        TimeRow(label: "Notte", hours: yearTotals.nightTime, color: .indigo)
                        Divider()
                        TimeRow(label: "IFR", hours: yearTotals.ifrTime, color: .purple)
                    }
                    .padding(.top, 8)
                }

                // Function time
                GroupBox("Funzione Pilota") {
                    VStack(spacing: 0) {
                        TimeRow(label: "PIC", hours: yearTotals.picTime, color: .green)
                        Divider()
                        TimeRow(label: "Co-Pilota (SIC)", hours: yearTotals.coPilotTime, color: .yellow)
                        Divider()
                        TimeRow(label: "Duale", hours: yearTotals.dualTime, color: .orange)
                        Divider()
                        TimeRow(label: "Istruttore", hours: yearTotals.instructorTime, color: .red)
                        Divider()
                        TimeRow(label: "Simulatore (FSTD)", hours: yearTotals.fstdTime, color: .gray)
                    }
                    .padding(.top, 8)
                }

                // Monthly chart
                if !store.flights.isEmpty {
                    GroupBox("Ore per Mese (\(displayYear))") {
                        MonthlyChart(year: displayYear, flights: store.flights)
                            .frame(height: 200)
                            .padding(.top, 8)
                    }
                }

                // Aircraft types
                if !aircraftSummary.isEmpty {
                    GroupBox("Per Tipo Aeromobile") {
                        AircraftBreakdown(data: aircraftSummary)
                            .padding(.top, 8)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Statistiche")
    }

    private var aircraftSummary: [(type: String, hours: Double, flights: Int)] {
        var dict: [String: (Double, Int)] = [:]
        let source = selectedYear == nil ? store.flights : store.flights.filter {
            Calendar.current.component(.year, from: $0.date) == displayYear
        }
        for flight in source {
            let key = flight.aircraftType.isEmpty ? "N/D" : flight.aircraftType
            let existing = dict[key] ?? (0, 0)
            dict[key] = (existing.0 + flight.totalFlightTime, existing.1 + 1)
        }
        return dict.map { (type: $0.key, hours: $0.value.0, flights: $0.value.1) }
            .sorted { $0.hours > $1.hours }
    }
}

// MARK: - Supporting Views

private struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.title, design: .monospaced).bold())
                    .foregroundStyle(color)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TimeRow: View {
    let label: String
    let hours: Double
    let color: Color

    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4, height: 16)
            Text(label)
            Spacer()
            Text(hours.hoursMinutes)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(hours > 0 ? .primary : .tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

private struct MonthlyChart: View {
    let year: Int
    let flights: [Flight]

    private struct MonthData: Identifiable {
        var id: Int { month }
        let month: Int
        let hours: Double
    }

    private var data: [MonthData] {
        let calendar = Calendar.current
        var monthly = [Int: Double]()
        for flight in flights where calendar.component(.year, from: flight.date) == year {
            let m = calendar.component(.month, from: flight.date)
            monthly[m, default: 0] += flight.totalFlightTime
        }
        return (1...12).map { MonthData(month: $0, hours: monthly[$0] ?? 0) }
    }

    private static let monthNames = ["Gen","Feb","Mar","Apr","Mag","Giu",
                                      "Lug","Ago","Set","Ott","Nov","Dic"]

    var body: some View {
        Chart(data) { item in
            BarMark(
                x: .value("Mese", Self.monthNames[item.month - 1]),
                y: .value("Ore", item.hours)
            )
            .foregroundStyle(.blue.gradient)
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v.hoursMinutes)
                            .font(.caption)
                    }
                }
            }
        }
    }
}

private struct AircraftBreakdown: View {
    let data: [(type: String, hours: Double, flights: Int)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text(item.type)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text("\(item.flights) voli")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(item.hours.hoursMinutes)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                if index < data.count - 1 { Divider() }
            }
        }
    }
}
