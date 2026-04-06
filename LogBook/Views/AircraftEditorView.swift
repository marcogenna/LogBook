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

                // MARK: - Identificazione
                Section("Identificazione") {
                    FieldRow("Marche", text: $draft.registration, placeholder: "es. SX-NEF", uppercase: true)
                    FieldRow("Codice ICAO", text: $draft.icaoCode, placeholder: "es. A320", uppercase: true)
                        .onChange(of: draft.icaoCode) { _, newVal in
                            autoFillFromICAO(newVal)
                        }
                }

                // MARK: - Costruttore e Modello
                Section("Costruttore e Modello") {
                    FieldRow("Costruttore", text: $draft.manufacturer, placeholder: "es. Airbus")
                    FieldRow("Modello", text: $draft.model, placeholder: "es. A320")
                        .onChange(of: draft.model) { _, newVal in
                            autoFillFromModel(newVal)
                        }
                    FieldRow("Variante / Serie", text: $draft.variant, placeholder: "es. 271N (identifica motorizzazione)")
                }

                // MARK: - Dettagli Tecnici
                Section("Dettagli Tecnici") {
                    FieldRow("Serial Number (MSN)", text: $draft.serialNumber, placeholder: "es. 7654")
                    FieldRow("Tipo Motore", text: $draft.engineType, placeholder: "es. PW1127G-JM")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Numero Motori").font(.caption).foregroundStyle(.secondary)
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

                    FieldRow("MTOW", text: $draft.mtow, placeholder: "es. 77,000 kg")
                    FieldRow("Primo Volo", text: $draft.firstFlight, placeholder: "es. 2018-03-15")
                }

                // MARK: - Classificazione
                Section("Classificazione EASA") {
                    Picker("Categoria", selection: classificationBinding) {
                        Text("Monomotore – Monopilota (SE)").tag(Classification.se)
                        Text("Multimotore – Monopilota (ME)").tag(Classification.me)
                        Text("Multipilota (MP)").tag(Classification.mp)
                    }
                    .pickerStyle(.radioGroup)
                }

                // MARK: - Operatore
                Section("Operatore") {
                    FieldRow("Compagnia", text: $draft.company, placeholder: "es. Aegean Airlines")
                }

                // MARK: - Note
                Section("Note") {
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 60, maxHeight: 120)
                        .font(.body)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "Nuovo Aeromobile" : "Modifica Aeromobile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
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
                            Label("Cerca su Internet", systemImage: "magnifyingglass.circle")
                        }
                    }
                    .disabled(draft.registration.trimmingCharacters(in: .whitespaces).count < 3 || isLooking)
                    .help("Cerca dati aeromobile per marche su internet")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 620)
        .alert("Ricerca Aeromobile", isPresented: $showLookupAlert) {
            Button("OK") {}
        } message: {
            Text(lookupError ?? "Nessun risultato trovato per \(draft.registration)")
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
            // Dati dall'API sono autorevoli: sovrascrivono sempre ICAO, manufacturer, model, variant
            if !info.icaoCode.isEmpty   { draft.icaoCode = info.icaoCode }
            if !info.manufacturer.isEmpty { draft.manufacturer = info.manufacturer }
            if !info.model.isEmpty      { draft.model = info.model }
            if !info.variant.isEmpty    { draft.variant = info.variant }
            if !info.company.isEmpty    { draft.company = info.company }

            // Dati tecnici: popola solo se vuoti
            if draft.engineType.isEmpty && !info.engineType.isEmpty { draft.engineType = info.engineType }
            if draft.engineCount == 0 { draft.engineCount = info.engineCount }
            if draft.mtow.isEmpty && !info.mtow.isEmpty { draft.mtow = info.mtow }

            // Classifica SE/ME/MP: sovrascrive
            draft.isSingleEngine = info.isSingleEngine
            draft.isMultiEngine = info.isMultiEngine
            draft.isMultiPilot = info.isMultiPilot
        } else {
            lookupError = nil
            showLookupAlert = true
        }
    }

    // MARK: - Auto-fill from ICAO code (locale)

    /// Chiamata quando cambia il campo "Codice ICAO" — es. l'utente scrive "A320" o "A20N"
    private func autoFillFromICAO(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard trimmed.count >= 3 else { return }

        Task {
            guard let icao = await lookup.lookupByICAOCode(trimmed) else { return }
            applyICAOInfo(icao)
        }
    }

    /// Chiamata quando cambia il campo "Modello" — accetta input libero:
    /// "A320", "Airbus A320", "Airbus A320-271N", "737-800", "Boeing 737", etc.
    private func autoFillFromModel(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return }

        // Parsa l'input libero per estrarre manufacturer, codice ICAO, variant
        let parsed = parseModelInput(trimmed)

        // Se ha trovato un manufacturer nell'input, usalo
        if let mfr = parsed.manufacturer, draft.manufacturer.isEmpty {
            draft.manufacturer = mfr
        }

        // Se ha trovato una variant nell'input, usala
        if let v = parsed.variant, draft.variant.isEmpty {
            draft.variant = v
        }

        // Cerca nel database ICAO
        Task {
            if let code = parsed.icaoCode,
               let icao = await lookup.lookupByICAOCode(code) {
                if draft.icaoCode.isEmpty { draft.icaoCode = code }
                applyICAOInfo(icao)
            }
        }
    }

    /// Applica i dati dal database ICAO locale ai campi vuoti
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

    /// Mapping nomi costruttori → prefisso ICAO dei modelli
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

        // 1. Cerca manufacturer noto all'inizio dell'input
        //    "Airbus A320-271N" → manufacturer="Airbus", rest="A320-271N"
        var rest = upper
        for (name, _) in Self.knownManufacturers {
            if upper.hasPrefix(name) {
                result.manufacturer = name.capitalized
                rest = String(upper.dropFirst(name.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // 2. Separa modello e variant dal resto
        //    "A320-271N" → base="A320", variant="271N"
        //    "A320" → base="A320", variant=nil
        //    "737-800" → base="737", variant="800"
        let normalized = rest.replacingOccurrences(of: "-", with: " ")
        let parts = normalized.split(separator: " ").map(String.init)

        if let base = parts.first {
            // Cerca direttamente nel database ICAO
            result.icaoCode = base

            // Variant è tutto dopo il primo token
            if parts.count >= 2 {
                result.variant = parts.dropFirst().joined(separator: "")
            }

            // Se il codice base non è un codice ICAO standard, prova mapping comuni
            // "320" → "A320", "737" → "B737"
            if base.allSatisfy(\.isNumber) {
                // Solo numeri: prova ad aggiungere prefisso dal manufacturer
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
