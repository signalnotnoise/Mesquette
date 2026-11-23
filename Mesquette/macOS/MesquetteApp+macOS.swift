//
//  MesquetteApp+macOS.swift
//  Mesquette
//

#if os(macOS)
import SwiftUI
import ShapERuntime

@main
struct MesquetteApp: App {

    @State private var appModel = AppModel()
    @State private var showAbout = false
    @AppStorage("mesquette.showGenerationHistory") private var isHistoryVisible = false

    var body: some Scene {
        WindowGroup(AppIdentity.name) {
            AppLaunchView {
                MacContentView()
                    .environment(appModel)
            }
            .sheet(isPresented: $showAbout) {
                AboutMesquetteView()
                    .environment(appModel)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        // Menu + ⌃⌘F as a discoverable fullscreen toggle (green button also works).
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(AppIdentity.name)") {
                    showAbout = true
                }
            }
            CommandGroup(after: .sidebar) {
                Button(isHistoryVisible ? "Hide History" : "Show History") {
                    isHistoryVisible.toggle()
                }
                .keyboardShortcut("y", modifiers: [.command, .shift])
            }
            CommandGroup(after: .windowSize) {
                Button("Toggle Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.control, .command])
            }
        }

        Settings {
            DirectorAvailabilityView(appModel: appModel)
                .padding(20)
                .frame(minWidth: 360)
        }
    }
}
#endif
