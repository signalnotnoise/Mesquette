// PromptPresetPickerView.swift
// Mesquette — Browse categories + tap a chip to fill the prompt field

import SwiftUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Intuitive preset browser: category tabs + scrollable chips.
/// Tapping a preset writes into `appModel.prompt` (text mode only).
struct PromptPresetPickerView: View {
    @Bindable var appModel: AppModel

    /// Compact (iPad chat panel), expanded (visionOS / Mac sheet), or a single-row strip (iPhone).
    var style: Style = .compact
    /// Called after a chip (or Invent) writes into the prompt.
    var onApply: (() -> Void)? = nil

    enum Style: Sendable {
        case compact
        case expanded
        /// Category menu + horizontally scrolling chips. Fits a phone composer.
        case strip
    }

    @State private var selectedCategory: PromptCategory = .scenes
    @State private var lastAppliedID: String?
    @State private var viewModel = DirectorCompileBarViewModel()

    private var presets: [PromptPreset] {
        PromptPresetLibrary.presets(in: selectedCategory)
    }

    var body: some View {
        Group {
            switch style {
            case .strip:
                stripContent
            case .compact, .expanded:
                VStack(alignment: .leading, spacing: style == .expanded ? 12 : 8) {
                    header
                    if !appModel.inventedPresets.isEmpty {
                        inventedRow
                    }
                    categoryBar
                    presetGrid
                }
            }
        }
        .opacity(appModel.inputMode == .text ? 1 : 0.45)
        .disabled(appModel.inputMode != .text || appModel.isGenerating || appModel.isInventing)
        .animation(.easeInOut(duration: 0.15), value: selectedCategory)
        .animation(.easeInOut(duration: 0.12), value: lastAppliedID)
        .onAppear {
            viewModel.refreshAvailability(appModel: appModel)
        }
    }

    // MARK: - Phone strip

    private var stripContent: some View {
        HStack(spacing: 8) {
            inventChip
            categoryMenu

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(appModel.inventedPresets) { preset in
                        presetChip(preset)
                    }
                    ForEach(presets) { preset in
                        presetChip(preset)
                    }
                }
            }
            .scrollClipDisabled()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var categoryMenu: some View {
        Menu {
            ForEach(PromptCategory.allCases) { category in
                Button {
                    selectedCategory = category
                } label: {
                    Label(category.title, systemImage: category.systemImage)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: selectedCategory.systemImage)
                Text(selectedCategory.title)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.22))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Preset category, \(selectedCategory.title)")
        .accessibilityHint("Choose a preset category")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles.rectangle.stack")
                .foregroundStyle(.secondary)
            Text(style == .expanded ? "Prompt presets" : "Presets")
                .font(style == .expanded ? .headline : .subheadline)
                .fontWeight(.semibold)
            Spacer()
            if style == .expanded {
                inventChip
            }
            Text("\(PromptPresetLibrary.all.count) ideas")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if !appModel.prompt.isEmpty {
                Button {
                    appModel.prompt = ""
                    lastAppliedID = nil
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                        .labelStyle(.iconOnly)
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .help("Clear prompt")
            }
        }
    }

    private var inventChip: some View {
        Button {
            Task {
                await viewModel.invent(appModel: appModel)
                if let latest = appModel.inventedPresets.first {
                    lastAppliedID = latest.id
                    onApply?()
                }
            }
        } label: {
            HStack(spacing: 6) {
                if appModel.isInventing {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "dice.fill")
                }
                Text(appModel.isInventing ? "Inventing…" : "Invent")
            }
            .font(style == .expanded ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
            .padding(.horizontal, style == .expanded ? 12 : 10)
            .padding(.vertical, style == .expanded ? 8 : 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.22))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!appModel.canInvent && !appModel.isInventing)
        .help(
            appModel.directorAvailability.isAvailable
                ? "Ask Apple Intelligence to write a new scene preset"
                : appModel.directorAvailability.message
        )
        .accessibilityLabel("Invent a scene idea")
    }

    private var inventedRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FOR YOU")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
            FlowLayout(spacing: 8) {
                ForEach(appModel.inventedPresets) { preset in
                    presetChip(preset)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Categories

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PromptCategory.allCases) { category in
                    categoryChip(category)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func categoryChip(_ category: PromptCategory) -> some View {
        let selected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            Label(category.title, systemImage: category.systemImage)
                .font(style == .expanded ? .subheadline : .caption)
                .fontWeight(selected ? .semibold : .regular)
                .padding(.horizontal, style == .expanded ? 14 : 10)
                .padding(.vertical, style == .expanded ? 10 : 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? AnyShapeStyle(.tint.opacity(0.22)) : AnyShapeStyle(.quaternary))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(selected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
#if os(visionOS)
        .hoverEffect(.highlight)
#endif
        .accessibilityLabel(category.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Preset chips

    private var presetGrid: some View {
        ScrollView(.vertical, showsIndicators: style == .expanded) {
            FlowLayout(spacing: 8) {
                ForEach(presets) { preset in
                    presetChip(preset)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: style == .expanded ? 360 : 110)
    }

    private func presetChip(_ preset: PromptPreset) -> some View {
        let applied = lastAppliedID == preset.id
        return Button {
            apply(preset)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: preset.systemImage)
                    .font(.caption)
                    .foregroundStyle(applied ? Color.accentColor : .secondary)
                Text(preset.title)
                    .font(style == .expanded ? .subheadline : .caption)
                    .fontWeight(applied ? .semibold : .medium)
                    .lineLimit(1)
            }
            .padding(.horizontal, style == .expanded ? 12 : 10)
            .padding(.vertical, style == .expanded ? 10 : 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(applied ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.ultraThinMaterial))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(applied ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(preset.prompt)
#if os(visionOS)
        .hoverEffect(.highlight)
#endif
        .accessibilityLabel(preset.title)
        .accessibilityHint(preset.prompt)
        .contextMenu {
            Button("Use prompt") { apply(preset) }
            Button("Copy prompt") {
                copyToPasteboard(preset.prompt)
            }
        }
    }

    private func apply(_ preset: PromptPreset) {
        appModel.inputMode = .text
        appModel.prompt = preset.prompt
        lastAppliedID = preset.id
        onApply?()
    }

    private func copyToPasteboard(_ text: String) {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#elseif canImport(UIKit)
        UIPasteboard.general.string = text
#endif
    }
}

// MARK: - Simple flow layout (wrapping chips)

/// Horizontal flow that wraps to the next line (no external deps).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            width = max(width, x - spacing)
        }

        let height = y + rowHeight
        return (CGSize(width: width, height: height), frames)
    }
}

// MARK: - Preview

#Preview("Compact") {
    PromptPresetPickerView(appModel: AppModel(), style: .compact)
        .padding()
        .frame(width: 360)
}

#Preview("Expanded") {
    PromptPresetPickerView(appModel: AppModel(), style: .expanded)
        .padding()
        .frame(width: 640)
}
