// iPadOS/IPadChatPanelView.swift
// Mesquette — iOS / iPadOS only

#if os(iOS)
import SwiftUI
import PhotosUI
import os

/// Right-hand chat panel for iPad: history of prompts + parameter controls + input bar.
struct IPadChatPanelView: View {
    @Bindable var appModel: AppModel
    let onGenerate: () -> Void
    var onGenerateSet: (() -> Void)? = nil

    @State private var showParameters = false
    @State private var selectedItem: PhotosPickerItem? = nil

    private var photoPickerTitle: String {
        appModel.inputImage == nil ? "Choose a photo" : "Change photo"
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ─────────────────────────────────────────────────
            HStack {
                Image(systemName: "cube.transparent.fill")
                    .foregroundStyle(.secondary)
                Text(AppIdentity.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                AboutMesquetteButton(font: .body)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background.secondary)

            Divider()

            // ── History (chat feed) ────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if appModel.generationHistory.isEmpty {
                            Text("Describe a 3D model to generate it.")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }
                        ForEach(appModel.generationHistory) { record in
                            ChatBubbleView(record: record)
                                .id(record.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: appModel.generationOrder.count) {
                    if let lastID = appModel.generationOrder.last {
                        withAnimation {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)

            Divider()

            // ── Parameter toggle ───────────────────────────────────────
            DisclosureGroup(isExpanded: $showParameters) {
                IOSParameterControlsView(appModel: appModel)
                    .padding(.top, 8)
            } label: {
                Label("Parameters", systemImage: "slider.horizontal.3")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // ── Input mode tabs ────────────────────────────────────────
            Picker("Input Mode", selection: $appModel.inputMode) {
                Text("Text to 3D").tag(AppModel.InputMode.text)
                Text("Image to 3D").tag(AppModel.InputMode.image)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .disabled(appModel.isGenerating)

            if appModel.inputMode == .text {
                PromptPresetPickerView(appModel: appModel, style: .compact)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                DirectorCompileBar(appModel: appModel, style: .compact)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                DirectorResultCard(appModel: appModel, onGenerateSet: onGenerateSet)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .frame(maxHeight: 220)
                    .clipped()
            }

            // ── Input bar ──────────────────────────────────────────────
            HStack(alignment: .bottom, spacing: 10) {
                if appModel.inputMode == .text {
                    TextField(
                        "Describe a 3D model…",
                        text: $appModel.prompt,
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .disabled(appModel.isDirectorBusy)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        .fill.quaternary,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .onSubmit {
                        guard !appModel.prompt
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty,
                              !appModel.isGenerating else { return }
                        onGenerate()
                    }
                } else {
                    let title = photoPickerTitle
                    HStack(spacing: 10) {
                        if let img = appModel.inputImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .onTapGesture(count: 2) {
                                    appModel.showImagePreview = true
                                }
                                .popover(
                                    isPresented: $appModel.showImagePreview
                                ) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 300, height: 300)
                                        .padding()
                                }
                        } else if appModel.isProcessingImage {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 36, height: 36)
                        }

                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Text(title)
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(appModel.isGenerating || appModel.isProcessingImage)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .background(
                        .fill.quaternary,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                }

                if appModel.isGenerating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.regular)
                        .frame(width: 36, height: 36)
                        .accessibilityLabel("Generating, \(Int(appModel.progress * 100)) percent")
                } else {
                    let isInputValid = !appModel.isDirectorBusy && (appModel.inputMode == .text ? !appModel.prompt.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty : appModel.inputImage != nil)
                    Button(action: onGenerate) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 36))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(
                                isInputValid ? Color.accentColor : Color.secondary.opacity(0.45)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isInputValid)
                    .accessibilityLabel("Generate 3D model")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.background.secondary)
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            appModel.isProcessingImage = true
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let rawImage = UIImage(data: data) {
                    var finalImg = rawImage
                    if let cgImage = rawImage.cgImage {
                        do {
                            if let stripped = try await ImageBackgroundRemoval.removeBackground(from: cgImage) {
                                finalImg = UIImage(cgImage: stripped)
                            } else {
                                Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.visionarydevops.Mesquette", category: "image").error("Vision succeeded but returned nil mask.")
                            }
                        } catch {
                            Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.visionarydevops.Mesquette", category: "image").error("Background removal failed: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                    await MainActor.run {
                        appModel.inputImage = finalImg
                        appModel.isProcessingImage = false
                    }
                } else {
                    await MainActor.run {
                        appModel.isProcessingImage = false
                    }
                }
            }
        }
    }
}

// MARK: - Chat bubble

struct ChatBubbleView: View {
    let record: GenerationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // User prompt (right-aligned bubble)
            HStack {
                Spacer()
                Text(record.prompt)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Color.accentColor.opacity(0.15),
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
            }

            // Status response (left-aligned)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.caption)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let params = record.params, case .completed = record.status {
                        Text("seed \(params.seed) · grid \(params.gridSize) · \(params.numInferenceSteps) steps")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if case .completed = record.status, record.latestMesh != nil {
                    ExportMeshButton(record: record)
                }

                Text(record.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var statusIcon: String {
        switch record.status {
        case .generating: return "progress.indicator"
        case .completed:  return "checkmark.circle.fill"
        case .failed:     return "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch record.status {
        case .generating: return Color.secondary
        case .completed:  return Color.green
        case .failed:     return Color.red
        }
    }

    private var statusText: String {
        switch record.status {
        case .generating:       return "Generating…"
        case .completed:        return "Model ready in scene"
        case .failed(let msg):  return "Failed: \(msg)"
        }
    }
}

// MARK: - Parameter controls (iPadOS)

struct IOSParameterControlsView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Quality").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $appModel.qualityPreset) {
                    ForEach(QualityPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }

            paramRow("Guidance Scale", value: $appModel.guidanceScale, in: 1...30,
                     format: "%.1f")
            paramRow(
                "Inference Steps",
                value: Binding(
                    get: { Double(appModel.numInferenceSteps) },
                    set: { appModel.numInferenceSteps = Int($0.rounded()) }
                ),
                in: 4...256,
                format: "%.0f"
            )

            HStack {
                Text("Grid Size").font(.caption).foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(appModel.gridSize) },
                        set: { appModel.gridSize = max(32, min(512, Int($0.rounded()))) }
                    ),
                    in: 32...512
                )
                Text("\(appModel.gridSize)")
                    .font(.caption.monospacedDigit())
                    .frame(width: 36, alignment: .trailing)
            }

            HStack {
                Text("Batch Size").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $appModel.batchSize) {
                    ForEach([1, 2, 4], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            HStack {
                Text("Seed").font(.caption).foregroundStyle(.secondary)
                Spacer()
                TextField("", value: $appModel.seed, format: .number)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                Button("Random") { appModel.seed = Int.random(in: 0...999_999) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            
            HStack {
                Text("GPU final extract").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: $appModel.usesGPU)
                    .labelsHidden()
            }

            HStack {
                Text("Live partials").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: $appModel.enableLivePartials)
                    .labelsHidden()
            }
        }
        .disabled(appModel.isGenerating)
    }

    private func paramRow(_ label: String, value: Binding<Double>,
                          in range: ClosedRange<Double>, format: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue))
                .font(.caption.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
    }
}
#endif
