import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var store: FlightStore
    @AppStorage("pilotName")      private var pilotName = ""
    @AppStorage("pilotLicense")   private var pilotLicense = ""
    @AppStorage("defaultPICName") private var defaultPICName = ""

    @State private var urlInput: String = ""
    @State private var anonKeyInput: String = ""
    @State private var showKey = false
    @State private var savedBadge = false
    @State private var testResult: TestResult? = nil
    @State private var isTesting = false

    private enum TestResult {
        case success(Int)
        case failure(String)
    }

    var body: some View {
        Form {

            // MARK: Pilota
            Section("Pilota") {
                FieldRow(label: "Nome", placeholder: "Mario Rossi", text: $pilotName)
                FieldRow(label: "Numero Licenza", placeholder: "ITA.ATPL.12345", text: $pilotLicense)
                FieldRow(label: "PIC predefinito", placeholder: "Nome del comandante", text: $defaultPICName)
            }

            // MARK: Supabase
            Section {
                FieldRow(label: "Project URL", placeholder: "https://xxxx.supabase.co", text: $urlInput)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Anon Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        if showKey {
                            TextField("eyJhbGciOi...", text: $anonKeyInput)
                                .font(.system(.body, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("eyJhbGciOi...", text: $anonKeyInput)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)

                HStack(spacing: 10) {
                    Button("Salva credenziali") {
                        saveCredentials()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(urlInput.isEmpty || anonKeyInput.isEmpty)

                    Button("Test connessione") {
                        Task { await testConnection() }
                    }
                    .disabled(!hasCredentials)

                    Button("Cancella", role: .destructive) {
                        clearCredentials()
                    }

                    if isTesting {
                        ProgressView().controlSize(.small)
                    }

                    Spacer()

                    if savedBadge {
                        Label("Salvato", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }

                    if let result = testResult {
                        switch result {
                        case .success(let count):
                            Label("\(count) voli trovati", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green).font(.caption)
                        case .failure(let msg):
                            Label(msg, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red).font(.caption)
                        }
                    }
                }
                .padding(.top, 4)

            } header: {
                Text("Supabase")
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ottieni URL e Anon Key da supabase.com → Project Settings → API")
                    if !storedURL.isEmpty {
                        Label("Connesso: \(storedURL)", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // MARK: Info
            Section("Info") {
                HStack {
                    Text("Versione")
                    Spacer()
                    Text(appVersion).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Voli caricati")
                    Spacer()
                    Text("\(store.flights.count)").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Impostazioni")
        .frame(minWidth: 500)
        .onAppear { loadCredentials() }
    }

    // MARK: - Helpers

    private var storedURL: String {
        UserDefaults.standard.string(forKey: "supabaseURL") ?? ""
    }

    private var hasCredentials: Bool {
        !storedURL.isEmpty && Keychain.load(for: Keychain.supabaseAnonKey) != nil
    }

    private func loadCredentials() {
        urlInput     = storedURL
        anonKeyInput = Keychain.load(for: Keychain.supabaseAnonKey) ?? ""
    }

    private func saveCredentials() {
        let url = urlInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let key = anonKeyInput.trimmingCharacters(in: .whitespaces)

        UserDefaults.standard.set(url, forKey: "supabaseURL")
        UserDefaults.standard.synchronize()
        Keychain.save(key, for: Keychain.supabaseAnonKey)

        urlInput   = url
        testResult = nil
        withAnimation { savedBadge = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { savedBadge = false }
        }
    }

    private func clearCredentials() {
        UserDefaults.standard.removeObject(forKey: "supabaseURL")
        UserDefaults.standard.synchronize()
        Keychain.delete(for: Keychain.supabaseAnonKey)
        urlInput     = ""
        anonKeyInput = ""
        testResult   = nil
    }

    private func testConnection() async {
        isTesting  = true
        testResult = nil
        defer { isTesting = false }
        do {
            let flights = try await SupabaseProvider().fetchAll()
            testResult = .success(flights.count)
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - FieldRow

private struct FieldRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 2)
    }
}
