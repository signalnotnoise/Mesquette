// DirectorResultCard.swift
// Mesquette — Shows a compiled prompt or a laid-out scene set.

import SwiftUI

struct DirectorResultCard: View {
    @Bindable var appModel: AppModel
    var onGenerateSet: (() -> Void)?
    @State private var viewModel = DirectorResultCardViewModel()

    var body: some View {
        if let error = appModel.directorError, !error.isEmpty {
            errorRow(error)
        }

        if let compiled = appModel.lastCompilation {
            card(compiled)
        }
    }

    @ViewBuilder
    private func errorRow(_ error: String) -> some View {
        Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func card(_ compiled: CompiledPrompt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: compiled.kind == .set ? "square.grid.3x3.fill" : "text.badge.checkmark")
                    .foregroundStyle(.tint)
                Text(compiled.title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Button("Revert") {
                    viewModel.revert(appModel: appModel)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(appModel.isDirectorBusy)
            }

            if compiled.kind == .set {
                HStack(spacing: 6) {
                    chip(compiled.layout.title)
                    if !compiled.mood.isEmpty {
                        chip(compiled.mood)
                    }
                }
            }

            Text(compiled.rationale)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if compiled.kind == .single {
                singleBody(compiled)
            } else {
                setBody(compiled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func singleBody(_ compiled: CompiledPrompt) -> some View {
        HStack(spacing: 6) {
            chip(compiled.scale.title)
            chip(compiled.material.title)
            if compiled.variationCount > 1 {
                Button("Use \(compiled.variationCount) variations") {
                    viewModel.applyVariations(appModel: appModel)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(appModel.isDirectorBusy)
            }
        }
    }

    @ViewBuilder
    private func setBody(_ compiled: CompiledPrompt) -> some View {
        Text("Director invented this set — separate meshes, staged on the table.")
            .font(.caption2)
            .foregroundStyle(.tertiary)

        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(compiled.parts) { part in
                    partRow(part, selected: part.id == appModel.selectedPartID)
                }
            }
        }
        .frame(maxHeight: compiled.parts.count > 3 ? 168 : nil)
        .scrollIndicators(.visible)

        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                setActionButtons
            }
            VStack(alignment: .leading, spacing: 8) {
                setActionButtons
            }
        }
    }

    @ViewBuilder
    private var setActionButtons: some View {
        if let onGenerateSet {
            Button("Generate as set") {
                onGenerateSet()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(appModel.isDirectorBusy || (appModel.lastCompilation?.parts.count ?? 0) < 2)
        }

        Button("Use first only") {
            viewModel.useFirstPart(appModel: appModel)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(appModel.isDirectorBusy)
    }

    private func partRow(_ part: CompiledPart, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                guard !appModel.isDirectorBusy else { return }
                viewModel.selectPart(id: part.id, appModel: appModel)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(part.title)
                            .font(.caption.weight(.semibold))
                        if part.isHero {
                            Text("hero")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                    }
                    Text(part.shapEPrompt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text("\(part.slot.title) · \(part.scale.title) · \(part.material.title)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if (appModel.lastCompilation?.parts.count ?? 0) > 2 {
                Button {
                    viewModel.removePart(id: part.id, appModel: appModel)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(appModel.isDirectorBusy)
                .accessibilityLabel("Remove \(part.title)")
            }
        }
        .padding(6)
        .background(
            selected ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.fill.tertiary, in: Capsule(style: .continuous))
    }
}
