// DirectorAvailabilityView.swift
// Mesquette — Explains on-device Foundation Models vs Core ML.

import SwiftUI

struct DirectorAvailabilityView: View {
    @Bindable var appModel: AppModel
    @State private var viewModel = DirectorAvailabilityViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(viewModel.headline, systemImage: "wand.and.stars")
                .font(.headline)

            HStack(spacing: 8) {
                statusDot
                Text(appModel.directorAvailability.message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }

            Text(viewModel.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { viewModel.refresh(appModel: appModel) }
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private var dotColor: Color {
        switch appModel.directorAvailability {
        case .available: return .green
        case .checking: return .secondary
        case .unavailable: return .orange
        }
    }
}
