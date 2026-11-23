// DirectorCompileBar.swift
// Mesquette — Compile / status control. Logic lives in DirectorCompileBarViewModel.

import SwiftUI

struct DirectorCompileBar: View {
    @Bindable var appModel: AppModel
    var style: Style = .regular
    @State private var viewModel = DirectorCompileBarViewModel()

    enum Style: Sendable {
        case regular
        case compact
        case icon
    }

    var body: some View {
        Group {
            switch style {
            case .regular:
                regularBar
            case .compact:
                compactBar
            case .icon:
                iconButton
            }
        }
        .onAppear {
            viewModel.refreshAvailability(appModel: appModel)
        }
        .disabled(appModel.inputMode != .text || appModel.isGenerating)
        .opacity(appModel.inputMode == .text ? 1 : 0.45)
    }

    private var regularBar: some View {
        HStack(spacing: 10) {
            inventButton

            Button {
                Task { await viewModel.compile(appModel: appModel) }
            } label: {
                if appModel.isCompiling {
                    ProgressView()
                        .controlSize(.small)
                    Text("Compiling…")
                } else {
                    Label("Compile", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.bordered)
            .disabled(!appModel.canCompile && !appModel.isCompiling)
            .help(compileHelp)
#if os(visionOS)
            .hoverEffect(.highlight)
#endif

            if !appModel.directorAvailability.isAvailable,
               case .unavailable(let reason) = appModel.directorAvailability {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var compactBar: some View {
        HStack(spacing: 8) {
            inventButton
                .controlSize(.small)

            Button {
                Task { await viewModel.compile(appModel: appModel) }
            } label: {
                if appModel.isCompiling {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Compile", systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.medium))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!appModel.canCompile && !appModel.isCompiling)
            .help(compileHelp)
        }
    }

    private var iconButton: some View {
        HStack(spacing: 6) {
            Button {
                Task { await viewModel.invent(appModel: appModel) }
            } label: {
                if appModel.isInventing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 36, height: 36)
                } else {
                    Image(systemName: "dice.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(.fill.quaternary, in: Circle())
                }
            }
            .buttonStyle(.plain)
            .disabled(!appModel.canInvent && !appModel.isInventing)
            .accessibilityLabel("Invent a scene idea")
            .help(inventHelp)

            Button {
                Task { await viewModel.compile(appModel: appModel) }
            } label: {
                if appModel.isCompiling {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 36, height: 36)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(.fill.quaternary, in: Circle())
                }
            }
            .buttonStyle(.plain)
            .disabled(!appModel.canCompile && !appModel.isCompiling)
            .accessibilityLabel("Compile prompt")
            .help(compileHelp)
        }
    }

    private var inventButton: some View {
        Button {
            Task { await viewModel.invent(appModel: appModel) }
        } label: {
            if appModel.isInventing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Inventing…")
                }
            } else {
                Label("Invent", systemImage: "dice.fill")
            }
        }
        .buttonStyle(.bordered)
        .disabled(!appModel.canInvent && !appModel.isInventing)
        .help(inventHelp)
        .accessibilityLabel("Invent a scene idea")
#if os(visionOS)
        .hoverEffect(.highlight)
#endif
    }

    private var compileHelp: String {
        if appModel.directorAvailability.isAvailable {
            return "Rewrite this as a Shap-E prompt, or split a scene into objects"
        }
        return appModel.directorAvailability.message
    }

    private var inventHelp: String {
        if appModel.directorAvailability.isAvailable {
            return appModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Ask Apple Intelligence to write a new scene preset"
                : "Invent a new scene preset around the current description"
        }
        return appModel.directorAvailability.message
    }
}
