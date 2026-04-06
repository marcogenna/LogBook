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
            .navigationTitle("Import Logbook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if case .preview = phase {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import \(preview.count) flights") {
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
                Text("Select a file to import")
                    .font(.title2.bold())
                Text("Supports PilotLog (.db / .json), LogTen Pro,\nand any SQLite database with flight data.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button("Choose file…") { openFile() }
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
                Label("\(preview.count) flights found", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Spacer()
                Text("Preview (first 5 rows)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            // Simple list (avoids Table for reliability)
            VStack(spacing: 0) {
                previewHeader
                ForEach(Array(preview.prefix(5))) { flight in
                    previewRow(flight)
                }
            }
            .padding(.horizontal)

            Divider()

            Text("Imported flights will be saved locally and synced to Supabase when available.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
        }
    }

    private var previewHeader: some View {
        HStack(spacing: 0) {
            Text("Date").frame(width: 90, alignment: .leading)
            Text("Route").frame(width: 130, alignment: .leading)
            Text("Type").frame(width: 80, alignment: .leading)
            Text("Reg.").frame(width: 80, alignment: .leading)
            Text("Total").frame(width: 60, alignment: .trailing)
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
            Text(preview.isEmpty ? "Reading file…" : "Importing…")
                .font(.headline)
            Text("This may take a few seconds.")
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
            Text("\(count) flights imported")
                .font(.title2.bold())
            Text("Available in the Logbook.")
                .foregroundStyle(.secondary)
            Button("Close") { dismiss() }
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
            Text("Import failed")
                .font(.title2.bold())
            Text(msg)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)
                .textSelection(.enabled)
            Button("Retry") { phase = .pick }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - NSOpenPanel (bypass SwiftUI fileImporter issues)

    private func openFile() {
        let panel = NSOpenPanel()
        panel.title = "Select logbook to import"
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        phase = .importing

        // Copy to sandbox temp, then parse in background
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
