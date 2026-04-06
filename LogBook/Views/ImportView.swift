import SwiftUI
import AppKit

struct ImportView: View {

    @EnvironmentObject private var store: FlightStore
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .pick
    @State private var preview: [Flight] = []

    private enum Phase {
        case pick, preview, importing, done(Int), failed(String)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch phase {
                case .pick:
                    pickView
                case .preview:
                    previewView
                case .importing:
                    progressView
                case .done(let count):
                    doneView(count: count)
                case .failed(let msg):
                    failedView(msg)
                }
            }
            .navigationTitle("Importa Logbook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
                if case .preview = phase {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Importa \(preview.count) voli") {
                            doImport()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 460)
    }

    // MARK: - Pick

    private var pickView: some View {
        VStack(spacing: 24) {
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Seleziona un file da importare")
                    .font(.title2.bold())
                Text("Supporta PilotLog (.db / .json), LogTen Pro,\ne qualsiasi database SQLite con dati di volo.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button("Scegli file…") { openFile() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Preview

    private var previewView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("\(preview.count) voli trovati", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Spacer()
                Text("Anteprima (prime 5 righe)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            // Lista semplice (evita Table per affidabilità)
            VStack(spacing: 0) {
                previewHeader
                ForEach(Array(preview.prefix(5))) { flight in
                    previewRow(flight)
                }
            }
            .padding(.horizontal)

            Divider()

            Text("I voli importati saranno salvati in locale e sincronizzati su Supabase quando disponibile.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
        }
    }

    private var previewHeader: some View {
        HStack(spacing: 0) {
            Text("Data").frame(width: 90, alignment: .leading)
            Text("Rotta").frame(width: 130, alignment: .leading)
            Text("Tipo").frame(width: 80, alignment: .leading)
            Text("Marche").frame(width: 80, alignment: .leading)
            Text("Totale").frame(width: 60, alignment: .trailing)
            Text("PIC").frame(width: 60, alignment: .trailing)
            Spacer()
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }

    private func previewRow(_ f: Flight) -> some View {
        HStack(spacing: 0) {
            Text(f.date, style: .date).frame(width: 90, alignment: .leading)
            Text(f.route).frame(width: 130, alignment: .leading)
            Text(f.aircraftType).frame(width: 80, alignment: .leading)
            Text(f.aircraftRegistration).frame(width: 80, alignment: .leading)
            Text(f.totalFlightTime > 0 ? f.totalFlightTime.hoursMinutes : "—")
                .frame(width: 60, alignment: .trailing)
            Text(f.picTime > 0 ? f.picTime.hoursMinutes : "—")
                .frame(width: 60, alignment: .trailing)
            Spacer()
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.vertical, 4)
    }

    // MARK: - Progress / Done / Failed

    private var progressView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(preview.isEmpty ? "Lettura file in corso…" : "Importazione in corso…")
                .font(.headline)
            Text("Potrebbe richiedere qualche secondo.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func doneView(count: Int) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("\(count) voli importati")
                .font(.title2.bold())
            Text("Disponibili nel Logbook.")
                .foregroundStyle(.secondary)
            Button("Chiudi") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func failedView(_ msg: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)
            Text("Importazione fallita")
                .font(.title2.bold())
            Text(msg)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)
                .textSelection(.enabled)
            Button("Riprova") { phase = .pick }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - NSOpenPanel (bypass SwiftUI fileImporter issues)

    private func openFile() {
        let panel = NSOpenPanel()
        panel.title = "Seleziona logbook da importare"
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        phase = .importing

        // Copia nel sandbox temp, poi parsa in background
        Task {
            do {
                let tempDir  = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent(
                    "import_\(UUID().uuidString).\(url.pathExtension)"
                )
                try FileManager.default.copyItem(at: url, to: tempFile)
                defer { try? FileManager.default.removeItem(at: tempFile) }

                let flights = try await Task.detached(priority: .userInitiated) {
                    try SQLiteImporter.importFlights(from: tempFile)
                }.value

                preview = flights
                phase   = .preview
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func doImport() {
        let count = preview.count
        phase = .importing
        Task {
            store.importFlights(preview)
            phase = .done(count)
        }
    }
}
