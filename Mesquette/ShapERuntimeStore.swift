// ShapERuntimeStore.swift
// Mesquette — Load Shap-E off the main actor so Generate is not blocked by I/O.

import Foundation
import Metal
import MLX
import ShapERuntime
#if canImport(UIKit)
import UIKit
#endif

nonisolated enum ShapERuntimeLoadError: Error, LocalizedError, Sendable {
    case bundleNotFound
    case unavailableInPreviews
    case assetPackUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .bundleNotFound:
            return "Shap-E runtime bundle was not in the app and could not be downloaded."
        case .unavailableInPreviews:
            return "Model loading is disabled in Xcode Previews."
        case .assetPackUnavailable(let detail):
            return "Could not download Shap-E weights: \(detail)"
        }
    }
}

nonisolated enum RuntimeLaunchContext {
    /// Canvas / PreviewShell often omit `XCODE_RUNNING_FOR_PREVIEWS` in the
    /// hosted app process. MLX then inits GPU on the preview sim and aborts
    /// (`basic_string` nullptr → SIGABRT).
    static var isXcodePreview: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return true }
        if env["ENABLE_PREVIEWS"] == "1" { return true }
        if env["XCTestConfigurationFilePath"] != nil { return true }
        let path = Bundle.main.bundlePath
        if path.contains("/Previews/") { return true }
        if path.contains("Preview.app") { return true }
        return false
    }
}

/// IOGPU rejects Metal command buffers whose queue was created while the app
/// was inactive (launch / background). Bind MLX's GPU stream on the main
/// thread after the scene is active, then concurrent generate can reuse it.
nonisolated enum MLXForegroundGPU {
    static func prepare() async {
        guard !RuntimeLaunchContext.isXcodePreview else { return }
#if os(iOS) || os(visionOS)
        await waitUntilActive()
        try? await Task.sleep(for: .milliseconds(80))
#endif
        await MainActor.run {
            bindMetalOnMain()
        }
    }

    @MainActor
    private static func bindMetalOnMain() {
        _ = MTLCreateSystemDefaultDevice()
        let warmup = MLXArray(Float(0))
        MLX.eval(warmup)
    }

#if os(iOS) || os(visionOS)
    private static func waitUntilActive() async {
        let active = await MainActor.run {
            UIApplication.shared.applicationState == .active
        }
        if active { return }

        let notifications = NotificationCenter.default.notifications(
            named: UIApplication.didBecomeActiveNotification
        )
        let stillActive = await MainActor.run {
            UIApplication.shared.applicationState == .active
        }
        if stillActive { return }

        for await _ in notifications {
            return
        }
    }
#endif
}

/// Shared loader. The first Generate tap awaits this instead of constructing
/// `ShapERuntime` on the main actor. Text-only init skips clip_vision + image300m
/// (~2.3 GB); those load on the first image generate.
actor ShapERuntimeStore {
    static let shared = ShapERuntimeStore()

    private var runtime: ShapERuntime?
    private var loadTask: Task<ShapERuntime, Error>?
    /// Bumped each time a new load task is created so a failed waiter cannot
    /// nil out a newer attempt that started after the failure.
    private var loadEpoch: UInt64 = 0

    /// Kick off a background load. Safe to call more than once.
    func preload() {
        guard !RuntimeLaunchContext.isXcodePreview else { return }
        _ = ensureLoadTask()
    }

    /// Bind Metal/MLX on the main thread while the app is in the foreground.
    /// Call before Generate so `@concurrent` MLX.eval is not the first GPU submit.
    func prepareForGPUWork() async {
        guard !RuntimeLaunchContext.isXcodePreview else { return }
        await MLXForegroundGPU.prepare()
    }

    /// Wait until the first load attempt finishes. Errors are swallowed so
    /// launch UI can dismiss even if the bundle is missing.
    func waitUntilLoadFinishes() async {
        guard !RuntimeLaunchContext.isXcodePreview else { return }
        do {
            _ = try await runtime()
        } catch {
            // Splash still proceeds; Generate reports the real failure.
        }
    }

    func runtime() async throws -> ShapERuntime {
        if RuntimeLaunchContext.isXcodePreview {
            throw ShapERuntimeLoadError.unavailableInPreviews
        }
        if let runtime {
            return runtime
        }
        let task = ensureLoadTask()
        let epoch = loadEpoch
        do {
            let loaded = try await task.value
            runtime = loaded
            loadTask = nil
            return loaded
        } catch {
            if loadEpoch == epoch {
                loadTask = nil
            }
            throw error
        }
    }

    private func ensureLoadTask() -> Task<ShapERuntime, Error> {
        if let loadTask {
            return loadTask
        }
        loadEpoch &+= 1
        let task = Task.detached(priority: .userInitiated) {
            // Creating the MLX GPU stream during launch (app still inactive)
            // makes later Generate commit buffers that IOGPU rejects.
            await MLXForegroundGPU.prepare()
            return try await Self.loadRuntime()
        }
        loadTask = task
        return task
    }

    /// Makes sure image-pipeline weight files are on disk (prefetch pack).
    func prepareImageWeights() async throws {
        _ = try await RuntimeAssetLocator.resolvedModelBundleURLIncludingImage()
    }

    private static func loadRuntime() async throws -> ShapERuntime {
        applyDeviceCachePolicy()
        do {
            let modelURL = try await RuntimeAssetLocator.resolvedModelBundleURL()
            // BPE vocab ships as an app resource; the Hugging Face snapshot
            // also carries it at the bundle root for builds without one.
            let bpeURL = Bundle.main.url(forResource: "bpe_simple_vocab_16e6", withExtension: "txt.gz")
                ?? modelURL.appendingPathComponent("bpe_simple_vocab_16e6.txt.gz")
            guard FileManager.default.fileExists(atPath: bpeURL.path) else {
                throw ShapERuntimeLoadError.bundleNotFound
            }
            return try ShapERuntime(modelBundleURL: modelURL, bpeVocabularyURL: bpeURL)
        } catch let error as ShapERuntimeLoadError {
            throw error
        } catch {
            throw ShapERuntimeLoadError.assetPackUnavailable(error.localizedDescription)
        }
    }

    /// `cacheLimit` is only the unused-buffer pool, not model weights.
    /// Weights live in active memory (~2.5 GB text pipeline). A 32 MB cache
    /// does not prevent OOM; it just forces a new Metal buffer per layer.
    /// Cap the pool once so jetsam does not see unbounded growth, but keep
    /// enough to reuse transformer activations across Generate taps.
    nonisolated private static func applyDeviceCachePolicy() {
#if os(iOS)
        Memory.cacheLimit = 256 * 1024 * 1024
#elseif os(visionOS)
        Memory.cacheLimit = 512 * 1024 * 1024
#endif
    }
}
