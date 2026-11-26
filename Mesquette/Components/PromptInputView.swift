#if os(visionOS)
import SwiftUI
import os
import PhotosUI

struct PromptInputView: View {
    @Bindable var appModel: AppModel
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var showPresets = false

    var body: some View {
        VStack(spacing: 16) {
            Picker("Input Mode", selection: $appModel.inputMode) {
                Text("Text to 3D").tag(AppModel.InputMode.text)
                Text("Image to 3D").tag(AppModel.InputMode.image)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 48)
            .disabled(appModel.isGenerating)
            .accessibilityLabel("Input mode")

            if appModel.inputMode == .text {
                textComposer
            } else {
                imageComposer
            }
        }
        .sheet(isPresented: $showPresets) {
            NavigationStack {
                PromptPresetPickerView(appModel: appModel, style: .expanded) {
                    showPresets = false
                }
                .padding(20)
                .navigationTitle("Ideas")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showPresets = false }
                            .fontWeight(.semibold)
                    }
                }
            }
            .frame(minWidth: 640, minHeight: 560)
        }
    }

    private var textComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                "A blue sports car, a bakery at first light…",
                text: $appModel.prompt,
                axis: .vertical
            )
            .font(.title2)
            .lineLimit(3...8)
            .padding(18)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            )
            .disabled(appModel.isDirectorBusy)
            .padding(.horizontal, 48)

            HStack(spacing: 12) {
                Button {
                    showPresets = true
                } label: {
                    Label("Browse ideas", systemImage: "square.grid.2x2")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                }
                .buttonStyle(.bordered)
                .hoverEffect(.highlight)
                .disabled(appModel.isDirectorBusy)
                .help("Open the scene library, or invent one")

                if !appModel.prompt.isEmpty {
                    Button("Clear") {
                        appModel.prompt = ""
                    }
                    .buttonStyle(.borderless)
                    .disabled(appModel.isGenerating)
                }

                Spacer()

                Text("\(appModel.prompt.count) characters")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 48)
        }
    }

    private var imageComposer: some View {
        HStack(spacing: 16) {
            if let img = appModel.inputImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onTapGesture(count: 2) {
                        appModel.showImagePreview = true
                    }
                    .popover(isPresented: $appModel.showImagePreview) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(minWidth: 400, minHeight: 400)
                            .padding()
                    }
            } else if appModel.isProcessingImage {
                ProgressView()
                    .frame(width: 88, height: 88)
            } else {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                    .frame(width: 88, height: 88)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(appModel.inputImage == nil
                     ? "Choose a photo of a single object on a simple background."
                     : "Background removal runs automatically when possible.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                PhotosPicker("Select Image", selection: $selectedItem, matching: .images)
                    .font(.title3)
                    .buttonStyle(.borderedProminent)
                    .disabled(appModel.isGenerating || appModel.isProcessingImage)
            }

            Spacer()
        }
        .padding(.horizontal, 48)
        .onChange(of: selectedItem) { _, newItem in
            appModel.isProcessingImage = true
            Task {
                let pickedData: Data?
                do {
                    pickedData = try await newItem?.loadTransferable(type: Data.self)
                } catch {
                    Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.visionarydevops.Mesquette", category: "image").error("Image pick failed: \(error.localizedDescription, privacy: .public)")
                    pickedData = nil
                }
                if let data = pickedData,
                   let uiImage = UIImage(data: data) {
                    var finalImg = uiImage
                    if let cgImage = uiImage.cgImage {
                        do {
                            if let stripped = try await ImageBackgroundRemoval.removeBackground(from: cgImage) {
                                finalImg = UIImage(cgImage: stripped)
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
                    await MainActor.run { appModel.isProcessingImage = false }
                }
            }
        }
    }
}
#endif
