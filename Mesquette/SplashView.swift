// SplashView.swift
// Mesquette — Launch splash with layered logo animation.

import SwiftUI

/// Wraps the platform root so the splash covers the first load.
struct AppLaunchView<Content: View>: View {
    let content: Content
    @State private var showSplash = true

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .opacity(showSplash ? 0 : 1)
                .allowsHitTesting(!showSplash)

            if showSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.7)) {
                        showSplash = false
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.7), value: showSplash)
    }
}

struct SplashView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sunOpacity = 0.0
    @State private var sunScale: CGFloat = 0.55
    @State private var glowOpacity = 0.0
    @State private var atmosphere = 0.0
    @State private var sailOpacity = 0.0
    @State private var sailOffset: CGFloat = 36
    @State private var sailYaw = -22.0
    @State private var meshOpacity = 0.0
    @State private var meshOffset: CGFloat = 28
    @State private var titleOpacity = 0.0
    @State private var titleOffset: CGFloat = 18
    @State private var creditOpacity = 0.0
    @State private var idleTilt = 0.0
    @State private var showPreparing = false
    @State private var preparingLabel = "Preparing Engine…"
    @State private var weightsReady = false
    @State private var skipRequested = false
    @State private var didFinish = false

    private let copper = Color(red: 1.0, green: 0.78, blue: 0.48)
    private let ember = Color(red: 1.0, green: 0.45, blue: 0.08)

    private var titleGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.94, blue: 0.78),
                copper,
                Color(red: 0.90, green: 0.50, blue: 0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        GeometryReader { geo in
            let logoSize = min(min(geo.size.width, geo.size.height) * 0.48, 420)

            ZStack {
                Color.black.ignoresSafeArea()

                

                VStack(spacing: 0) {
                    Spacer()

                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        ember.opacity(0.55),
                                        Color(red: 0.7, green: 0.18, blue: 0.02).opacity(0.18),
                                        .clear
                                    ],
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: logoSize * 0.58
                                )
                            )
                            .frame(width: logoSize * 1.15, height: logoSize * 1.15)
                            .scaleEffect(sunScale)
                            .opacity(glowOpacity)
                            .blur(radius: 18)

                        Image("BrandLogoBack")
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .scaleEffect(sunScale)
                            .opacity(sunOpacity)

                        Image("BrandLogoMiddle")
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .offset(y: sailOffset)
                            .opacity(sailOpacity)
                            .rotation3DEffect(
                                .degrees(sailYaw),
                                axis: (x: 0.12, y: 1, z: 0.04)
                            )

                        Image("BrandLogoFront")
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .offset(x: meshOffset)
                            .opacity(meshOpacity)
                    }
                    .frame(width: logoSize, height: logoSize)
                    #if os(iOS)
                    .rotation3DEffect(
                        .degrees(idleTilt),
                        axis: (x: 0.18, y: 1, z: 0.06)
                    )
                    #endif
                    .shadow(color: Color.orange.opacity(sunOpacity * 0.35), radius: 36)

                    Text(AppIdentity.name)
                        .font(.system(size: titleSize(for: geo.size), weight: .bold))
                        .foregroundStyle(titleGradient)
                        .tracking(2.4)
                        .shadow(color: ember.opacity(0.35), radius: 12, y: 2)
                        .padding(.top, 8)
                        .offset(y: titleOffset)
                        .opacity(titleOpacity)
                        .accessibilityAddTraits(.isHeader)

                    if showPreparing {
                        ProgressView()
                            .tint(copper)
                            .padding(.top, 18)
                            .transition(.opacity)
                    }

                    Spacer()

                    Text(AppIdentity.copyrightCredit)
                        .font(creditFont(for: geo.size))
                        .foregroundStyle(copper.opacity(0.94))
                        .shadow(color: copper.opacity(0.45), radius: 10, y: 0)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, max(geo.safeAreaInsets.bottom, 28) + 8)
                        .opacity(creditOpacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .task {
            await runLaunchSequence()
        }
    }

    private func titleSize(for size: CGSize) -> CGFloat {
        min(max(size.width * 0.072, 36), 64)
    }

    private func creditFont(for size: CGSize) -> Font {
        let point = min(max(size.width * 0.028, 18), 26)
        return .custom("SnellRoundhand", size: point)
    }

    @MainActor
    private func runLaunchSequence() async {
        if RuntimeLaunchContext.isXcodePreview {
            await playIntro()
            return
        }

        await playIntro()

        let load = Task {
            await ShapERuntimeStore.shared.waitUntilLoadFinishes()
        }
        let hint = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(reduceMotion ? 80 : 250))
                try Task.checkCancellation()
                withAnimation(.easeIn(duration: 0.35)) {
                    showPreparing = true
                }
            } catch {
                return
            }
        }

        await load.value
        hint.cancel()
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 400))
        onFinished()
    }

    @MainActor
    private func playIntro() async {
        if reduceMotion {
            sunOpacity = 1
            sunScale = 1
            glowOpacity = 0.7
            sailOpacity = 1
            sailOffset = 0
            sailYaw = 0
            meshOpacity = 1
            meshOffset = 0
            titleOpacity = 1
            titleOffset = 0
            creditOpacity = 1
            return
        }

        withAnimation(.easeOut(duration: 1.05)) {
            sunOpacity = 1
            sunScale = 1
            glowOpacity = 1
        }
        try? await Task.sleep(for: .seconds(0.42))

        withAnimation(.spring(duration: 1.1, bounce: 0.16)) {
            sailOpacity = 1
            sailOffset = 0
            sailYaw = 0
        }
        try? await Task.sleep(for: .seconds(0.38))

        withAnimation(.easeOut(duration: 0.9)) {
            meshOpacity = 1
            meshOffset = 0
        }
        try? await Task.sleep(for: .seconds(0.32))

        withAnimation(.easeOut(duration: 0.7)) {
            titleOpacity = 1
            titleOffset = 0
        }
        try? await Task.sleep(for: .seconds(0.22))

        withAnimation(.easeOut(duration: 0.85)) {
            creditOpacity = 1
        }
        try? await Task.sleep(for: .seconds(0.9))

        withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
            idleTilt = 7.5
            sunScale = 1.04
        }
    }
}


#Preview {
    SplashView {
        
    }
}
