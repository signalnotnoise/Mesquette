// AboutMesquetteView.swift
// Mesquette — Credits live here, not on the splash.

import SwiftUI

struct AboutMesquetteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ZStack {
                    Image("BrandLogoBack")
                        .resizable()
                        .scaledToFit()
                    Image("BrandLogoMiddle")
                        .resizable()
                        .scaledToFit()
                    Image("BrandLogoFront")
                        .resizable()
                        .scaledToFit()
                }
                .frame(width: 128, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                VStack(spacing: 8) {
                    Text(AppIdentity.name)
                        .font(.largeTitle.weight(.bold))
                    Text("Text or image → 3D mesh")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 6) {
                    Text(AppIdentity.copyrightCredit)
                    Text(AppIdentity.developerCredit)
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

                DirectorAvailabilityView(appModel: appModel)
                    .padding(.top, 8)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(28)
            .navigationTitle("About")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
#if os(macOS)
        .frame(width: 400, height: 520)
#elseif os(visionOS)
        .frame(minWidth: 480, minHeight: 560)
#endif
    }
}

struct AboutMesquetteButton: View {
    var font: Font = .body
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(font)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(AppIdentity.name)")
        .sheet(isPresented: $isPresented) {
            AboutMesquetteView()
        }
    }
}
