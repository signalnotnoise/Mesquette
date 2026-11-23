import SwiftUI

struct GenerateButtonView: View {
    @Bindable var appModel: AppModel
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("Generate 3D Model")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 40)
                .padding(.vertical, 15)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
#if os(visionOS)
        .hoverEffect(.highlight)
#endif
        .disabled(
            appModel.isDirectorBusy
                || (appModel.inputMode == .text
                    ? appModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    : appModel.inputImage == nil)
        )
    }
}
