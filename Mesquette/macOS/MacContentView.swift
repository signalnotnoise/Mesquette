// macOS/MacContentView.swift
// Mesquette — macOS only

#if os(macOS)
import MLX3DRuntime
import SwiftUI

/// Root macOS layout: 3-D SceneKit preview (left) + chat panel (right).
struct MacContentView: View {
    @Environment(AppModel.self) private var appModel
    @State private var viewModel     = ContentViewModel()
    @State private var isSceneLocked = false
    @State private var dragVertical  = false   // false = XZ plane, true = Y axis
    @State private var resetTrigger  = 0
    @State private var cameraView: StudioCameraRig.View = .orbit
    @State private var isInspectorVisible = true
    @State private var isPinning = false
    @AppStorage("mesquette.showGenerationHistory") private var isHistoryVisible = false

    var body: some View {
        @Bindable var model = appModel

        HSplitView {
            // ── Left: 3D viewport ──────────────────────────────────────
            ZStack(alignment: .topTrailing) {
                Mac3DPreviewView(
                    records:       model.generationHistory,
                    isLocked:      isSceneLocked,
                    dragVertical:  dragVertical,
                    resetTrigger:  resetTrigger,
                    cameraView:    cameraView,
                    pins:          model.placementPins,
                    isPinning:     isPinning,
                    onDropPin: { x, y, z in
                        model.addPlacementPin(x: x, y: y, z: z)
                    },
                    onRemovePin: { id in
                        model.removePlacementPin(id: id)
                    },
                    onMovePin: { id, x, y, z in
                        model.movePlacementPin(id: id, x: x, y: y, z: z)
                    },
                    onRetryPin: { id in
                        viewModel.retryPin(id: id, appModel: model)
                    },
                    shadingMode:   model.shadingMode
                )
                .frame(minWidth: 420, maxWidth: .infinity, minHeight: 500)
                .layoutPriority(1)
                .overlay(alignment: .bottomLeading) {
                    if isPinning || !model.placementPins.isEmpty {
                        pinStatus.padding(12)
                    } else if cameraView == .walk {
                        walkHint.padding(12)
                    }
                }

                // Viewport toolbar — stay inside the 3D pane, above the splitter.
                viewportToolbar
                    .zIndex(2)

                // Generation progress overlay
                if model.isGenerating {
                    generatingOverlay
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .topLeading)
                }
            }

            if isInspectorVisible {
                MacChatPanelView(
                    appModel: model,
                    isHistoryVisible: $isHistoryVisible
                ) {
                    if model.usesPlacementPins && model.generationModel == .shapE {
                        viewModel.generateAtPins(appModel: model)
                    } else {
                        viewModel.generateMesh(appModel: model)
                    }
                } onGenerateSet: {
                    if model.usesPlacementPins && model.generationModel == .shapE {
                        viewModel.generateAtPins(appModel: model)
                    } else {
                        viewModel.generateMeshSet(appModel: model)
                    }
                } onRetryPin: { id in
                    viewModel.retryPin(id: id, appModel: model)
                } onStop: {
                    viewModel.cancelInFlightGeneration()
                }
                .frame(minWidth: 320, idealWidth: 380, maxWidth: 420)
                .clipped()
                .background(.background)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isInspectorVisible)
        .animation(.easeInOut(duration: 0.2), value: isHistoryVisible)
        .onChange(of: isHistoryVisible) { _, visible in
            if visible { isInspectorVisible = true }
        }
        .frame(minWidth: isInspectorVisible ? 900 : 560, minHeight: 560)
        // Fullscreen-capable window + double-click top chrome → toggle fullscreen.
        .background(MacWindowFullscreenSupport())
    }

    // MARK: - Viewport toolbar

    private var viewportToolbar: some View {
        HStack(spacing: 6) {

            ToolbarSegment(
                options: [
                    ("rotate.3d", "Orbit — drag to tumble, scroll to zoom, Shift-drag to pan. Drag up to look down on the table."),
                    ("arrow.down.to.line.compact", "Top — look down from above. Drag still orbits."),
                    ("figure.walk", "Walk — first-person. Drag to look, WASD to move, Q/E up and down, scroll to go forward.")
                ],
                selectedIndex: StudioCameraRig.View.allCases.firstIndex(of: cameraView) ?? 0
            ) { idx in
                cameraView = StudioCameraRig.View.allCases[idx]
                if cameraView == .walk { isSceneLocked = false }
            }

            // Lock / Unlock camera
            ToolbarIconButton(
                icon: isSceneLocked ? "lock.fill" : "lock.open",
                isActive: isSceneLocked,
                help: isSceneLocked
                    ? "Camera locked — left-drag to move · right-drag to rotate"
                    : "Lock camera to move and rotate models"
            ) {
                isSceneLocked.toggle()
            }

            // Drag-axis toggle (only meaningful when locked)
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

            // Teleport to centre
            ToolbarIconButton(
                icon: "scope",
                isActive: false,
                help: "Frame the scene in the current view"
            ) {
                resetTrigger += 1
            }

            ToolbarIconButton(
                icon: "mappin.and.ellipse",
                isActive: isPinning,
                help: isPinning
                    ? "Click empty space to drop a pin. Click an empty pin to remove it. Double-click a filled pin to retry that object."
                    : "Drop points — floor pins for mountains and props, lifted pins for birds, planes, and clouds"
            ) {
                isPinning.toggle()
                if isPinning { isSceneLocked = false }
            }

            ToolbarSegment(
                options: [
                    ("cube.fill", "Smooth Phong shading"),
                    ("diamond.fill", "Flat faceted shading — crisp low-poly edges"),
                    ("cube.transparent", "Wireframe mesh")
                ],
                selectedIndex: appModel.shadingModeIndex
            ) { idx in
                appModel.shadingMode = AppModel.ShadingMode.allCases[idx]
            }

            ToolbarIconButton(
                icon: "clock.arrow.circlepath",
                isActive: isHistoryVisible,
                help: isHistoryVisible
                    ? "Hide generation history"
                    : "Show generation history — export and reuse prompts",
                badge: isHistoryVisible ? nil : appModel.generationHistory.count
            ) {
                isHistoryVisible.toggle()
            }

            ToolbarIconButton(
                icon: isInspectorVisible
                    ? "sidebar.right"
                    : "sidebar.trailing",
                isActive: !isInspectorVisible,
                help: isInspectorVisible
                    ? "Hide create panel"
                    : "Show create panel"
            ) {
                isInspectorVisible.toggle()
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
        )
        .padding(.top, 12)
        .padding(.trailing, 12)
        .animation(.easeInOut(duration: 0.15), value: isSceneLocked)
        .animation(.easeInOut(duration: 0.15), value: isPinning)
        .animation(.easeInOut(duration: 0.15), value: cameraView)
    }

    private var pinStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse")
            if isPinning {
                Text("Click empty to drop or remove · double-click filled to retry · \(appModel.emptyPlacementPins.count) empty · \(appModel.placementPins.count)/\(PlacementPin.maxCount)")
            } else {
                Text("\(appModel.emptyPlacementPins.count) empty · \(appModel.placementPins.count) pin\(appModel.placementPins.count == 1 ? "" : "s") — double-click a teal pin to retry")
            }
            if !appModel.placementPins.isEmpty {
                Button("Clear") {
                    appModel.clearPlacementPins()
                }
                .buttonStyle(.borderless)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .animation(.easeInOut(duration: 0.15), value: isSceneLocked)
    }

    private var walkHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.walk")
            Text("Drag to look · WASD walk · Q/E up/down · scroll forward")
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Progress overlay

    private var generatingOverlay: some View {
        VStack(spacing: 6) {
            ProgressView(value: appModel.progress)
                .progressViewStyle(.linear)
                .frame(width: 160)
            Text(appModel.progressPhaseLabel.isEmpty
                 ? "Generating… \(Int(appModel.progress * 100))%"
                 : "\(appModel.progressPhaseLabel) · \(Int(appModel.progress * 100))%")
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 180, height: 32)
        }
        .padding(12)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .padding(16)
    }
}

// MARK: - Small reusable toolbar components

private struct ToolbarIconButton: View {
    let icon: String
    let isActive: Bool
    let help: String
    var badge: Int? = nil
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive
                              ? AnyShapeStyle(Color.accentColor.opacity(0.22))
                              : isHovered
                                ? AnyShapeStyle(.thinMaterial)
                                : AnyShapeStyle(.regularMaterial))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isActive ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08),
                                      lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if let badge, badge > 0 {
                        Text(badge > 9 ? "9+" : "\(badge)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(Color.accentColor, in: Capsule())
                            .offset(x: 5, y: -5)
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .scaleEffect(isHovered ? 1.06 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(help)
    }
}

private struct ToolbarSegment: View {
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
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedIndex == i
                                      ? AnyShapeStyle(Color.accentColor.opacity(0.25))
                                      : AnyShapeStyle(.regularMaterial))
                        )
                }
                .buttonStyle(.plain)
                .help(options[i].help)
            }
        }
        .padding(2)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
#endif
