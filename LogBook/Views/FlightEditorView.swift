import SwiftUI

struct FlightEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FlightStore

    @State private var draft: Flight
    @State private var regSuggestions: [Aircraft] = []
    @State private var showSuggestions = false
    private let onSave: (Flight) -> Void
    private let isNew: Bool

    init(flight: Flight, onSave: @escaping (Flight) -> Void) {
        _draft = State(initialValue: flight)
        self.onSave = onSave
        self.isNew = flight.aircraftType.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: 1 – Date & Route
                Section("Date & Route") {
                    DatePicker("Date", selection: $draft.date, displayedComponents: .date)

                    HStack {
                        VStack(alignment: .leading) {
                            Label("Departure (ICAO)", systemImage: "airplane.departure")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("LIMC", text: $draft.departurePlace)
                                .textFieldStyle(.squareBorder)
                                .textCase(.uppercase)
                            DatePicker("Time", selection: Binding(
                                get: { draft.departureTime ?? draft.date },
                                set: { draft.departureTime = $0 }
                            ), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        }

                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.top, 16)

                        VStack(alignment: .leading) {
                            Label("Arrival (ICAO)", systemImage: "airplane.arrival")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("LIRN", text: $draft.arrivalPlace)
                                .textFieldStyle(.squareBorder)
                                .textCase(.uppercase)
                            DatePicker("Time", selection: Binding(
                                get: { draft.arrivalTime ?? draft.date },
                                set: { draft.arrivalTime = $0 }
                            ), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        }
                    }
                }

                // MARK: 2 – Aircraft
                Section("Aircraft") {
                    LabeledContent("Registration") {
                        VStack(alignment: .trailing, spacing: 2) {
                            TextField("SX-DVQ", text: $draft.aircraftRegistration)
                                .textCase(.uppercase)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: draft.aircraftRegistration) { _, newVal in
                                    updateRegSuggestions(newVal)
                                }

                            if showSuggestions && !regSuggestions.isEmpty {
                                VStack(spacing: 0) {
                                    ForEach(regSuggestions.prefix(5)) { ac in
                                        Button {
                                            applyAircraft(ac)
                                        } label: {
                                            HStack {
                                                Text(ac.registration)
                                                    .font(.system(.caption, design: .monospaced))
                                                Spacer()
                                                Text(ac.type)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .background(.background)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(.separator, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    LabeledContent("Type") {
                        TextField("A320", text: $draft.aircraftType)
                            .textCase(.uppercase)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // MARK: 3 – Time (Single/Multi/Total)
                Section("Flight Times") {
                    HoursField(label: "Single Engine – Single Pilot (SE)", value: $draft.seSinglePilotTime)
                    HoursField(label: "Multi Engine – Single Pilot (ME)", value: $draft.meSinglePilotTime)
                    HoursField(label: "Multi Pilot (MP)", value: $draft.multiPilotTime)
                    Divider()
                    HoursField(label: "Total Flight", value: $draft.totalFlightTime, bold: true)
                }

                // MARK: 4 – PIC Name
                Section("PIC") {
                    LabeledContent("PIC Name") {
                        TextField("John Smith", text: $draft.picName)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // MARK: 5 – Landings
                Section("Landings") {
                    Stepper("Day: \(draft.dayLandings)", value: $draft.dayLandings, in: 0...99)
                    Stepper("Night: \(draft.nightLandings)", value: $draft.nightLandings, in: 0...99)
                }

                // MARK: 6 – Operational Conditions
                Section("Operational Conditions") {
                    HoursField(label: "Night Hours", value: $draft.nightTime)
                    HoursField(label: "IFR Hours", value: $draft.ifrTime)
                }

                // MARK: 7 – Pilot Function
                Section("Pilot Function") {
                    HoursField(label: "PIC", value: $draft.picTime)
                    HoursField(label: "Co-Pilot (SIC)", value: $draft.coPilotTime)
                    HoursField(label: "Dual", value: $draft.dualTime)
                    HoursField(label: "Instructor", value: $draft.instructorTime)
                }

                // MARK: 8 – FSTD/Simulatore
                Section("Simulator (FSTD)") {
                    LabeledContent("FSTD Type") {
                        TextField("FFS B738", text: $draft.fstdType)
                            .multilineTextAlignment(.trailing)
                    }
                    HoursField(label: "Simulator Hours", value: $draft.fstdTime)
                }

                // MARK: 9 – Remarks
                Section("Note / Endorsements") {
                    TextEditor(text: $draft.remarks)
                        .frame(minHeight: 60, maxHeight: 120)
                        .font(.body)
                }

            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New Flight" : "Edit Flight")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 700)
    }

    private var isValid: Bool {
        !draft.aircraftType.isEmpty && draft.totalFlightTime > 0
    }

    // MARK: - Aircraft autocomplete

    private func updateRegSuggestions(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard q.count >= 2 else {
            regSuggestions = []
            showSuggestions = false
            return
        }
        regSuggestions = store.aircraft.filter {
            $0.registration.uppercased().contains(q)
        }
        showSuggestions = !regSuggestions.isEmpty
    }

    private func applyAircraft(_ ac: Aircraft) {
        draft.aircraftRegistration = ac.registration.uppercased()
        draft.aircraftType = ac.type.uppercased()

        // Auto-classify SE/ME/MP times if total > 0 and no specific time set
        if draft.totalFlightTime > 0 &&
           draft.seSinglePilotTime == 0 &&
           draft.meSinglePilotTime == 0 &&
           draft.multiPilotTime == 0 {
            if ac.isSingleEngine {
                draft.seSinglePilotTime = draft.totalFlightTime
            } else if ac.isMultiEngine {
                draft.meSinglePilotTime = draft.totalFlightTime
            } else if ac.isMultiPilot {
                draft.multiPilotTime = draft.totalFlightTime
            }
        }

        showSuggestions = false
        regSuggestions = []
    }
}

// MARK: – Hours Field

private struct HoursField: View {
    let label: String
    @Binding var value: Double
    var bold: Bool = false

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField("0:00", text: $text)
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                    .frame(width: 70)
                    .font(.system(.body, design: .monospaced).weight(bold ? .semibold : .regular))
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { parseText() }
                    }
                    .onAppear { text = value > 0 ? value.hoursMinutes : "" }
                    .onChange(of: value) { _, v in
                        if !focused { text = v > 0 ? v.hoursMinutes : "" }
                    }
                Text("hh:mm")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func parseText() {
        // Accepts: "1:30", "1.5", "90" (minutes if > 24)
        let clean = text.trimmingCharacters(in: .whitespaces)
        if clean.contains(":") {
            let parts = clean.split(separator: ":").map { Int($0) ?? 0 }
            if parts.count == 2 {
                value = Double(parts[0]) + Double(parts[1]) / 60.0
            }
        } else if let d = Double(clean.replacingOccurrences(of: ",", with: ".")) {
            value = d > 24 ? d / 60.0 : d
        }
        text = value > 0 ? value.hoursMinutes : ""
    }
}
