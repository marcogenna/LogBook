import SwiftUI

@main
struct LogBookApp: App {

    @StateObject private var store = FlightStore()
    @State private var showImport = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1100, minHeight: 600)
                .sheet(isPresented: $showImport) {
                    ImportView().environmentObject(store)
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .importExport) {
                Button("Importa da SQLite…") { showImport = true }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            CommandGroup(after: .newItem) {
                Button("Sincronizza con Supabase") {
                    Task { await store.fetchFlights() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView().environmentObject(store)
        }
    }
}
