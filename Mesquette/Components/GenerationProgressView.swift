import SwiftUI

struct GenerationProgressView: View {
    @Bindable var appModel: AppModel
    
    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: appModel.progress, total: 1.0)
                .progressViewStyle(.linear)
                .padding(.horizontal, 100)
            Text(appModel.progressPhaseLabel.isEmpty
                 ? "Generating mesh…"
                 : appModel.progressPhaseLabel)
                .font(.headline)
                .foregroundColor(.secondary)
            Text("\(Int(appModel.progress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }
}
