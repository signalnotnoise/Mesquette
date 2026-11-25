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

    private var currentPhase: String = ""
    private var currentPhaseStep: Int = -1
    private var generationTask: Task<Void, Never>?

    /// Stop GPU work before iOS backgrounds the scene. IOGPU will kill the
    /// process if a Metal command buffer completes off-screen.
    func cancelInFlightGeneration() {
        generationTask?.cancel()
    }

    private static func planPinsOrFallback(
        client: DirectorClient,
        scene: String,
        empty: [PlacementPin],
        already: [String],
        alreadyIDs: Set<UUID>,
        allPins: [PlacementPin],
        seed: Int,
        extrasBudget: Int
    ) async throws -> (jobs: [PinAssignment], note: String) {
        let tagged = await tagSceneCastOrNil(client: client, scene: scene)
        let cast = DirectorStaging.resolvedCast(scene: scene, tagged: tagged)
        let split = DirectorStaging.namedPinJobs(
            empty: empty,
            allPins: allPins,
            cast: cast,
            already: already,
            seed: seed,
            alreadyIDs: alreadyIDs
        )
        PlacementDebug.log(
            "cast \(cast.objects.map { "\($0.title)(\($0.prefersAirborne ? "air" : "floor"))" }.joined(separator: ", "))"
        )

        var jobs = split.jobs
        var extrasFailed = false
        var extras: [PinAssignment] = []
        let budgeted = extrasBudget <= 0 ? [] : Array(split.extraPins.prefix(extrasBudget))
        if !budgeted.isEmpty {
            do {
                extras = try await planExtraPins(
                    client: client,
                    scene: scene,
                    extraPins: budgeted,
                    already: already + jobs.map(\.title),
                    allPins: allPins,
                    setting: split.setting,
                    seed: seed &+ jobs.count
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                PlacementDebug.log("extra pin plan failed — skip leftovers: \(error)")
                extrasFailed = true
                extras = []
            }
        }
        jobs += extras

        if jobs.isEmpty {
            jobs = DirectorStaging.fallbackPinJobs(
                pins: empty,
                scene: scene,
                seed: seed,
                already: already,
                allPins: allPins
            )
        }

        let named = jobs.filter { $0.route == .named || $0.route == .fallback }.count
        let extraCount = jobs.filter { $0.route == .extra }.count
        let leftover = max(0, empty.count - jobs.count)
        let note = DirectorStaging.summarizePinPlan(
            named: named,
            extras: extraCount,
            leftoverPins: leftover,
            extrasBudget: extrasBudget,
            extrasFailed: extrasFailed || (extrasBudget > 0 && extraCount == 0 && !budgeted.isEmpty)
        )
        return (jobs, note)
    }

    private static func tagSceneCastOrNil(
        client: DirectorClient,
        scene: String
    ) async -> DirectorStaging.TaggedSceneCast? {
        let planTask = Task { @MainActor in
            try await client.tagSceneCast(from: scene)
        }
        let timeoutTask = Task {
            // Hard timeout (documented exception): tagging must never block Generate.
            try await Task.sleep(for: .seconds(25))
            planTask.cancel()
        }
        defer {
            planTask.cancel()
            timeoutTask.cancel()
        }
        do {
            let tagged = try await planTask.value
            if tagged.objects.isEmpty { return nil }
            return tagged
        } catch is CancellationError {
            if Task.isCancelled { return nil }
            PlacementDebug.log("content tag timed out — code cast")
            return nil
        } catch {
            if Task.isCancelled { return nil }
            PlacementDebug.log("content tag failed — code cast: \(error)")
            return nil
        }
    }

    private static func planExtraPins(
        client: DirectorClient,
        scene: String,
        extraPins: [PlacementPin],
        already: [String],
        allPins: [PlacementPin],
        setting: String,
        seed: Int
    ) async throws -> [PinAssignment] {
        let extraIntent = """
        Scene: \(scene)
        Setting: \(setting)
        Already placed: \(already.isEmpty ? "none" : already.joined(separator: ", "))
        Invent complementary objects that belong in THIS scene only. \
        Name each object. Omit a pin rather than write a generic prop. \
        Do not invent trees, forests, mountains, or a new biome.
        """
        let planTask = Task { @MainActor in
            try await client.planPins(
                intent: extraIntent,
                pins: extraPins,
                baseSeed: seed,
                alreadyOnTable: already,
                allPins: allPins,
                mode: .extras
            )
        }
        let timeoutTask = Task {
            // Hard timeout (documented exception): extras are optional dressing.
            try await Task.sleep(for: .seconds(40))
            planTask.cancel()
        }
        defer {
            planTask.cancel()
            timeoutTask.cancel()
        }
        do {
            let extras = try await planTask.value
            return extras
        } catch is CancellationError {
            if Task.isCancelled { throw CancellationError() }
            PlacementDebug.log("extra pin plan timed out — leave leftover pins empty")
            return []
        } catch {
            if Task.isCancelled { throw CancellationError() }
            PlacementDebug.log("extra pin plan failed — leave leftover pins empty: \(error)")
            return []
        }
    }

    private func phaseWeight(_ phase: String) -> Int {
        switch phase {
        case "embedding": return 0
        case "sampling": return 1
        case "projecting": return 2
        // Final extract sub-stages (in order)
        case "volume": return 3
        case "meshing": return 4
        case "colors": return 5
        case "resolving": return 6
        case "extracting": return 3 // legacy single-shot extract
        default: return -1
        }
    }

    private func phaseLabel(_ phase: String, step: Int, total: Int) -> String {
        switch phase {
        case "embedding":
            return "Embedding"
        case "sampling":
            return total > 1 ? "Sampling \(step)/\(total)" : "Sampling"
        case "projecting":
            return "Projecting latent"
        case "volume":
            return total > 1 ? "Volume sample \(step)/\(total)" : "Sampling volume"
        case "meshing":
            return total > 1 ? "Meshing \(step)/\(total)" : "Building mesh"
        case "colors":
            return total > 1 ? "Vertex colors \(step)/\(total)" : "Vertex colors"
        case "resolving":
            return "Finalizing geometry"
        case "extracting":
            return "Extracting mesh"
        default:
            return "Generating"
        }
    }

    /// Maps phase + step into a monotonic-ish 0…1 overall progress for the UI bar.
    ///
    /// Spans: embed 0–5%, sample 5–70%, project 70–75%,
    /// volume 75–90%, meshing 90–93%, colors 93–98%, resolve 98–100%.
    private func overallProgress(phase: String, currentStep: Int, totalSteps: Int) -> Double {
        let safeTotal = max(totalSteps, 1)
        let local = min(1.0, max(0.0, Double(currentStep) / Double(safeTotal)))
        switch phase {
        case "embedding":
            return 0.05 * local
        case "sampling":
            return 0.05 + 0.65 * local
        case "projecting":
            return 0.70 + 0.05 * local
        case "volume":
            return 0.75 + 0.15 * local
        case "meshing":
            return 0.90 + 0.03 * local
        case "colors":
            return 0.93 + 0.05 * local
        case "resolving":
            return 0.98 + 0.02 * local
        case "extracting":
            return 0.75 + 0.25 * local
        default:
            return appProgressFloor(for: phase)
        }
    }

    private func appProgressFloor(for phase: String) -> Double {
        switch phaseWeight(phase) {
        case 0: return 0.0
        case 1: return 0.05
        case 2: return 0.70
        case 3: return 0.75
        case 4: return 0.90
        case 5: return 0.93
        case 6: return 0.98
        default: return 0.0
        }
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

    /// One Shap-E object per empty pin. Filled pins keep their mesh.
    func generateAtPins(appModel: AppModel) {
        guard generationTask == nil, !appModel.isDirectorBusy else { return }
        guard appModel.inputMode == .text,
              !appModel.emptyPlacementPins.isEmpty,
              !appModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        let empty = Array(appModel.emptyPlacementPins.prefix(PlacementPin.maxCount))
        let allPins = appModel.placementPins
        let already = appModel.identityKeysOnTable
        let scene = appModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedPrompt = appModel.prompt
        let savedBatch = appModel.batchSize
        let savedSeed = appModel.seed
        let client = DirectorClient()

        generationTask = Task { @MainActor in
            defer {
                appModel.isGenerating = false
                generationTask = nil
                appModel.prompt = savedPrompt
                appModel.batchSize = savedBatch
                appModel.seed = savedSeed
#if os(iOS)
                UIApplication.shared.isIdleTimerDisabled = false
#endif
            }

#if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = true
            guard UIApplication.shared.applicationState == .active else { return }
#endif

            appModel.isGenerating = true
            appModel.progress = 0.02
            appModel.progressPhaseLabel = "Planning \(empty.count) empty pin\(empty.count == 1 ? "" : "s")…"
            appModel.pinPlanNote = nil
            await Task.yield()

            let assignments: [PinAssignment]
            var planNote = ""
            do {
                let planned = try await Self.planPinsOrFallback(
                    client: client,
                    scene: scene,
                    empty: empty,
                    already: already,
                    alreadyIDs: appModel.inventoryIDsOnTable,
                    allPins: allPins,
                    seed: savedSeed,
                    extrasBudget: appModel.clampedPinExtrasBudget
                )
                assignments = planned.jobs
                planNote = planned.note
                appModel.directorError = nil
            } catch is CancellationError {
                appModel.progressPhaseLabel = ""
                return
            } catch {
                if Task.isCancelled {
                    appModel.progressPhaseLabel = ""
                    return
                }
                PlacementDebug.log("planPins failed, fallback: \(error)")
                assignments = DirectorStaging.fallbackPinJobs(
                    pins: empty,
                    scene: scene,
                    seed: savedSeed,
                    already: already,
                    allPins: allPins
                )
                planNote = DirectorStaging.summarizePinPlan(
                    named: assignments.count,
                    extras: 0,
                    leftoverPins: max(0, empty.count - assignments.count),
                    extrasBudget: appModel.clampedPinExtrasBudget,
                    extrasFailed: true
                )
            }
            appModel.pinPlanNote = planNote.isEmpty ? nil : planNote

            let setID = UUID()
            var setFailed = false
            let livePins = appModel.placementPins
            let pinByID = Dictionary(uniqueKeysWithValues: livePins.map { ($0.id, $0) })

            for (i, job) in assignments.enumerated() {
                if Task.isCancelled { break }
                let pin = pinByID[job.pinID]
                    ?? appModel.placementPins.first(where: { $0.id == job.pinID })
                    ?? empty[min(i, empty.count - 1)]
                appModel.batchSize = 1
                appModel.seed = job.seed
                PlacementDebug.log(
                    String(
                        format: "job %d/%d %@ '%@' pin=(%.2f, %.2f, %.2f) scale=%@",
                        i + 1,
                        assignments.count,
                        job.route.rawValue,
                        String(job.title.prefix(32)),
                        pin.x, pin.y, pin.z,
                        job.scale.rawValue
                    )
                )
                let failed = await runTextJob(
                    appModel: appModel,
                    promptText: job.shapEPrompt,
                    seed: job.seed,
                    offsetX: pin.x,
                    offsetY: pin.y,
                    offsetZ: pin.z,
                    rotationY: 0,
                    placementScale: job.scale.placementScale,
                    slot: .heroCenter,
                    setID: setID,
                    setIndex: i,
                    setCount: assignments.count,
                    setTitle: scene,
                    partTitle: job.title,
                    fillsToNeighbors: false,
                    suggestedScale: job.scale.rawValue,
                    pinID: pin.id,
                    inventoryID: job.inventoryID,
                    planRoute: job.route
                )
                if failed {
                    setFailed = true
                    break
                }
            }

            if appModel.isGenerating {
                appModel.isGenerating = false
                if Task.isCancelled {
                    appModel.progressPhaseLabel = ""
                } else if setFailed {
                    appModel.progressPhaseLabel = "Failed"
                } else {
                    appModel.progressPhaseLabel = planNote.isEmpty ? "Done" : planNote
                }
            }
        }
    }

    /// Throw away the mesh on this pin and sculpt the same prompt with a new seed.
    func retryPin(id pinID: UUID, appModel: AppModel) {
        guard generationTask == nil, !appModel.isDirectorBusy else { return }
        guard let pin = appModel.placementPins.first(where: { $0.id == pinID }),
              let recID = pin.recordID,
              let rec = appModel.generationDict[recID],
              rec.latestMesh != nil
        else { return }

        let prompt = rec.prompt
        let scale = DirectorScale(rawValue: rec.suggestedScale ?? "") ?? .tabletop
        let placementScale = rec.placementScale ?? scale.placementScale
        let fills = rec.fillsToNeighbors
        let title = rec.partTitle ?? rec.prompt
        let seed = (rec.params?.seed ?? appModel.seed) &+ 17
        let scene = rec.setTitle ?? appModel.prompt
        let setID = rec.setID ?? UUID()
        let savedPrompt = appModel.prompt
        let savedBatch = appModel.batchSize
        let savedSeed = appModel.seed

        appModel.removeGeneration(id: recID)

        generationTask = Task { @MainActor in
            defer {
                appModel.isGenerating = false
                generationTask = nil
                appModel.prompt = savedPrompt
                appModel.batchSize = savedBatch
                appModel.seed = savedSeed
            }
            appModel.isGenerating = true
            appModel.progress = 0.02
            appModel.progressPhaseLabel = "Retry \(title)…"
            let live = appModel.placementPins.first(where: { $0.id == pinID }) ?? pin
            let failed = await runTextJob(
                appModel: appModel,
                promptText: prompt,
                seed: seed,
                offsetX: live.x,
                offsetY: live.y,
                offsetZ: live.z,
                rotationY: 0,
                placementScale: placementScale,
                slot: rec.slot ?? .heroCenter,
                setID: setID,
                setIndex: rec.setIndex ?? 0,
                setCount: 1,
                setTitle: scene,
                partTitle: title,
                fillsToNeighbors: fills,
                suggestedScale: rec.suggestedScale ?? scale.rawValue,
                pinID: pinID,
                inventoryID: rec.inventoryID,
                planRoute: rec.planRoute
            )
            if appModel.isGenerating {
                appModel.isGenerating = false
                appModel.progressPhaseLabel = failed ? "Failed" : "Done"
            }
        }
    }

    /// Sequential Shap-E runs for a directed set. One object per part, laid out by offset.
    func generateMeshSet(appModel: AppModel) {
        guard generationTask == nil, !appModel.isDirectorBusy else { return }
        guard appModel.inputMode == .text,
              let compiled = appModel.lastCompilation?.normalized(),
              compiled.kind == .set,
              compiled.parts.count >= 2 else { return }

        let parts = DirectorLayoutEngine.applyPins(
            appModel.placementPins,
            to: compiled.parts,
            layout: compiled.layout
        )
        let setID = UUID()
        let setTitle = compiled.title
        let savedPrompt = appModel.prompt
        let savedBatch = appModel.batchSize
        let savedSeed = appModel.seed

        generationTask = Task { @MainActor in
            defer {
                appModel.isGenerating = false
                generationTask = nil
                appModel.prompt = savedPrompt
                appModel.batchSize = savedBatch
                appModel.seed = savedSeed
#if os(iOS)
                UIApplication.shared.isIdleTimerDisabled = false
#endif
            }

#if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = true
            guard UIApplication.shared.applicationState == .active else { return }
#endif

            appModel.isGenerating = true
            var setFailed = false

            for (i, part) in parts.enumerated() {
                if Task.isCancelled { break }
                appModel.batchSize = 1
                appModel.seed = savedSeed &+ i
                let pinY = i < appModel.placementPins.count ? appModel.placementPins[i].y : 0
                let failed = await runTextJob(
                    appModel: appModel,
                    promptText: part.shapEPrompt,
                    seed: savedSeed &+ i,
                    offsetX: part.offsetX,
                    offsetY: pinY,
                    offsetZ: part.offsetZ,
                    rotationY: 0,
                    placementScale: part.placementScale,
                    slot: part.slot,
                    setID: setID,
                    setIndex: i,
                    setCount: parts.count,
                    setTitle: setTitle,
                    partTitle: part.title,
                    fillsToNeighbors: false,
                    suggestedScale: part.scale.rawValue
                )
                if failed {
                    setFailed = true
                    break
                }
            }

            if appModel.isGenerating {
                appModel.isGenerating = false
                if Task.isCancelled {
                    appModel.progressPhaseLabel = ""
                } else if setFailed {
                    appModel.progressPhaseLabel = "Failed"
                } else {
                    appModel.progressPhaseLabel = "Done"
                }
            }
        }
    }

    /// Returns `true` if the job failed or was cancelled.
    private func runTextJob(
        appModel: AppModel,
        promptText: String,
        seed: Int,
        offsetX: Float,
        offsetY: Float = 0,
        offsetZ: Float,
        rotationY: Float,
        placementScale: Float,
        slot: DirectorSlot,
        setID: UUID,
        setIndex: Int,
        setCount: Int,
        setTitle: String,
        partTitle: String,
        fillsToNeighbors: Bool = false,
        suggestedScale: String? = nil,
        pinID: UUID? = nil,
        inventoryID: UUID? = nil,
        planRoute: PinPlanRoute? = nil
    ) async -> Bool {
        let baseParams = appModel.currentParamsSnapshot()
        var itemParams = baseParams
        itemParams.seed = seed
        itemParams.batchSize = 1
        let stamp = DirectorSession.stamp(
            forPrompt: promptText,
            appModel: appModel,
            setID: setID,
            setIndex: setIndex,
            setTitle: setTitle
        )
        let record = GenerationRecord(
            prompt: promptText,
            params: itemParams,
            userIntent: stamp.userIntent,
            compiledPrompt: stamp.compiledPrompt,
            directorRationale: stamp.directorRationale,
            suggestedScale: suggestedScale ?? stamp.suggestedScale,
            suggestedMaterial: stamp.suggestedMaterial,
            setID: setID,
            setIndex: setIndex,
            setTitle: setTitle,
            offsetX: offsetX,
            offsetY: offsetY,
            offsetZ: offsetZ,
            rotationY: rotationY,
            placementScale: placementScale,
            slot: slot,
            fillsToNeighbors: fillsToNeighbors,
            pinID: pinID,
            partTitle: partTitle,
            inventoryID: inventoryID,
            planRoute: planRoute
        )
        let recordIDs = [record.id]
        appModel.generationDict[record.id] = record
        appModel.generationOrder.append(record.id)
        if let pinID {
            appModel.bindPin(pinID, to: record.id)
        }

        appModel.progress = 0.02
        appModel.progressPhaseLabel = "\(partTitle) \(setIndex + 1)/\(setCount) · Loading…"
        currentPhase = ""
        currentPhaseStep = -1
        await Task.yield()

        do {
            try Task.checkCancellation()
            await ShapERuntimeStore.shared.prepareForGPUWork()
            try Task.checkCancellation()
            let runtime = try await ShapERuntimeStore.shared.runtime()
            try Task.checkCancellation()

            let guidanceScale  = Float(appModel.guidanceScale)
            let inferenceSteps = appModel.numInferenceSteps
            let gridSize       = appModel.gridSize
            let queryBatch     = appModel.queryBatchSize
            let useMetalMarchingCubes = appModel.usesGPU
            let progressInterval = appModel.enableLivePartials ? 5 : 0
            let applyLivePartials = appModel.enableLivePartials
            let prefix = "\(partTitle) \(setIndex + 1)/\(setCount)"

            let progressHandler: @Sendable (String, Int, Int, [ShapEMeshResult]?) -> Void = { [recordIDs] phase, currentStep, totalSteps, partialMeshes in
                Task { @MainActor in
                    let resolvedPhase = phase.isEmpty ? "sampling" : phase
                    let weight = self.phaseWeight(resolvedPhase)
                    let currentWeight = self.phaseWeight(self.currentPhase)
                    if weight < currentWeight { return }
                    if weight == currentWeight && currentStep < self.currentPhaseStep { return }
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
                    appModel.progress = max(appModel.progress, overall)
                    appModel.progressPhaseLabel = "\(prefix) · " + self.phaseLabel(
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

            let result = try await withMLXError {
                try await runtime.generate(
                    prompt:            promptText,
                    batchSize:         1,
                    guidanceScale:     guidanceScale,
                    numInferenceSteps: inferenceSteps,
                    gridSize:          gridSize,
                    queryBatchSize:    queryBatch,
                    seed:              seed,
                    useMetalMarchingCubes: useMetalMarchingCubes,
                    progressInterval:  progressInterval,
                    progress:          progressHandler
                )
            }

            updateRecords(
                in: appModel,
                ids: recordIDs,
                status: .completed,
                meshResults: result.map(\.meshResult),
                persistFinal: true
            )
            return false
        } catch is CancellationError {
            updateRecords(
                in: appModel,
                ids: recordIDs,
                status: .failed("Stopped — keep Mesquette on screen while generating.")
            )
            return true
        } catch {
            updateRecords(
                in: appModel,
                ids: recordIDs,
                status: .failed(error.localizedDescription)
            )
            return true
        }
    }

    private func updateRecords(
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
    private func withMLXError<R: Sendable>(
        _ body: @Sendable @escaping () async throws -> R
    ) async throws -> R {
        try await withError(body)
    }
}
