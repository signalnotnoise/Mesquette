// ContentViewViewModel+Set.swift
// Mesquette — Split from ContentViewViewModel.swift verbatim (pure code motion).

import SwiftUI
import RealityKit
import MLX3DRuntime
import ShapERuntime
import MLX
#if canImport(UIKit)
import UIKit
#endif

extension ContentViewModel {

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
    func runTextJob(
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
            await GenerationSessionStore.shared.prepareForGPUWork()
            try Task.checkCancellation()
            try await GenerationSessionStore.shared.loadShapE()
            try Task.checkCancellation()

            let guidanceScale  = Float(appModel.guidanceScale)
            let inferenceSteps = appModel.numInferenceSteps
            let gridSize       = appModel.gridSize
            let queryBatch     = appModel.queryBatchSize
            let useMetalMarchingCubes = appModel.usesGPU
            let progressInterval = appModel.enableLivePartials ? 5 : 0
            let applyLivePartials = appModel.enableLivePartials
            let prefix = "\(partTitle) \(setIndex + 1)/\(setCount)"

            let progressHandler: @Sendable (String, Int, Int, [MeshResult]?) -> Void = { [recordIDs] phase, currentStep, totalSteps, partialMeshes in
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
                            meshResults: partials,
                            persistFinal: false
                        )
                    }
                }
            }

            let result = try await withMLXError {
                try await GenerationSessionStore.shared.textMeshes(
                    prompt: promptText,
                    batchSize: 1,
                    guidanceScale: guidanceScale,
                    numInferenceSteps: inferenceSteps,
                    gridSize: gridSize,
                    queryBatchSize: queryBatch,
                    seed: seed,
                    useMetalMarchingCubes: useMetalMarchingCubes,
                    progressInterval: progressInterval,
                    progress: progressHandler
                )
            }

            updateRecords(
                in: appModel,
                ids: recordIDs,
                status: .completed,
                meshResults: result,
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
}
