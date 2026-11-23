//
//  MesquetteApp+visionOS.swift
//  Mesquette
//

#if os(visionOS)
import SwiftUI
import ShapERuntime

@main
struct MesquetteApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            AppLaunchView {
                ContentView()
                    .environment(appModel)
            }
        }
        // Create console: prompt, invent/compile, quality, generate, look around.
        .defaultSize(width: 920, height: 780)
        .windowResizability(.contentMinSize)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear  { appModel.immersiveSpaceState = .open }
                .onDisappear { appModel.immersiveSpaceState = .closed }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
#endif
