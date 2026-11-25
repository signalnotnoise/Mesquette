import SwiftUI
import RealityKit
import RuntimeWrapper
import ShapERuntime
import MLX
import os
#if canImport(UIKit)
import UIKit
#endif

@Observable
@MainActor
class ContentViewModel {

    var currentPhase: String = ""
    var currentPhaseStep: Int = -1
    var generationTask: Task<Void, Never>?

    /// Stop GPU work before iOS backgrounds the scene. IOGPU will kill the
    /// process if a Metal command buffer completes off-screen.
    func cancelInFlightGeneration() {
        generationTask?.cancel()
    }


    func generateMesh(appModel: AppModel) {
        guard generationTask == nil, !appModel.isCompiling, !appModel.isInventing else { return }
        generationTask = Task { @MainActor in
            defer {
                generationTask = nil
#if os(iOS)
                UIApplication.shared.isIdleTimerDisabled = false
#endif
            }

#if os(iOS)
            // A long extract will lock the phone otherwise, then IOGPU
            // terminates on the next Metal completion callback.
            UIApplication.shared.isIdleTimerDisabled = true
            guard UIApplication.shared.applicationState == .active else {
                return
            }
#endif

            // Do not cap MLX cache at 32 MB or clearCache() on every run:
            // the transformer is multi-GB, so a tiny cache thrashes and
            // clearing it forces a cold Metal compile on the next Generate.

            // Add history records immediately so the chat panel shows them.
            // Each batch item gets a unique seed: base, base+1, … (matches KarrasSampler).
            let promptText = appModel.inputMode == .image ? "Image to 3D Generation" : appModel.prompt
            let batchSize = appModel.batchSize
            let baseParams = appModel.currentParamsSnapshot()
            let stamp = DirectorSession.stamp(
                forPrompt: promptText,
                appModel: appModel,
                setID: nil,
                setIndex: nil,
                setTitle: nil
            )
            let records: [GenerationRecord] = (0..<batchSize).map { i in
                let suffix = batchSize > 1 ? " (\(i + 1))" : ""
                var itemParams = baseParams
                itemParams.seed = baseParams.seed &+ i
                return GenerationRecord(
                    prompt: promptText + suffix,
                    params: itemParams,
                    userIntent: stamp.userIntent,
                    compiledPrompt: stamp.compiledPrompt,
                    directorRationale: stamp.directorRationale,
                    suggestedScale: stamp.suggestedScale,
                    suggestedMaterial: stamp.suggestedMaterial
                )
            }
            let recordIDs = records.map(\.id)
            for record in records {
                appModel.generationDict[record.id] = record
                appModel.generationOrder.append(record.id)
            }

            appModel.isGenerating = true
            appModel.progress = 0.02
            appModel.progressPhaseLabel = "Loading model…"

            self.currentPhase = ""
            self.currentPhaseStep = -1

            // Let SwiftUI paint the progress UI before we await model load / generate.
            await Task.yield()

            do {
                try Task.checkCancellation()
                // `generate` is @concurrent (off the main actor). IOGPU requires the
                // Metal/MLX stream to be created while the app is in the foreground.
                await ShapERuntimeStore.shared.prepareForGPUWork()
                try Task.checkCancellation()
                let generationModel = appModel.generationModel
                // Shap-E keeps the full-fidelity direct runtime; TripoSR goes
                // through the RuntimeWrapper facade (ThreeDGenerationRuntime).
                let runtime: ShapERuntime? = generationModel == .shapE
                    ? try await ShapERuntimeStore.shared.runtime() : nil
                try Task.checkCancellation()

                let prompt         = appModel.prompt
                let batchSize      = appModel.batchSize
                let guidanceScale  = Float(appModel.guidanceScale)
                let inferenceSteps = appModel.numInferenceSteps
                let gridSize       = appModel.gridSize
                let queryBatch     = appModel.queryBatchSize
                let seed           = appModel.seed
                let useMetalMarchingCubes = appModel.usesGPU
                // Progress interval for partial mesh extracts. 0 = never extract partials
                // (still reports sampling step progress without unscaled latents).
                let progressInterval = appModel.enableLivePartials ? 5 : 0
                let applyLivePartials = appModel.enableLivePartials
                let meshResults: [MeshResult]

                // @Sendable so this can cross into MLX `withError` (which is @concurrent).
                // UI updates hop back to the main actor inside the Task.
                let progressHandler: @Sendable (String, Int, Int, [ShapEMeshResult]?) -> Void = { [recordIDs] phase, currentStep, totalSteps, partialMeshes in
                    Task { @MainActor in
                        // Normalize empty phase (runtime used "" for non-partial ticks) to sampling.
                        let resolvedPhase = phase.isEmpty ? "sampling" : phase
                        let weight = self.phaseWeight(resolvedPhase)
                        let currentWeight = self.phaseWeight(self.currentPhase)

                        if weight < currentWeight { return }
                        // Allow step to advance within a phase; ignore stale/out-of-order steps.
                        if weight == currentWeight && currentStep < self.currentPhaseStep { return }
                        // Same step can still update the label on first sighting only once.
                        if weight == currentWeight
                            && currentStep == self.currentPhaseStep
                            && resolvedPhase == self.currentPhase {
                            return
                        }

                        self.currentPhase = resolvedPhase
                        self.currentPhaseStep = currentStep

                        let overall = self.overallProgress(
                            phase: resolvedPhase,
                            currentStep: currentStep,
                            totalSteps: totalSteps
                        )
                        // Never let the bar go backwards mid-run.
                        appModel.progress = max(appModel.progress, overall)
                        appModel.progressPhaseLabel = self.phaseLabel(
                            resolvedPhase,
                            step: currentStep,
                            total: totalSteps
                        )

                        if applyLivePartials,
                           let partials = partialMeshes,
                           !partials.isEmpty {
                            self.updateRecords(
                                in: appModel,
                                ids: recordIDs,
                                status: .generating,
                                meshResults: partials.map(\.meshResult),
                                persistFinal: false
                            )
                        }
                    }
                }

                if appModel.inputMode == .image {
                    appModel.progressPhaseLabel = generationModel == .tripoSR
                        ? "Loading TripoSR model…" : "Downloading image model…"
                    if generationModel == .shapE {
                        try await ShapERuntimeStore.shared.prepareImageWeights()
                    }
#if os(macOS)
                    guard let img = appModel.inputImage, let cgImage = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                        appModel.isGenerating = false
                        appModel.progressPhaseLabel = ""
                        updateRecords(in: appModel, ids: recordIDs, status: .failed("No valid image provided"))
                        return
                    }
#else
                    guard let img = appModel.inputImage, let cgImage = img.cgImage else {
                        appModel.isGenerating = false
                        appModel.progressPhaseLabel = ""
                        updateRecords(in: appModel, ids: recordIDs, status: .failed("No valid image provided"))
                        return
                    }
#endif

                    if generationModel == .tripoSR {
                        // TripoSR reconstructs density from the silhouette, so
                        // it needs the upstream contract: alpha cutout cropped
                        // to the foreground (the app's white composite for
                        // Shap-E would be meshed as a white slab).
                        appModel.progressPhaseLabel = "Preparing image…"
                        let preparedImage: CGImage?
                        do {
                            preparedImage = try await ImageBackgroundRemoval.foregroundCutout(from: cgImage)
                            if preparedImage == nil {
                                Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.visionarydevops.Mesquette", category: "image").error("Foreground cutout returned nil; TripoSR will use the unprepared image")
                            }
                        } catch {
                            Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.visionarydevops.Mesquette", category: "image").error("Foreground cutout failed, using unprepared image: \(error.localizedDescription, privacy: .public)")
                            preparedImage = nil
                        }
                        let tripo = try await TripoSRStore.shared.tripoRuntime()
                        meshResults = try await withMLXError {
                            try await tripo.generate(
                                image: preparedImage ?? cgImage,
                                useMetalMarchingCubes: useMetalMarchingCubes,
                                progress: progressHandler
                            ).map(\.meshResult)
                        }
                    } else if let runtime {
                        meshResults = try await withMLXError {
                            try await runtime.generate(
                                image:             cgImage,
                                batchSize:         batchSize,
                                guidanceScale:     guidanceScale,
                                numInferenceSteps: inferenceSteps,
                                gridSize:          gridSize,
                                queryBatchSize:    queryBatch,
                                seed:              seed,
                                useMetalMarchingCubes: useMetalMarchingCubes,
                                progressInterval:  progressInterval,
                                progress:          progressHandler
                            )
                        }.map(\.meshResult)
                    } else {
                        throw ShapERuntimeLoadError.bundleNotFound
                    }
                } else if let runtime {
                    meshResults = try await withMLXError {
                        try await runtime.generate(
                            prompt:            prompt,
                            batchSize:         batchSize,
                            guidanceScale:     guidanceScale,
                            numInferenceSteps: inferenceSteps,
                            gridSize:          gridSize,
                            queryBatchSize:    queryBatch,
                            seed:              seed,
                            useMetalMarchingCubes: useMetalMarchingCubes,
                            progressInterval:  progressInterval,
                            progress:          progressHandler
                        )
                    }.map(\.meshResult)
                } else {
                    // TripoSR has no text path; the picker forces image mode,
                    // so this is unreachable unless state was restored oddly.
                    throw ThreeDGenerationRuntimeError.promptUnsupported(.tripoSR)
                }

                appModel.progress = 0.98
                appModel.progressPhaseLabel = "Finishing…"

                // Store final MeshResult (used by previews / export).
                updateRecords(
                    in: appModel,
                    ids: recordIDs,
                    status: .completed,
                    meshResults: meshResults,
                    persistFinal: true
                )

                appModel.progress = 1.0
                appModel.progressPhaseLabel = "Done"
                appModel.isGenerating = false

            } catch is CancellationError {
                appModel.isGenerating = false
                appModel.progress = 0.0
                appModel.progressPhaseLabel = ""
                updateRecords(
                    in: appModel,
                    ids: recordIDs,
                    status: .failed("Stopped — keep Mesquette on screen while generating. iOS cannot run GPU work in the background.")
                )
            } catch ShapERuntimeError.gpuNotForeground {
                appModel.isGenerating = false
                appModel.progress = 0.0
                appModel.progressPhaseLabel = ""
                updateRecords(
                    in: appModel,
                    ids: recordIDs,
                    status: .failed(ShapERuntimeError.gpuNotForeground.localizedDescription)
                )
            } catch {
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.visionarydevops.Mesquette", category: "generate")
                    .error("Failed to generate: \(error.localizedDescription, privacy: .public)")
                appModel.isGenerating = false
                appModel.progress = 0.0
                appModel.progressPhaseLabel = ""
                updateRecords(in: appModel, ids: recordIDs, status: .failed(error.localizedDescription))
            }
        }
    }


    func updateRecords(
        in appModel: AppModel,
        ids: [UUID],
        status: GenerationRecord.Status,
        meshResults: [MeshResult]? = nil,
        persistFinal: Bool = false
    ) {
        for (i, id) in ids.enumerated() {
            guard var record = appModel.generationDict[id] else { continue }
            record.status = status

            if let results = meshResults, i < results.count {
                let mesh = results[i]
                record.latestMesh = mesh
                // Partials have tiny AABBs and would over-scale; wait for the final mesh.
                if persistFinal {
                    if let raw = record.suggestedScale,
                       let scale = DirectorScale(rawValue: raw),
                       let fit = DirectorLayoutEngine.fit(
                        mesh: mesh,
                        scale: scale,
                        worldScale: DirectorLayoutEngine.pinWorldScale(appModel.placementPins)
                       ) {
                        PlacementDebug.log(
                            String(
                                format: "fit '%@' suggested=%@ → scale=%.3f radius=%.3f",
                                String(record.prompt.prefix(40)),
                                raw,
                                fit.scale,
                                fit.radius
                            )
                        )
                        record.placementScale = fit.scale
                        record.footprintRadius = fit.radius
                    } else {
                        PlacementDebug.log(
                            "fit FAILED '\(record.prompt.prefix(40))' suggested=\(record.suggestedScale ?? "nil") keepScale=\(record.placementScale ?? -1)"
                        )
                    }
                }

                // Only persist the **final** mesh to disk (not every partial).
                if persistFinal {
                    let fileName = "\(id.uuidString)_final.plist"
                    let fileURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(fileName)
                    record.finalMeshURL = fileURL

                    Task.detached(priority: .utility) {
                        // Best-effort sidecar for reuse; the record itself is the source of truth.
                        if let data = try? PropertyListEncoder().encode(mesh) {
                            try? data.write(to: fileURL)
                        }
                    }
                }
            }

            appModel.generationDict[id] = record
            if case .failed = status, let pinID = record.pinID {
                appModel.unbindPin(pinID, belongingTo: id)
            }
        }

        if let setID = ids.compactMap({ appModel.generationDict[$0]?.setID }).first {
            refitSet(setID, in: appModel)
        }
    }

    private func refitSet(_ setID: UUID, in appModel: AppModel) {
        var members = appModel.generationOrder.compactMap { id -> GenerationRecord? in
            guard let rec = appModel.generationDict[id], rec.setID == setID else { return nil }
            return rec
        }
        guard members.count >= 2 else { return }
        let layout = appModel.lastCompilation?.layout ?? .cluster
        let pins = appModel.placementPins
        if !pins.isEmpty {
            // Pins are anchors. Do not expand fills — that is what ballooned the fir (0.17 → 2.3).
            DirectorLayoutEngine.packRecords(&members, layout: layout, pins: pins)
        } else if members.contains(where: \.fillsToNeighbors) {
            DirectorLayoutEngine.expandFills(&members)
        } else {
            DirectorLayoutEngine.packRecords(&members, layout: layout)
        }
        for rec in members {
            appModel.generationDict[rec.id] = rec
        }
    }

    /// MLX `withError` is a `@concurrent` global. A MainActor-isolated async
    /// closure is not Sendable, so generation must be passed as `@Sendable`.
    func withMLXError<R: Sendable>(
        _ body: @Sendable @escaping () async throws -> R
    ) async throws -> R {
        try await withError(body)
    }
}
