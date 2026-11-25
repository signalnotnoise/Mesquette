// RuntimeAssetLocator.swift
// Resolves the Shap-E weights directory, in order:
//   1. a `runtime_bundle` copied into the app (legacy engineering builds)
//   2. Apple-hosted Background Assets packs (Release / TestFlight / App Store)
//   3. the pinned public Hugging Face bundle in Caches (HFBundleDownloader)

import Foundation
#if os(macOS)
import Security
#endif
import System
#if canImport(BackgroundAssets)
import BackgroundAssets
#endif

enum RuntimeAssetLocator {
    static let textPackID = "shap-e-text"
    static let imagePackID = "shap-e-image"
    static let appGroupID = "group.com.visionarydevops.Mesquette"
    static let bundleRelativeRoot = "runtime_bundle"

    /// Engineering builds still copy `runtime_bundle` into the app. Release
    /// excludes it so the IPA stays under the 4 GB App Store cap.
    static func bundledRuntimeURL() -> URL? {
        guard let root = Bundle.main.resourceURL?
            .appendingPathComponent(bundleRelativeRoot, isDirectory: true)
        else { return nil }
        let manifest = root.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
        return root
    }

    /// Directory ShapERuntime can treat as `modelBundleURL`.
    static func resolvedModelBundleURL() async throws -> URL {
        try await resolve(scope: .text)
    }

    /// Call before image-to-3D so `clip_vision` / `image300m` are on disk.
    static func resolvedModelBundleURLIncludingImage() async throws -> URL {
        try await resolve(scope: .full)
    }

    /// Background Assets *traps* (`Fatal error: The process lacks a team
    /// ID`) instead of throwing when touched from an ad-hoc/unsigned build,
    /// so the hosted attempt must be gated on an actual team identifier —
    /// a do/catch cannot recover from it.
    static var hasTeamIdentifier: Bool {
#if os(macOS)
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        else { return false }
        return !team.isEmpty
#else
        // SecCode doesn't exist off macOS. Signed iOS/visionOS builds always
        // carry a provisioning profile naming a team; unsigned simulator
        // builds don't — exactly the split the gate needs.
        return provisioningTeamIdentifier != nil
#endif
    }

#if !os(macOS)
    private static var provisioningTeamIdentifier: String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<plist".utf8))?.lowerBound,
              let end = data.range(of: Data("</plist>".utf8), options: .backwards)?.upperBound,
              let plist = try? PropertyListSerialization.propertyList(
                  from: data[start..<end], format: nil) as? [String: Any],
              let teams = plist["TeamIdentifier"] as? [String]
        else { return nil }
        return teams.first { !$0.isEmpty }
    }
#endif

    private static func resolve(scope: HFBundleScope) async throws -> URL {
        if let bundled = bundledRuntimeURL() { return bundled }
        if hasTeamIdentifier {
            do {
                return try await hostedRuntimeURL(includingImage: scope == .full)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Packs unavailable/downloading failed: fall through to HF.
            }
        }
        return try await HFBundleDownloader.resolveBundle(scope: scope)
    }

#if canImport(BackgroundAssets)
    @available(iOS 26, macOS 26, visionOS 26, *)
    @available(watchOS, unavailable)
    private static func hostedRuntimeURL(includingImage: Bool) async throws -> URL {
        try await ensurePack(id: textPackID)
        if includingImage {
            try await ensurePack(id: imagePackID)
        } else {
            // Opportunistic prefetch: failure only means the image pack
            // downloads later via resolvedModelBundleURLIncludingImage().
            Task {
                try? await ensurePack(id: imagePackID)
            }
        }
        // Packs share one namespace; this merges slices from every downloaded pack.
        // Do not persist the URL past process lifetime.
        return try AssetPackManager.shared.url(for: FilePath(bundleRelativeRoot))
    }

    @available(iOS 26, macOS 26, visionOS 26, *)
    @available(watchOS, unavailable)
    private static func ensurePack(id: String) async throws {
        if #available(visionOS 27, *) {
            if let pack = try await AssetPackManager.shared.manifest.assetPack(withID: id){
                try await AssetPackManager.shared.ensureLocalAvailability(of: pack)
            }
        } else {
            // Fallback on earlier versions
        }
    }
#else
    private static func hostedRuntimeURL(includingImage: Bool) async throws -> URL {
        throw ShapERuntimeLoadError.bundleNotFound
    }
#endif
}
