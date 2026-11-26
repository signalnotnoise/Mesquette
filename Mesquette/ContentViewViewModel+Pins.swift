// ContentViewViewModel+Pins.swift
// Mesquette — Split from ContentViewViewModel.swift verbatim (pure code motion).

import SwiftUI
import RealityKit
import RuntimeWrapper
import ShapERuntime
import MLX
#if canImport(UIKit)
import UIKit
#endif

extension ContentViewModel {

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

}
