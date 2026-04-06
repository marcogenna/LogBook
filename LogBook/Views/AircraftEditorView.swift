import SwiftUI

struct AircraftEditorView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var draft: Aircraft
    @State private var isLooking = false
    @State private var lookupError: String?
    @State private var showLookupAlert = false

    private let onSave: (Aircraft) -> Void
    private let isNew: Bool
    private let lookup = AircraftLookupService.shared

    init(aircraft: Aircraft, onSave: @escaping (Aircraft) -> Void) {
        _draft = State(initialValue: aircraft)
        self.onSave = onSave
        self.isNew = aircraft.registration.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: - Identification
                Section("Identification") {
                    FieldRow("Registration", text: $draft.registration, placeholder: "e.g. SX-NEF", uppercase: true)
                    FieldRow("ICAO Code", text: $draft.icaoCode, placeholder: "e.g. A320", uppercase: true)
                        .onChange(of: draft.icaoCode) { _, newVal in
                            autoFillFromICAO(newVal)
                        }
                }

                // MARK: - Manufacturer & Model
                Section("Manufacturer & Model") {
                    FieldRow("Manufacturer", text: $draft.manufacturer, placeholder: "e.g. Airbus")
                    FieldRow("Model", text: $draft.model, placeholder: "e.g. A320")
                        .onChange(of: draft.model) { _, newVal in
                            autoFillFromModel(newVal)
                        }
                    FieldRow("Variant / Series", text: $draft.variant, placeholder: "e.g. 271N (identifies engine variant)")
                }

                // MARK: - Technical Details
                Section("Technical Details") {
                    FieldRow("Serial Number (MSN)", text: $draft.serialNumber, placeholder: "e.g. 7654")
                    FieldRow("Engine Type", text: $draft.engineType, placeholder: "e.g. PW1127G-JM")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Engine Count").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $draft.engineCount) {
                            Text("—").tag(0)
                            Text("1").tag(1)
                            Text("2").tag(2)
                            Text("3").tag(3)
                            Text("4").tag(4)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    FieldRow("MTOW", text: $draft.mtow, placeholder: "e.g. 77,000 kg")
                    FieldRow("First Flight", text: $draft.firstFlight, placeholder: "e.g. 2018-03-15")
                }

                // MARK: - Classification
                Section("EASA Classification") {
                    Picker("Category", selection: classificationBinding) {
                        Text("Single Engine – Single Pilot (SE)").tag(Classification.se)
                        Text("Multi Engine – Single Pilot (ME)").tag(Classification.me)
                        Text("Multi Pilot (MP)").tag(Classification.mp)
                    }
                    .pickerStyle(.radioGroup)
                }

                // MARK: - Operator
                Section("Operator") {
                    FieldRow("Operator", text: $draft.company, placeholder: "e.g. Aegean Airlines")
                }

                // MARK: - Notes
                Section("Notes") {
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 60, maxHeight: 120)
                        .font(.body)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New Aircraft" : "Edit Aircraft")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await performLookup() }
                    } label: {
                        if isLooking {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Label("Search Online", systemImage: "magnifyingglass.circle")
                        }
                    }
                    .disabled(draft.registration.trimmingCharacters(in: .whitespaces).count < 3 || isLooking)
                    .help("Look up aircraft data by registration online")
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
        .frame(minWidth: 520, minHeight: 620)
        .alert("Aircraft Lookup", isPresented: $showLookupAlert) {
            Button("OK") {}
        } message: {
            Text(lookupError ?? "No results found for \(draft.registration)")
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        !draft.registration.trimmingCharacters(in: .whitespaces).isEmpty &&
        (!draft.icaoCode.isEmpty || !draft.model.isEmpty)
    }

    // MARK: - Internet Lookup

    private func performLookup() async {
        isLooking = true
        defer { isLooking = false }

        let info = await lookup.fullLookup(registration: draft.registration)

        if let info = info {
            // API data is authoritative: always overwrite ICAO, manufacturer, model, variant
            if !info.icaoCode.isEmpty   { draft.icaoCode = info.icaoCode }
            if !info.manufacturer.isEmpty { draft.manufacturer = info.manufacturer }
            if !info.model.isEmpty      { draft.model = info.model }
            if !info.variant.isEmpty    { draft.variant = info.variant }
            if !info.company.isEmpty    { draft.company = info.company }

            // Technical data: fill only if empty
            if draft.engineType.isEmpty && !info.engineType.isEmpty { draft.engineType = info.engineType }
            if draft.engineCount == 0 { draft.engineCount = info.engineCount }
            if draft.mtow.isEmpty && !info.mtow.isEmpty { draft.mtow = info.mtow }

            // SE/ME/MP classification: overwrite
            draft.isSingleEngine = info.isSingleEngine
            draft.isMultiEngine = info.isMultiEngine
            draft.isMultiPilot = info.isMultiPilot
        } else {
            lookupError = nil
            showLookupAlert = true
        }
    }

    // MARK: - Auto-fill from ICAO code (local)

    /// Called when the ICAO Code field changes — e.g. user types "A320" or "A20N"
    private func autoFillFromICAO(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard trimmed.count >= 3 else { return }

        Task {
            guard let icao = await lookup.lookupByICAOCode(trimmed) else { return }
            applyICAOInfo(icao)
        }
    }

    /// Called when the Model field changes — accepts free-form input:
    /// "A320", "Airbus A320", "Airbus A320-271N", "737-800", "Boeing 737", etc.
    private func autoFillFromModel(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return }

        // Parse free-form input to extract manufacturer, ICAO code, variant
        let parsed = parseModelInput(trimmed)

        // If a manufacturer was found in the input, use it
        if let mfr = parsed.manufacturer, draft.manufacturer.isEmpty {
            draft.manufacturer = mfr
        }

        // If a variant was found in the input, use it
        if let v = parsed.variant, draft.variant.isEmpty {
            draft.variant = v
        }

        // Look up in ICAO database
        Task {
            if let code = parsed.icaoCode,
               let icao = await lookup.lookupByICAOCode(code) {
                if draft.icaoCode.isEmpty { draft.icaoCode = code }
                applyICAOInfo(icao)
            }
        }
    }

    /// Apply data from local ICAO database to empty fields
    private func applyICAOInfo(_ icao: AircraftLookupService.ICAOType) {
        if draft.manufacturer.isEmpty { draft.manufacturer = icao.manufacturer }
        if draft.engineCount == 0 { draft.engineCount = icao.engineCount }
        if draft.mtow.isEmpty { draft.mtow = icao.mtow }

        // Auto-classifica
        if !draft.isSingleEngine && !draft.isMultiEngine && !draft.isMultiPilot {
            draft.isSingleEngine = icao.engineCount == 1
            draft.isMultiEngine = icao.engineCount == 2 && icao.wtc == "L"
            draft.isMultiPilot = icao.engineCount >= 2 && icao.wtc != "L"
        }
    }

    // MARK: - Parse model input

    /// Mapping manufacturer names → ICAO model prefix
    private static let knownManufacturers: [(name: String, prefix: String)] = [
        ("AIRBUS", "A"),
        ("BOEING", "B"),
        ("CESSNA", "C"),
        ("PIPER", "P"),
        ("BEECHCRAFT", "BE"),
        ("BOMBARDIER", ""),
        ("EMBRAER", "E"),
        ("ATR", "AT"),
        ("DIAMOND", "DA"),
        ("PILATUS", "PC"),
        ("DASSAULT", "F"),
        ("GULFSTREAM", "G"),
        ("FOKKER", "F"),
        ("SAAB", "S"),
        ("DE HAVILLAND", "DH"),
        ("MCDONNELL DOUGLAS", "MD"),
    ]

    private struct ParsedModelInput {
        var manufacturer: String?
        var icaoCode: String?
        var variant: String?
    }

    private func parseModelInput(_ input: String) -> ParsedModelInput {
        let upper = input.uppercased()
        var result = ParsedModelInput()

        // 1. Find known manufacturer at the start of input
        //    "Airbus A320-271N" → manufacturer="Airbus", rest="A320-271N"
        var rest = upper
        for (name, _) in Self.knownManufacturers {
            if upper.hasPrefix(name) {
                result.manufacturer = name.capitalized
                rest = String(upper.dropFirst(name.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // 2. Separate model and variant from the rest
        //    "A320-271N" → base="A320", variant="271N"
        //    "A320" → base="A320", variant=nil
        //    "737-800" → base="737", variant="800"
        let normalized = rest.replacingOccurrences(of: "-", with: " ")
        let parts = normalized.split(separator: " ").map(String.init)

        if let base = parts.first {
            // Search directly in ICAO database
            result.icaoCode = base

            // Variant is everything after the first token
            if parts.count >= 2 {
                result.variant = parts.dropFirst().joined(separator: "")
            }

            // If the base code is not a standard ICAO code, try common mappings
            // "320" → "A320", "737" → "B737"
            if base.allSatisfy(\.isNumber) {
                // Numbers only: try adding prefix from manufacturer
                if let mfr = result.manufacturer?.uppercased(),
                   let entry = Self.knownManufacturers.first(where: { $0.name == mfr }),
                   !entry.prefix.isEmpty {
                    result.icaoCode = entry.prefix + base
                }
            }
        }

        return result
    }

    // MARK: - Classification binding

    private enum Classification: String {
        case se, me, mp
    }

    private var classificationBinding: Binding<Classification> {
        Binding(
            get: {
                if draft.isSingleEngine { return .se }
                if draft.isMultiEngine  { return .me }
                return .mp
            },
            set: { val in
                draft.isSingleEngine = val == .se
                draft.isMultiEngine  = val == .me
                draft.isMultiPilot   = val == .mp
            }
        )
    }
}

// MARK: - Reusable Field Row

private struct FieldRow: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    var uppercase: Bool = false

    init(_ label: String, text: Binding<String>, placeholder: String, uppercase: Bool = false) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.uppercase = uppercase
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .modifier(UppercaseModifier(active: uppercase))
        }
    }
}

private struct UppercaseModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.textCase(.uppercase)
        } else {
            content
        }
    }
}
