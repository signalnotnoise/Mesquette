// macOS/MacChatPanelView.swift
// Mesquette — macOS create panel (prompt → generate → history)

#if os(macOS)
import SwiftUI
import AppKit
import MLX3DRuntime
import UniformTypeIdentifiers
import os

/// Right-hand panel optimized for a clear macOS create workflow:
/// 1) Choose Text / Image  2) Set quality  3) Describe / pick idea  4) Generate
/// History is optional (viewport clock button / View → Show History) so it never
/// buries the prompt. Advanced settings stay at the bottom.
struct MacChatPanelView: View {
    @Bindable var appModel: AppModel
    @Binding var isHistoryVisible: Bool
    let onGenerate: () -> Void
    var onGenerateSet: () -> Void = {}
    var onRetryPin: (UUID) -> Void = { _ in }
    var onStop: () -> Void = {}

    @State private var showAdvanced = false
    @State private var showPresetsSheet = false

    private var canGenerate: Bool {
        guard !appModel.isDirectorBusy else { return false }
        switch appModel.inputMode {
        case .text:
            let hasPrompt = !appModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if appModel.usesPlacementPins {
                return hasPrompt && !appModel.emptyPlacementPins.isEmpty
            }
            return hasPrompt
        case .image:
            return appModel.inputImage != nil && !appModel.isProcessingImage
        }
    }

    var body: some View {
        // Header + Advanced stay intrinsic. Create fills the middle. History is
        // off by default (viewport clock button / View menu) so it cannot steal
        // the prompt. When shown, Create gets a firm height and History the rest.
        VStack(spacing: 0) {
            header

            if isHistoryVisible {
                GeometryReader { geo in
                    let createH = createPaneHeight(middle: geo.size.height)
                    VStack(spacing: 0) {
                        createScroller
                            .frame(height: createH)

                        Divider()

                        historySection
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
            } else {
                createScroller
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            advancedSection
                .padding(16)
        }
        .frame(minWidth: 320)
        .clipped()
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showPresetsSheet) {
            MacPresetBrowserSheet(appModel: appModel) {
                showPresetsSheet = false
            }
            .frame(minWidth: 520, minHeight: 440)
        }
    }

    private var createScroller: some View {
        ScrollView {
            createSection
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
        .scrollIndicators(.visible)
    }

    /// Firm pixel height for Create when History is on. Always leaves History a floor.
    private func createPaneHeight(middle: CGFloat) -> CGFloat {
        let h = max(middle, 200)
        let historyFloor: CGFloat = 110
        let createFloor: CGFloat = 280
        let createCap: CGFloat = 520
        let proposed = h * 0.62
        return min(max(proposed, createFloor), max(h - historyFloor, 160), createCap)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "cube.transparent.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(AppIdentity.name)
                    .font(.headline)
                Text("Text or image → 3D mesh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AboutMesquetteButton(font: .body)
            if appModel.isGenerating {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Create (primary)

    private var createSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Create")

            // Model backend — TripoSR is image-to-3D only; text/pin scenes run on Shap-E.
            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.subheadline.weight(.medium))
                Picker("Model", selection: $appModel.generationModel) {
                    Text("Shap-E").tag(MLX3DBackend.shapE)
                    Text("TripoSR").tag(MLX3DBackend.tripoSR)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(appModel.isGenerating)
                .help("Shap-E: text or image. TripoSR: image only, cleaner geometry.")
                if appModel.generationModel == .tripoSR {
                    Text("TripoSR converts one image to a mesh. For text prompts and pin scenes, switch to Shap-E.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Mode
            Picker("Input", selection: $appModel.inputMode) {
                Label("Text", systemImage: "text.alignleft")
                    .tag(AppModel.InputMode.text)
                Label("Image", systemImage: "photo")
                    .tag(AppModel.InputMode.image)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(appModel.isGenerating || appModel.generationModel == .tripoSR)
            .help(appModel.generationModel == .tripoSR
                  ? "TripoSR is image-to-3D only"
                  : "Text describes a model; Image converts a photo to 3D")

            // Quality — always visible (most-used control)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Quality")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(appModel.qualityPreset.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Picker("Quality", selection: $appModel.qualityPreset) {
                    ForEach(QualityPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(appModel.isGenerating || appModel.generationModel == .tripoSR)
                .help(appModel.generationModel == .tripoSR
                      ? "TripoSR uses its own fixed extraction settings"
                      : "Preview is fast; High is finer and slower")
            }

            // Prompt / image input
            Group {
                if appModel.inputMode == .text {
                    textPromptEditor
                } else {
                    imageDropCard
                }
            }

            // Progress while generating
            if appModel.isGenerating {
                generatingCard
            }

            // Primary action
            Button(action: {
                if appModel.isGenerating {
                    onStop()
                } else {
                    onGenerate()
                }
            }) {
                HStack {
                    if appModel.isGenerating {
                        ProgressView()
                            .controlSize(.small)
                        Text("Stop")
                    } else {
                        Image(systemName: "sparkles")
                        Text(appModel.usesPlacementPins && appModel.generationModel == .shapE
                             ? "Generate \(appModel.emptyPlacementPins.count) empty pin\(appModel.emptyPlacementPins.count == 1 ? "" : "s")"
                             : "Generate 3D Model")
                    }
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appModel.isGenerating ? false : !canGenerate)
            .keyboardShortcut(.return, modifiers: .command)
            .help(appModel.isGenerating
                  ? "Stop this run. Empty pins stay empty."
                  : (canGenerate
                     ? (appModel.usesPlacementPins
                        ? "Fill empty pins only. Filled pins keep their mesh. (⌘↩)"
                        : "Generate mesh (⌘↩)")
                     : (appModel.inputMode == .text
                        ? (appModel.usesPlacementPins && appModel.emptyPlacementPins.isEmpty
                           ? "All pins have objects. Drop more, or double-click a pin to retry."
                           : "Enter a description or pick an idea first")
                        : "Select an image first")))

            if appModel.inputMode == .text, !appModel.usesPlacementPins {
                DirectorCompileBar(appModel: appModel, style: .regular)
                DirectorResultCard(appModel: appModel) {
                    onGenerateSet()
                }
                Text("Tip: Invent writes a scene brief. Compile splits it into objects, then Generate as set. Or drop pins and generate without compile.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if appModel.usesPlacementPins {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fills empty pins only (max \(PlacementPin.maxCount)). Double-click a filled pin to retry that object. No compile.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    extraPropsSlider
                    if let note = appModel.pinPlanNote, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var extraPropsSlider: some View {
        let cap = appModel.extraPropsCapacity
        let value = min(appModel.pinExtrasBudget, cap)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Extra props")
                    .font(.caption.weight(.medium))
                Spacer()
                Text(cap == 0 ? "No leftover pins" : "\(value) of \(cap) leftover")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(min(appModel.pinExtrasBudget, max(cap, 0))) },
                    set: { appModel.pinExtrasBudget = Int($0.rounded()) }
                ),
                in: 0...Double(max(cap, 1)),
                step: 1
            )
            .disabled(appModel.isDirectorBusy || cap == 0)
            .help("Named objects always generate. Extra props fill leftover pins only — 0 leaves them empty.")
        }
    }

    private var textPromptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Description")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    showPresetsSheet = true
                } label: {
                    Label("Browse ideas", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appModel.isGenerating)
                .help("Open a library of ready-made prompts")
            }

            TextEditor(text: $appModel.prompt)
                .font(.body)
                .frame(minHeight: 96, maxHeight: 180)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .disabled(appModel.isDirectorBusy)
                .overlay(alignment: .topLeading) {
                    if appModel.prompt.isEmpty {
                        Text("A blue sports car, a wooden chair, a small robot…")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

            if !appModel.prompt.isEmpty {
                HStack {
                    Text("\(appModel.prompt.count) characters")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Clear") {
                        appModel.prompt = ""
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(appModel.isGenerating)
                }
            }
        }
    }

    private var imageDropCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Source image")
                .font(.subheadline.weight(.medium))

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .frame(width: 88, height: 88)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundStyle(.tertiary)
                        )

                    if let img = appModel.inputImage {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .onTapGesture(count: 2) {
                                appModel.showImagePreview = true
                            }
                            .popover(isPresented: $appModel.showImagePreview) {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(minWidth: 320, minHeight: 320)
                                    .padding()
                            }
                    } else if appModel.isProcessingImage {
                        ProgressView()
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(appModel.inputImage == nil
                         ? "Choose a photo of a single object on a simple background."
                         : "Background removal runs automatically when possible.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button(appModel.inputImage == nil ? "Choose Image…" : "Replace…") {
                            pickImage()
                        }
                        .buttonStyle(.bordered)
                        .disabled(appModel.isGenerating || appModel.isProcessingImage)

                        if appModel.inputImage != nil {
                            Button("Remove", role: .destructive) {
                                appModel.inputImage = nil
                            }
                            .buttonStyle(.borderless)
                            .disabled(appModel.isGenerating)
                        }
                    }
                }
            }
        }
    }

    private var generatingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: appModel.progress)
                .progressViewStyle(.linear)
            HStack {
                Text(appModel.progressPhaseLabel.isEmpty
                     ? "Working…"
                     : appModel.progressPhaseLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(appModel.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("History")
                Spacer()
                if !appModel.generationHistory.isEmpty {
                    Text("\(appModel.generationHistory.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }

            if appModel.generationHistory.isEmpty {
                emptyHistory
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Own scroller — list grows inside this region only, never over Create.
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(appModel.generationHistory.reversed()) { record in
                                MacHistoryCard(
                                    record: record,
                                    onReuse: {
                                        appModel.inputMode = .text
                                        appModel.prompt = record.prompt
                                        if let params = record.params {
                                            appModel.seed = params.seed
                                        }
                                    },
                                    onRetry: {
                                        guard let pinID = record.pinID,
                                              appModel.placementPins.contains(where: { $0.id == pinID })
                                        else { return nil }
                                        return { onRetryPin(pinID) }
                                    }()
                                )
                                .id(record.id)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    .scrollIndicators(.visible)
                    .onChange(of: appModel.generationOrder.count) {
                        if let lastID = appModel.generationOrder.last {
                            withAnimation {
                                proxy.scrollTo(lastID, anchor: .top)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
            }
        }
        .frame(minHeight: 120)
        .clipped()
    }

    private var emptyHistory: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No models yet")
                .font(.subheadline.weight(.medium))
            Text("Generate something above — finished meshes show up here for export and reuse.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            ScrollView {
                MacParameterControlsView(appModel: appModel)
                    .padding(.top, 10)
                    .padding(.trailing, 4)
            }
            .frame(maxHeight: 240)
        } label: {
            Label("Advanced settings", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.medium))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Helpers

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.4)
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "Choose a photo of a single object"
        panel.prompt = "Use Image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let rawImage = NSImage(contentsOf: url) else { return }

        appModel.isProcessingImage = true
        Task {
            var finalImg = rawImage
            if let cgImage = rawImage.cgImage(
                forProposedRect: nil, context: nil, hints: nil
            ) {
                do {
                    if let stripped = try await ImageBackgroundRemoval.removeBackground(from: cgImage) {
                        finalImg = NSImage(
                            cgImage: stripped,
                            size: NSSize(width: stripped.width, height: stripped.height)
                        )
                    }
                } catch {
                    Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.visionarydevops.Mesquette", category: "image").error("Background removal failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            await MainActor.run {
                appModel.inputImage = finalImg
                appModel.isProcessingImage = false
            }
        }
    }
}

// MARK: - History card

private struct MacHistoryCard: View {
    let record: GenerationRecord
    let onReuse: () -> Void
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                statusDot
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.prompt)
                        .font(.callout)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let params = record.params {
                        Text("seed \(params.seed) · grid \(params.gridSize) · \(params.numInferenceSteps) steps")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(record.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if case .completed = record.status {
                HStack(spacing: 8) {
                    if record.latestMesh != nil {
                        ExportMeshButton(record: record)
                    }
                    Button {
                        onReuse()
                    } label: {
                        Label("Reuse prompt", systemImage: "arrow.uturn.backward")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy this prompt back into the create field")
                    if let onRetry {
                        Button(action: onRetry) {
                            Label("Retry pin", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Throw away this mesh and generate the same prompt with a new seed")
                    }
                    Spacer()
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var statusDot: some View {
        Image(systemName: statusIcon)
            .font(.caption)
            .foregroundStyle(statusColor)
            .frame(width: 16)
            .padding(.top, 2)
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
        case .generating: return .secondary
        case .completed:  return .green
        case .failed:     return .red
        }
    }

    private var statusLine: String {
        switch record.status {
        case .generating:      return "Generating…"
        case .completed:       return "Ready in viewport · export available"
        case .failed(let msg): return "Failed: \(msg)"
        }
    }
}

// MARK: - Preset browser sheet

private struct MacPresetBrowserSheet: View {
    @Bindable var appModel: AppModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prompt ideas")
                        .font(.title2.weight(.semibold))
                    Text("Tap an idea, or Invent one with Apple Intelligence, then generate.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            PromptPresetPickerView(appModel: appModel, style: .expanded)
                .padding(20)

            Divider()

            HStack {
                if !appModel.prompt.isEmpty {
                    Text(appModel.prompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Use & Close") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
    }
}

// MARK: - Advanced parameter controls

private struct MacParameterControlsView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fine-tune steps, grid, seed, and GPU. Quality presets above already set sensible defaults.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            labeledSlider(
                "Guidance",
                help: "How strongly the model follows the prompt",
                value: $appModel.guidanceScale,
                in: 1...30,
                format: "%.1f"
            )

            labeledSlider(
                "Steps",
                help: "More steps = slower, often slightly cleaner",
                value: Binding(
                    get: { Double(appModel.numInferenceSteps) },
                    set: { appModel.numInferenceSteps = Int($0.rounded()) }
                ),
                in: 4...256,
                format: "%.0f"
            )

            labeledSlider(
                "Grid",
                help: "Voxel resolution for marching cubes (32–512)",
                value: Binding(
                    get: { Double(appModel.gridSize) },
                    set: { appModel.gridSize = max(32, min(512, Int($0.rounded()))) }
                ),
                in: 32...512,
                format: "%.0f"
            )

            HStack {
                Text("Variations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                Picker("", selection: $appModel.batchSize) {
                    ForEach([1, 2, 4], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .help("How many meshes to generate at once")
            }

            HStack {
                Text("Seed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                TextField("Seed", value: $appModel.seed, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                Button("Random") {
                    appModel.seed = Int.random(in: 0...999_999)
                }
                .controlSize(.small)
                .help("Base seed. Batch variations use seed, seed+1, seed+2…")
                Spacer()
            }
            if appModel.batchSize > 1 {
                Text("Batch of \(appModel.batchSize): seeds \(appModel.seed)…\(appModel.seed + appModel.batchSize - 1)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Toggle(isOn: $appModel.usesGPU) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("GPU final extract")
                        .font(.caption)
                    Text("Metal marching cubes for the finished mesh only")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle(isOn: $appModel.enableLivePartials) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Live partials")
                        .font(.caption)
                    Text("Preview during sampling — slower, higher GPU risk")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Button("Reset advanced to Standard defaults") {
                appModel.resetGenerationParameters()
            }
            .controlSize(.small)
        }
        .disabled(appModel.isGenerating)
    }

    private func labeledSlider(
        _ title: String,
        help: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        format: String
    ) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
                .help(help)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue))
                .font(.caption.monospacedDigit())
                .frame(width: 40, alignment: .trailing)
        }
    }
}
#endif
