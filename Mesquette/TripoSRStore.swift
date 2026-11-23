// TripoSRStore.swift
// Mesquette — Load the TripoSR facade runtime off the main actor, mirroring
// ShapERuntimeStore: weights resolve (HF download on first use) happen once,
// and a failed load is never cached so the next Generate can retry.

import Foundation
import RuntimeWrapper

actor TripoSRStore {
    static let shared = TripoSRStore()

    private var runtime: ThreeDGenerationRuntime?
    private var loadTask: Task<ThreeDGenerationRuntime, Error>?
    private var loadEpoch: UInt64 = 0

    func tripoRuntime() async throws -> ThreeDGenerationRuntime {
        if RuntimeLaunchContext.isXcodePreview {
            throw ShapERuntimeLoadError.unavailableInPreviews
        }
        if let runtime { return runtime }
        let task: Task<ThreeDGenerationRuntime, Error>
        if let loadTask {
            task = loadTask
        } else {
            loadEpoch &+= 1
            task = Task.detached(priority: .userInitiated) {
                await MLXForegroundGPU.prepare()
                let weightsURL = try await HFBundleDownloader.resolveTripoSRWeights()
                return try ThreeDGenerationRuntime(
                    configuration: .tripoSR(weightsURL: weightsURL)
                )
            }
            loadTask = task
        }
        let epoch = loadEpoch
        do {
            let loaded = try await task.value
            runtime = loaded
            loadTask = nil
            return loaded
        } catch {
            if loadEpoch == epoch { loadTask = nil }
            throw error
        }
    }
}
