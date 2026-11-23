// IPhoneContentView.swift
// Mesquette — compact-width iOS (iPhone, Slide Over, 1/3 Split View)

#if os(iOS)
import SwiftUI
import PhotosUI

/// Small-screen layout: the 3D canvas is the full screen (Maps / Find My).
/// Create lives in an in-window bottom panel that hugs the composer at peek, then
/// reveals ideas / history as you drag up — the prompt is never clipped.
struct IPhoneContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var viewModel: ContentViewModel
    @Binding var isSceneLocked: Bool
    @Binding var dragVertical: Bool
    @Binding var resetTrigger: Int

    @State private var panelLevel: PhonePanelLevel = .peek
    @State private var selectedItem: PhotosPickerItem?

    private var hasVisibleMesh: Bool {
        appModel.generationHistory.contains { $0.latestMesh != nil }
    }

    var body: some View {
        @Bindable var model = appModel

        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ZStack(alignment: .topTrailing) {
                    IPad3DPreviewView(
                        records: model.generationHistory,
                        isLocked: isSceneLocked,
                        dragVertical: dragVertical,
                        resetTrigger: resetTrigger,
                        shadingMode: model.shadingMode
                    )
                    .ignoresSafeArea()

                    if !hasVisibleMesh && !model.isGenerating {
                        IPhoneEmptyCanvasHint(appModel: model)
                            .padding(.bottom, PhonePanelMetrics.peekHeight + 168)
                            .padding(.top, 72)
                            .padding(.horizontal, 28)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    IOSViewportToolbar(
                        isSceneLocked: $isSceneLocked,
                        dragVertical: $dragVertical,
                        resetTrigger: $resetTrigger,
                        usesCapsuleChrome: true
                    )
                    .padding(.trailing, 14)
                    .safeAreaPadding(.top)

                    if model.isGenerating {
                        IOSGeneratingOverlay(
                            progress: model.progress,
                            phaseLabel: model.progressPhaseLabel
                        )
                        .safeAreaPadding(.top)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .topLeading)
                    }
                }

                IPhoneCreatePanel(
                    appModel: model,
                    level: $panelLevel,
                    selectedItem: $selectedItem,
                    onGenerate: { viewModel.generateMesh(appModel: model) },
                    onGenerateSet: { viewModel.generateMeshSet(appModel: model) }
                )
                .frame(height: PhonePanelMetrics.height(
                    for: panelLevel,
                    availableHeight: proxy.size.height,
                    isLandscape: verticalSizeClass == .compact
                ))
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 24,
                        topTrailingRadius: 24
                    )
                )
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(.secondary.opacity(0.55))
                        .frame(width: 40, height: 5)
                        .padding(.top, 7)
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(0.22), radius: 16, y: -4)
                .gesture(panelDragGesture)
                .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.86), value: panelLevel)
                .offset(y: proxy.safeAreaInsets.bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .onChange(of: selectedItem) { _, newItem in
            loadPickedImage(newItem)
        }
        .onChange(of: model.isGenerating) { _, generating in
            if generating {
                panelLevel = .peek
            }
        }
    }

    private var panelDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onEnded { value in
                let drag = value.translation.height
                let flick = value.predictedEndTranslation.height
                let primary = abs(flick) > abs(drag) * 1.15 ? flick : drag
                if primary < -44 {
                    panelLevel = panelLevel.expanded
                } else if primary > 44 {
                    panelLevel = panelLevel.collapsed
                }
            }
    }

    private func loadPickedImage(_ newItem: PhotosPickerItem?) {
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
                        }
                    } catch {
                        print("Background removal failed with error: \(error)")
                    }
                }
                appModel.inputImage = finalImg
                appModel.isProcessingImage = false
            } else {
                appModel.isProcessingImage = false
            }
        }
    }
}

private enum PhonePanelLevel: Int, Sendable {
    case peek
    case create
    case history

    var expanded: Self {
        Self(rawValue: min(rawValue + 1, Self.history.rawValue)) ?? self
    }

    var collapsed: Self {
        Self(rawValue: max(rawValue - 1, Self.peek.rawValue)) ?? self
    }
}

private enum PhonePanelMetrics {
    static let peekHeight: CGFloat = 142

    static func height(
        for level: PhonePanelLevel,
        availableHeight: CGFloat,
        isLandscape: Bool
    ) -> CGFloat {
        let peek = isLandscape ? 104.0 : peekHeight
        switch level {
        case .peek:
            return peek
        case .create:
            return min(max(peek, 360), availableHeight * 0.52)
        case .history:
            return max(peek, availableHeight - 12)
        }
    }
}

// MARK: - Empty canvas

private struct IPhoneEmptyCanvasHint: View {
    @Bindable var appModel: AppModel

    private var starterPresets: [PromptPreset] {
        Array(PromptPresetLibrary.presets(in: .animals).prefix(3))
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary)
            Text("Your 3D model will appear here")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Describe something below, or start from an idea.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                ForEach(starterPresets) { preset in
                    Button {
                        appModel.inputMode = .text
                        appModel.prompt = preset.prompt
                    } label: {
                        Label(preset.title, systemImage: preset.systemImage)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(appModel.isGenerating)
                    .accessibilityLabel(preset.title)
                    .accessibilityHint("Fills the prompt with this idea")
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 320)
    }
}

// MARK: - Create sheet

private struct IPhoneCreatePanel: View {
    @Bindable var appModel: AppModel
    @Binding var level: PhonePanelLevel
    @Binding var selectedItem: PhotosPickerItem?
    let onGenerate: () -> Void
    var onGenerateSet: () -> Void = {}

    @State private var showParameters = false
    @FocusState private var isPromptFocused: Bool

    private var isPeek: Bool { level == .peek }
    private var isLarge: Bool { level == .history }

    private var canGenerate: Bool {
        guard !appModel.isDirectorBusy else { return false }
        switch appModel.inputMode {
        case .text:
            return !appModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image:
            return appModel.inputImage != nil && !appModel.isProcessingImage
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isPeek {
                sheetHeader
                if isLarge {
                    historyList
                } else {
                    createControls
                    Spacer(minLength: 0)
                }
                Divider()
            }

            composer
        }
        .onChange(of: isPromptFocused) { _, focused in
            if focused, isPeek {
                level = .create
            }
        }
        .sheet(isPresented: $showParameters) {
            NavigationStack {
                ScrollView {
                    IOSParameterControlsView(appModel: appModel)
                        .padding(16)
                }
                .navigationTitle("Parameters")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showParameters = false }
                            .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: Header (medium + large)

    private var sheetHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isLarge ? "History" : "Create")
                    .font(.headline)
                Text(isLarge
                     ? "Previous generations"
                     : "Text or photo → 3D model")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isLarge {
                Button {
                    level = .history
                } label: {
                    Image(systemName: "text.bubble")
                        .font(.body.weight(.medium))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("History")
            }
            Button {
                showParameters = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.body.weight(.medium))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Parameters")
            .disabled(appModel.isGenerating)
            AboutMesquetteButton(font: .body)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: Medium — mode, quality, ideas

    private var createControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Input Mode", selection: $appModel.inputMode) {
                Text("Text").tag(AppModel.InputMode.text)
                Text("Photo").tag(AppModel.InputMode.image)
            }
            .pickerStyle(.segmented)
            .disabled(appModel.isGenerating)
            .accessibilityLabel("Input mode")

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
                .disabled(appModel.isGenerating)
            }

            if appModel.inputMode == .text {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ideas")
                        .font(.subheadline.weight(.medium))
                    PromptPresetPickerView(appModel: appModel, style: .strip)
                    DirectorCompileBar(appModel: appModel, style: .compact)
                    DirectorResultCard(appModel: appModel, onGenerateSet: onGenerateSet)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: Composer — always full-width prompt + send

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                inputModeButton

                Group {
                    if appModel.inputMode == .text {
                        promptField
                    } else {
                        imagePicker
                    }
                }
                .frame(maxWidth: .infinity)

                if appModel.inputMode == .text {
                    DirectorCompileBar(appModel: appModel, style: .icon)
                }
                generateButton
            }

            if isPeek && appModel.generationHistory.isEmpty && !appModel.isGenerating {
                Text("Swipe up for ideas, quality, and history")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 46)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, isPeek ? 4 : 10)
        .padding(.bottom, 10)
    }

    private var inputModeButton: some View {
        Menu {
            Picker("Input", selection: $appModel.inputMode) {
                Label("Text to 3D", systemImage: "text.alignleft")
                    .tag(AppModel.InputMode.text)
                Label("Photo to 3D", systemImage: "photo")
                    .tag(AppModel.InputMode.image)
            }
        } label: {
            Image(systemName: appModel.inputMode == .text
                  ? "text.alignleft"
                  : "photo")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(.fill.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(appModel.isGenerating)
        .accessibilityLabel(appModel.inputMode == .text ? "Text to 3D" : "Photo to 3D")
        .accessibilityHint("Switch between text and photo input")
    }

    private var promptField: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField(
                "Describe a 3D model…",
                text: $appModel.prompt,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(isPeek ? 1...2 : 1...5)
            .focused($isPromptFocused)
            .submitLabel(.go)
            .disabled(appModel.isDirectorBusy)
            .onSubmit {
                guard canGenerate else { return }
                onGenerate()
            }

            if !appModel.prompt.isEmpty && !appModel.isGenerating {
                Button {
                    appModel.prompt = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear prompt")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var photoPickerTitle: String {
        appModel.inputImage == nil ? "Choose a photo" : "Change photo"
    }

    private var imagePicker: some View {
        let title = photoPickerTitle
        return HStack(spacing: 10) {
            if let img = appModel.inputImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
            } else if appModel.isProcessingImage {
                ProgressView()
                    .frame(width: 36, height: 36)
            }

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(appModel.isGenerating || appModel.isProcessingImage)

            if appModel.inputImage != nil && !appModel.isGenerating {
                Button {
                    appModel.inputImage = nil
                    selectedItem = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove photo")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var generateButton: some View {
        if appModel.isGenerating {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.regular)
                .frame(width: 36, height: 36)
                .accessibilityLabel("Generating, \(Int(appModel.progress * 100)) percent")
        } else {
            Button(action: onGenerate) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 36))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(canGenerate ? Color.accentColor : Color.secondary.opacity(0.45))
            }
            .buttonStyle(.plain)
            .disabled(!canGenerate)
            .accessibilityLabel("Generate 3D model")
            .accessibilityHint(canGenerate
                               ? "Starts generating from the current prompt"
                               : (appModel.inputMode == .text
                                  ? "Enter a description first"
                                  : "Choose a photo first"))
        }
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if appModel.generationHistory.isEmpty {
                        Text("Generate a model and it will show up here.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                    ForEach(appModel.generationHistory) { record in
                        ChatBubbleView(record: record)
                            .id(record.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: appModel.generationOrder.count) {
                if let lastID = appModel.generationOrder.last {
                    withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("iPhone") {
    IPhoneContentView(
        viewModel: ContentViewModel(),
        isSceneLocked: .constant(false),
        dragVertical: .constant(false),
        resetTrigger: .constant(0)
    )
    .environment(AppModel())
}
#endif
