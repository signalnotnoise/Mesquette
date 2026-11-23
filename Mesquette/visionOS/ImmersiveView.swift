//
//  ImmersiveView.swift
//  Mesquette
//
//  Created by Alexander Otero on 4/13/26.
//

#if os(visionOS)
import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @State private var viewModel = ImmersiveViewModel()

    @State private var rootEntity = Entity()

    var body: some View {
        RealityView { content in
            // Load static RealityKit content bundle (skybox / environment).
            if let immersiveContentEntity = try? await Entity(
                named: "Immersive", in: realityKitContentBundle
            ) {
                content.add(immersiveContentEntity)
            }
            
            // Add our managed root entity for generations
            content.add(rootEntity)
            ImmersiveStudio.install(in: rootEntity)
            
            // Initial sync if any existing models
            Task {
                await viewModel.sync(with: appModel, rootEntity: rootEntity)
            }
        } update: { content in
            // Read properties to register SwiftUI observation dependencies
            _ = appModel.generationHistory
            _ = appModel.progress
            
            // Trigger sync whenever generation history updates (or partial meshes arrive)
            // RealityView update block is called synchronously, but we dispatch an async task.
            Task {
                await viewModel.sync(with: appModel, rootEntity: rootEntity)
            }
        }
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let parent = value.entity.parent else { return }
                    value.entity.position = value.convert(
                        value.location3D, from: .local, to: parent
                    )
                }
        )
        .gesture(
            RotateGesture3D()
                .targetedToAnyEntity()
                .onChanged { value in
                    if viewModel.initialOrientation == nil {
                        viewModel.initialOrientation = value.entity.transform.rotation
                    }
                    if let initial = viewModel.initialOrientation {
                        value.entity.transform.rotation = initial * simd_quatf(value.rotation)
                    }
                }
                .onEnded { _ in
                    viewModel.initialOrientation = nil
                }
        )
        .gesture(
            MagnifyGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    if viewModel.initialScale == nil {
                        viewModel.initialScale = value.entity.transform.scale
                    }
                    if let initial = viewModel.initialScale {
                        value.entity.transform.scale = initial * Float(value.magnification)
                    }
                }
                .onEnded { _ in
                    viewModel.initialScale = nil
                }
        )
    }
}

// MARK: - GeneratedEntityTag

/// Lightweight component that marks an entity as user-generated and lets
/// the update closure detect duplicates without a @State reference.
struct GeneratedEntityTag: Component {
    let entityID: ObjectIdentifier
    var isFinal: Bool = false
}

// MARK: - Preview

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
#endif
