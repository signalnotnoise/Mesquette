//
//  ContentView.swift
//  Mesquette
//
//  Created by Alexander Otero on 4/13/26.
//

#if os(visionOS)
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @State private var viewModel = ContentViewModel()
    @State private var showParameters = false
    @State private var showHistory = false

    var body: some View {
        @Bindable var model = appModel

        VStack(spacing: 22) {
            header

            PromptInputView(appModel: model)

            if model.inputMode == .text {
                directorSection
            }

            qualitySection

            generateSection

            Spacer(minLength: 12)

            ToggleImmersiveSpaceButton()
                .padding(.bottom, 20)
        }
        .animation(.easeInOut, value: model.isGenerating)
        .animation(.easeInOut, value: model.lastCompilation != nil)
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
        .frame(
            minWidth: 840,
            idealWidth: 920,
            maxWidth: 1100,
            minHeight: 720,
            idealHeight: 780,
            maxHeight: 1200
        )
        .sheet(isPresented: $showParameters) {
            ParameterSheet(appModel: model, isPresented: $showParameters)
        }
        .sheet(isPresented: $showHistory) {
            VisionHistoryView(appModel: model) {
                showHistory = false
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomOrnament) {
                Button {
                    showHistory = true
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .badge(model.generationHistory.count)
                .help("Export and reuse finished meshes")
                .hoverEffect(.highlight)

                Button {
                    showParameters = true
                } label: {
                    Label("Parameters", systemImage: "slider.horizontal.3")
                }
                .disabled(model.isGenerating)
                .hoverEffect(.highlight)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text(AppIdentity.name)
                    .font(.extraLargeTitle)
                    .fontWeight(.bold)
                    .tracking(1.2)
                AboutMesquetteButton(font: .title2)
            }

            Text("Invent or describe a scene, generate it, then look around. Meshes sit on the table in Immersive Space.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 720)
        }
        .padding(.top, 28)
        .padding(.horizontal, 24)
    }

    private var directorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DirectorCompileBar(appModel: appModel, style: .regular)
            // Generate as set is the large primary button below — keep the
            // card for layout, parts, and "Use first only".
            DirectorResultCard(appModel: appModel)
            .frame(maxHeight: 220)
            .clipped()

            Text("Invent writes a scene. Compile splits it into objects. Generate as set places them in space.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 48)
    }

    private var qualitySection: some View {
        @Bindable var model = appModel
        return VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Quality", systemImage: "speedometer")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(model.qualityPreset.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Picker("Quality", selection: $model.qualityPreset) {
                    ForEach(QualityPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.isGenerating)
                .frame(minHeight: 48)
            }

            Button {
                showParameters = true
            } label: {
                HStack(spacing: 12) {
                    Label("All Parameters", systemImage: "slider.horizontal.3")
                        .font(.headline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(parametersSummary(appModel))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            )
            .hoverEffect(.highlight)
            .disabled(appModel.isGenerating)
            .opacity(appModel.isGenerating ? 0.55 : 1)
            .accessibilityHint("Opens generation parameters including advanced options")
        }
        .padding(.horizontal, 48)
    }

    @ViewBuilder
    private var generateSection: some View {
        Group {
            if appModel.isGenerating {
                GenerationProgressView(appModel: appModel)
                    .transition(.opacity)
            } else if compiledSetReady {
                VStack(spacing: 12) {
                    Button {
                        generateSet()
                    } label: {
                        Text("Generate as set")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .hoverEffect(.highlight)
                    .disabled(appModel.isDirectorBusy)
                    .help("Generate each object and place it on the table in Immersive Space")

                    Button("This prompt only") {
                        generateSingle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .hoverEffect(.highlight)
                    .disabled(appModel.isDirectorBusy)
                    .help("Ignore the staged set and generate the description as one mesh")
                }
                .transition(.opacity)
            } else {
                GenerateButtonView(appModel: appModel) {
                    generateSingle()
                }
                .transition(.opacity)
            }
        }
        .padding(.top, 4)
    }

    private var compiledSetReady: Bool {
        guard let compiled = appModel.lastCompilation?.normalized() else { return false }
        return compiled.kind == .set && compiled.parts.count >= 2
    }

    // MARK: - Actions

    private func generateSingle() {
        Task {
            await openSpaceIfNeeded()
            viewModel.generateMesh(appModel: appModel)
        }
    }

    private func generateSet() {
        Task {
            await openSpaceIfNeeded()
            viewModel.generateMeshSet(appModel: appModel)
        }
    }

    private func openSpaceIfNeeded() async {
        guard appModel.immersiveSpaceState == .closed else { return }
        appModel.immersiveSpaceState = .inTransition
        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
        case .opened:
            break
        case .userCancelled, .error:
            fallthrough
        @unknown default:
            appModel.immersiveSpaceState = .closed
        }
    }

    private func parametersSummary(_ model: AppModel) -> String {
        "g \(String(format: "%.0f", model.guidanceScale)) · \(model.numInferenceSteps) steps · grid \(model.gridSize)"
    }
}

// MARK: - Parameter sheet

/// Dedicated scrollable sheet so seed / GPU / partials are always reachable.
private struct ParameterSheet: View {
    @Bindable var appModel: AppModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ParameterControlsView(appModel: appModel, style: .sheet)
                .navigationTitle("Parameters")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            isPresented = false
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 680, idealHeight: 760)
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
#endif
