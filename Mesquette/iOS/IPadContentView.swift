// iPadOS/IPadContentView.swift
// Mesquette — iOS / iPadOS only

#if os(iOS)
import SwiftUI
import UIKit

/// Root iOS layout. Regular width keeps the iPad split; compact width uses a
/// phone canvas (full-width scene + bottom composer) so the inspector cannot
/// clip the prompt field or starve the 3D view.
struct IPadContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel     = ContentViewModel()
    @State private var isSceneLocked = false
    @State private var dragVertical  = false   // false = XZ plane, true = Y axis
    @State private var resetTrigger  = 0
    @State private var isInspectorVisible = true

    var body: some View {
        @Bindable var model = appModel

        Group {
            if shouldUseSplitLayout {
                iPadSplitLayout(model: model)
            } else {
                IPhoneContentView(
                    viewModel: viewModel,
                    isSceneLocked: $isSceneLocked,
                    dragVertical: $dragVertical,
                    resetTrigger: $resetTrigger
                )
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                viewModel.cancelInFlightGeneration()
            }
        }
    }

    /// Never send an iPhone through the fixed-width iPad inspector, even if
    /// a future display mode reports a regular horizontal size class.
    private var shouldUseSplitLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
            && horizontalSizeClass == .regular
    }

    // MARK: - iPad / regular-width split

    private func iPadSplitLayout(model: AppModel) -> some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                IPad3DPreviewView(
                    records:       model.generationHistory,
                    isLocked:      isSceneLocked,
                    dragVertical:  dragVertical,
                    resetTrigger:  resetTrigger,
                    shadingMode:   model.shadingMode
                )
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)

                IOSViewportToolbar(
                    isSceneLocked: $isSceneLocked,
                    dragVertical: $dragVertical,
                    resetTrigger: $resetTrigger,
                    isInspectorVisible: $isInspectorVisible
                )

                if model.isGenerating {
                    IOSGeneratingOverlay(
                        progress: model.progress,
                        phaseLabel: model.progressPhaseLabel
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topLeading)
                }
            }

            if isInspectorVisible {
                Divider()

                IPadChatPanelView(appModel: model) {
                    viewModel.generateMesh(appModel: model)
                } onGenerateSet: {
                    viewModel.generateMeshSet(appModel: model)
                }
                .frame(width: 340)
                .background(.background)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isInspectorVisible)
        .background(.background)
        .edgesIgnoringSafeArea(.bottom)
    }
}

// MARK: - Shared viewport chrome

struct IOSViewportToolbar: View {
    @Environment(AppModel.self) private var appModel
    @Binding var isSceneLocked: Bool
    @Binding var dragVertical: Bool
    @Binding var resetTrigger: Int
    var isInspectorVisible: Binding<Bool>? = nil
    var usesCapsuleChrome: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            ToolbarIconButton(
                icon: isSceneLocked ? "lock.fill" : "lock.open",
                isActive: isSceneLocked,
                help: isSceneLocked
                    ? "Camera locked — drag to move · two-finger drag to rotate"
                    : "Lock camera to move and rotate models"
            ) {
                isSceneLocked.toggle()
            }
            .accessibilityLabel(isSceneLocked ? "Unlock camera" : "Lock camera")

            if isSceneLocked {
                ToolbarSegment(
                    options: [
                        ("arrow.left.and.right", "Move along floor (XZ)"),
                        ("arrow.up.and.down",    "Lift / lower (Y axis)")
                    ],
                    selectedIndex: dragVertical ? 1 : 0
                ) { idx in
                    dragVertical = (idx == 1)
                }
            }

            ToolbarIconButton(
                icon: "scope",
                isActive: false,
                help: "Teleport camera back to the centre of the scene"
            ) {
                resetTrigger += 1
            }
            .accessibilityLabel("Reset camera")

            ToolbarSegment(
                options: [
                    ("cube.fill", "Smooth Phong shading"),
                    ("diamond.fill", "Flat faceted shading"),
                    ("cube.transparent", "Wireframe mesh")
                ],
                selectedIndex: appModel.shadingModeIndex
            ) { idx in
                appModel.shadingMode = AppModel.ShadingMode.allCases[idx]
            }

            if let isInspectorVisible {
                ToolbarIconButton(
                    icon: isInspectorVisible.wrappedValue
                        ? "rectangle.split.1x2"
                        : "rectangle.righthalf.inset.filled",
                    isActive: !isInspectorVisible.wrappedValue,
                    help: isInspectorVisible.wrappedValue
                        ? "Hide create panel for a full-canvas preview"
                        : "Show create panel"
                ) {
                    isInspectorVisible.wrappedValue.toggle()
                }
                .accessibilityLabel(isInspectorVisible.wrappedValue
                                    ? "Hide create panel"
                                    : "Show create panel")
            }
        }
        .padding(usesCapsuleChrome ? 8 : 10)
        .background {
            if usesCapsuleChrome {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isSceneLocked)
    }
}

struct IOSGeneratingOverlay: View {
    let progress: Double
    let phaseLabel: String

    var body: some View {
        VStack(spacing: 6) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 160)
            Text(phaseLabel.isEmpty
                 ? "Generating… \(Int(progress * 100))%"
                 : "\(phaseLabel) · \(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Small reusable toolbar components

struct ToolbarIconButton: View {
    let icon: String
    let isActive: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive
                              ? AnyShapeStyle(.thinMaterial)
                              : AnyShapeStyle(.regularMaterial))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isActive ? Color.accentColor.opacity(0.6) : .clear,
                                      lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityHint(help)
    }
}

struct ToolbarSegment: View {
    let options: [(icon: String, help: String)]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                Button {
                    onSelect(i)
                } label: {
                    Image(systemName: options[i].icon)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedIndex == i
                                      ? AnyShapeStyle(Color.accentColor.opacity(0.25))
                                      : AnyShapeStyle(.regularMaterial))
                        )
                }
                .buttonStyle(.plain)
                .help(options[i].help)
                .accessibilityLabel(options[i].help)
                .accessibilityAddTraits(selectedIndex == i ? .isSelected : [])
            }
        }
        .padding(2)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
#endif
