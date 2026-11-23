// visionOS/VisionHistoryView.swift
// Mesquette — Export / reuse without burying the create window.

#if os(visionOS)
import SwiftUI

struct VisionHistoryView: View {
    @Bindable var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    var onReuse: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            Group {
                if appModel.generationHistory.isEmpty {
                    ContentUnavailableView(
                        "No models yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Generate something in the main window. Finished meshes show up here for export and reuse.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(appModel.generationHistory.reversed()) { record in
                                historyCard(record)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .hoverEffect(.highlight)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 480)
    }

    private func historyCard(_ record: GenerationRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: statusIcon(record.status))
                    .foregroundStyle(statusColor(record.status))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.prompt)
                        .font(.headline)
                        .lineLimit(3)
                    if let setTitle = record.setTitle, let index = record.setIndex {
                        Text("\(setTitle) · part \(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let params = record.params {
                        Text("seed \(params.seed) · grid \(params.gridSize) · \(params.numInferenceSteps) steps")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 8)
                Text(record.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if case .completed = record.status {
                HStack(spacing: 12) {
                    if record.latestMesh != nil {
                        ExportMeshButton(record: record)
                    }
                    Button {
                        appModel.inputMode = .text
                        appModel.prompt = record.prompt
                        if let params = record.params {
                            appModel.seed = params.seed
                        }
                        onReuse?()
                        dismiss()
                    } label: {
                        Label("Reuse prompt", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func statusIcon(_ status: GenerationRecord.Status) -> String {
        switch status {
        case .generating: return "progress.indicator"
        case .completed:  return "checkmark.circle.fill"
        case .failed:     return "exclamationmark.circle.fill"
        }
    }

    private func statusColor(_ status: GenerationRecord.Status) -> Color {
        switch status {
        case .generating: return .secondary
        case .completed:  return .green
        case .failed:     return .red
        }
    }
}
#endif
