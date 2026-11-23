//
//  MesquetteApp+iOS.swift
//  Mesquette
//

#if os(iOS)
import SwiftUI
import ShapERuntime

@main
struct MesquetteApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            AppLaunchView {
                IPadContentView()
                    .environment(appModel)
            }
        }
    }
}
#endif
