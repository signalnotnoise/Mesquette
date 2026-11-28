// GenerationSessionStore.swift
// Mesquette — Owns the shared MLX3DSession and where its weights come from.
//
// Replaces ShapERuntimeStore + TripoSRStore after the mlx-3d-runtime-swift
// migration: the package session caches loaded models per key; this actor
// resolves bundle/weights URLs (Background Assets or verified HF cache),
// preloads Shap-E at launch, and replays download progress to late waiters.

import CoreGraphics
import Foundation
import Metal
import MLX
import MLX3DRuntime
import ShapERuntime
#if canImport(UIKit)
import UIKit
#endif

nonisolated enum GenerationLoadError: Error, LocalizedError, Sendable {
    case bundleNotFound
    case unavailableInPreviews

    var errorDescription: String? {
        switch self {
        case .bundleNotFound:
            return "Model weights were not found and could not be downloaded."
        case .unavailableInPreviews:
            return "Model loading is disabled in Xcode Previews."
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
        // Documented settle exception: let the foreground transition land
        // before the first Metal submit (see AGENTS.md). Not a race fix.
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

actor GenerationSessionStore {
    static let shared = GenerationSessionStore()

    private let session = MLX3DSession()
    private var shapELoadTask: Task<Void, Error>?
    private var shapELoadEpoch: UInt64 = 0
    private var shapEBundle: (bundle: URL, bpe: URL)?

    /// Latest weights-download fraction; observers are replayed the current
    /// value immediately (splash subscribes after `preload()` started).
    private var downloadProgress: Double = 0
    private var progressObservers: [UUID: @Sendable (Double) -> Void] = [:]

    private func publishProgress(_ fraction: Double) {
        // Ticks cross one Task hop per update and may reorder slightly;
        // observers must still see a monotonic sequence.
        downloadProgress = max(downloadProgress, fraction)
        for observer in progressObservers.values { observer(downloadProgress) }
    }

    private var downloadProgressSink: @Sendable (Double) -> Void {
        { [weak self] fraction in
            Task { await self?.publishProgress(fraction) }
        }
    }

    // MARK: - Weights resolution

    private func resolveShapEBundle(progress: (@Sendable (Double) -> Void)?) async throws -> (bundle: URL, bpe: URL) {
        if let shapEBundle { return shapEBundle }
        let modelURL = try await RuntimeAssetLocator.resolvedModelBundleURL(progress: progress)
        // BPE vocab ships as an app resource; the Hugging Face snapshot
        // also carries it at the bundle root for builds without one.
        let bpeURL = Bundle.main.url(forResource: "bpe_simple_vocab_16e6", withExtension: "txt.gz")
            ?? modelURL.appendingPathComponent("bpe_simple_vocab_16e6.txt.gz")
        guard FileManager.default.fileExists(atPath: bpeURL.path) else {
            throw GenerationLoadError.bundleNotFound
        }
        let resolved = (bundle: modelURL, bpe: bpeURL)
        shapEBundle = resolved
        return resolved
    }

    // MARK: - Lifecycle

    /// Kick off the Shap-E download+load. Safe to call more than once.
    func preload() {
        guard !RuntimeLaunchContext.isXcodePreview else { return }
        _ = ensureShapELoadTask()
    }

    /// Bind Metal/MLX on the main thread while the app is in the foreground.
    /// Call before Generate so `@concurrent` MLX.eval is not the first GPU submit.
    func prepareForGPUWork() async {
        guard !RuntimeLaunchContext.isXcodePreview else { return }
        await MLXForegroundGPU.prepare()
    }

    /// Wait until the Shap-E load finishes. Errors are swallowed so
    /// launch UI can dismiss even if the bundle is missing.
    func waitUntilLoadFinishes(progress: (@Sendable (Double) -> Void)? = nil) async {
        guard !RuntimeLaunchContext.isXcodePreview else { return }
        do {
            try await loadShapE(progress: progress)
        } catch {
            // Splash still proceeds; Generate reports the real failure.
        }
    }

    /// Resolve + load Shap-E into the session cache. `progress` observers
    /// can register at any time; late ones replay the current fraction.
    func loadShapE(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        if RuntimeLaunchContext.isXcodePreview {
            throw GenerationLoadError.unavailableInPreviews
        }
        let observerID = progress.map { cb -> UUID in
            let id = UUID()
            progressObservers[id] = cb
            cb(downloadProgress)
            return id
        }
        defer { if let observerID { progressObservers[observerID] = nil } }
        try await ensureShapELoadTask().value
    }

    private func ensureShapELoadTask() -> Task<Void, Error> {
        if let shapELoadTask { return shapELoadTask }
        shapELoadEpoch &+= 1
        let epoch = shapELoadEpoch
        let task = Task.detached(priority: .userInitiated) { [self] in
            // Creating the MLX GPU stream during launch (app still inactive)
            // makes later Generate commit buffers that IOGPU rejects.
            await MLXForegroundGPU.prepare()
            do {
                try await self.performShapELoad()
                await self.shapELoadFinished(epoch: epoch, failed: false)
            } catch {
                await self.shapELoadFinished(epoch: epoch, failed: true)
                throw error
            }
        }
        shapELoadTask = task
        return task
    }

    private func performShapELoad() async throws {
        Self.applyDeviceCachePolicy()
        let sink = await downloadProgressSink
        let resolved = try await resolveShapEBundle(progress: sink)
        try await session.load(.shapE(modelBundleURL: resolved.bundle, bpeVocabularyURL: resolved.bpe))
    }

    private func shapELoadFinished(epoch: UInt64, failed: Bool) {
        guard shapELoadEpoch == epoch else { return }
        shapELoadTask = nil
        if failed {
            downloadProgress = 0
            // The resolved location may be why the load failed; never let a
            // retry reuse it without re-resolving first.
            shapEBundle = nil
        } else {
            publishProgress(1)
        }
    }

    /// Makes sure image-pipeline weight files are on disk (full bundle scope).
    func prepareImageWeights(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        _ = try await RuntimeAssetLocator.resolvedModelBundleURLIncludingImage(progress: progress)
    }

    // MARK: - Generation

    func textMeshes(
        prompt: String,
        batchSize: Int,
        guidanceScale: Float,
        numInferenceSteps: Int,
        gridSize: Int,
        queryBatchSize: Int,
        seed: Int,
        useMetalMarchingCubes: Bool,
        progressInterval: Int,
        progress: (@Sendable (String, Int, Int, [MeshResult]?) -> Void)?
    ) async throws -> [MeshResult] {
        try await loadShapE()
        let resolved = try await resolveShapEBundle(progress: nil)
        let options = TextToMeshOptions(
            guidanceScale: guidanceScale,
            numInferenceSteps: numInferenceSteps,
            gridSize: gridSize,
            queryBatchSize: queryBatchSize,
            seed: seed,
            useMetalMarchingCubes: useMetalMarchingCubes,
            progressInterval: progressInterval
        )
        let meshes = try await session.textToMeshBatch(
            prompt: prompt,
            modelBundleURL: resolved.bundle,
            bpeVocabularyURL: resolved.bpe,
            batchSize: batchSize,
            options: options,
            progress: progress.map { handler -> MLX3DProgressHandler in
                { event in handler(event.phase, event.step, event.totalSteps, event.partialMeshes?.map(Self.meshResult)) }
            }
        )
        return meshes.map(Self.meshResult)
    }

    func shapEImageMeshes(
        cgImage: CGImage,
        batchSize: Int,
        guidanceScale: Float,
        numInferenceSteps: Int,
        gridSize: Int,
        queryBatchSize: Int,
        seed: Int,
        useMetalMarchingCubes: Bool,
        progressInterval: Int,
        progress: (@Sendable (String, Int, Int, [MeshResult]?) -> Void)?
    ) async throws -> [MeshResult] {
        try await loadShapE()
        let resolved = try await resolveShapEBundle(progress: nil)
        var options = ShapEImageToMeshOptions()
        options.batchSize = batchSize
        options.guidanceScale = guidanceScale
        options.numInferenceSteps = numInferenceSteps
        options.gridSize = gridSize
        options.queryBatchSize = queryBatchSize
        options.seed = seed
        options.useMetalMarchingCubes = useMetalMarchingCubes
        options.progressInterval = progressInterval
        // Pickers already applied the white composite; don't apply it twice.
        options.applyWhiteBackgroundRemoval = false
        let meshes = try await session.imageToMeshShapE(
            cgImage: cgImage,
            modelBundleURL: resolved.bundle,
            bpeVocabularyURL: resolved.bpe,
            options: options,
            progress: progress.map { handler -> MLX3DProgressHandler in
                { event in handler(event.phase, event.step, event.totalSteps, event.partialMeshes?.map(Self.meshResult)) }
            }
        )
        return meshes.map(Self.meshResult)
    }

    /// TripoSR single-image generation. The image must already be a
    /// foreground cutout (the caller owns that policy, as before).
    func tripoMesh(
        cgImage: CGImage,
        useMetalMarchingCubes: Bool,
        progress: (@Sendable (String, Int, Int, [MeshResult]?) -> Void)?
    ) async throws -> MeshResult {
        await MLXForegroundGPU.prepare()
        let weightsURL = try await HFBundleDownloader.resolveTripoSRWeights()
        var options = ImageToMeshOptions()
        options.gridSize = 256  // previous facade default; package default is 128
        options.useMetalMarchingCubes = useMetalMarchingCubes
        options.applyForegroundCutout = false
        options.resizeMode = .stretch  // previous facade stretched to square
        let mesh = try await session.imageToMesh(
            cgImage: cgImage,
            weightsURL: weightsURL,
            options: options,
            progress: progress.map { handler -> MLX3DProgressHandler in
                { event in handler(event.phase, event.step, event.totalSteps, nil) }
            }
        )
        return Self.meshResult(from: mesh)
    }

    // MARK: - Mesh conversion

    /// Package `Mesh` (plain arrays) → the app's tensor-backed `MeshResult`.
    /// The single conversion point between the two mesh representations.
    nonisolated static func meshResult(from mesh: Mesh) -> MeshResult {
        func tensor<T>(_ values: [T], _ type: TensorDataType, shape: [Int]) -> RuntimeTensor {
            let data = values.withUnsafeBytes { Data($0) }
            // Counts come from a validated package mesh; a mismatch is a
            // programmer error in the conversion, surfaced in debug.
            return try! RuntimeTensor(name: "mlx3d", shape: shape, dataType: type, data: data)
        }
        let vertices = tensor(mesh.positions, .float32, shape: [mesh.vertexCount, 3])
        let faces = tensor(mesh.faces, .int32, shape: [mesh.faceCount, 3])
        var channels: [String: RuntimeTensor]?
        if let rgb = mesh.vertexColors, rgb.count == mesh.vertexCount * 3 {
            var rgba: [Float] = []
            rgba.reserveCapacity(mesh.vertexCount * 4)
            for i in 0..<mesh.vertexCount {
                rgba.append(contentsOf: [rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2], 1])
            }
            channels = ["RGBA": tensor(rgba, .float32, shape: [mesh.vertexCount, 4])]
        }
        var minC: [Float] = [0, 0, 0]
        var maxC: [Float] = [0, 0, 0]
        if mesh.vertexCount > 0 {
            minC = [mesh.positions[0], mesh.positions[1], mesh.positions[2]]
            maxC = minC
            for i in stride(from: 0, to: mesh.positions.count, by: 3) {
                for a in 0..<3 {
                    minC[a] = min(minC[a], mesh.positions[i + a])
                    maxC[a] = max(maxC[a], mesh.positions[i + a])
                }
            }
        }
        return MeshResult(
            vertices: vertices,
            faces: faces,
            vertexChannels: channels,
            bbox: BoundingBox(minCorner: minC, maxCorner: maxC),
            timings: [:],
            artifactInfo: ArtifactVersionInfo(artifactVersion: 0, manifestPath: "mlx3d")
        )
    }

    /// `cacheLimit` is only the unused-buffer pool, not model weights.
    /// Cap it once so jetsam does not see unbounded growth, but keep enough
    /// to reuse transformer activations across Generate taps.
    nonisolated private static func applyDeviceCachePolicy() {
#if os(iOS)
        MLX.Memory.cacheLimit = 256 * 1024 * 1024
#elseif os(visionOS)
        MLX.Memory.cacheLimit = 512 * 1024 * 1024
#endif
    }
}
