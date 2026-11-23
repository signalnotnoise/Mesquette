//
//  AppModel.swift
//  Mesquette
//
//  Created by Alexander Otero on 4/13/26.
//

import SwiftUI
import RealityKit
import RuntimeWrapper
import ShapERuntime

/// Maintains app-wide state shared across both platforms.
@MainActor
@Observable
class AppModel {

    // MARK: - Generation UI state (shared)
    enum InputMode: Hashable, Sendable { case text, image }

    /// Selected generation backend. TripoSR is image-to-3D only, so picking
    /// it forces image input; text/pin flows stay on Shap-E. Persisted.
    var generationModel: ThreeDGenerationModel =
        ThreeDGenerationModel(rawValue: UserDefaults.standard.string(forKey: "Mesquette.generationModel") ?? "") ?? .shapE {
        didSet {
            UserDefaults.standard.set(generationModel.rawValue, forKey: "Mesquette.generationModel")
            if generationModel == .tripoSR, inputMode == .text {
                inputMode = .image
            }
        }
    }
    var inputMode: InputMode = .text {
        didSet {
            // Adjust default guidance scale based on the selected mode
            if inputMode == .image && guidanceScale == 15.0 {
                guidanceScale = 3.0
            } else if inputMode == .text && guidanceScale == 3.0 {
                guidanceScale = 15.0
            }
        }
    }
    var prompt: String = ""
#if os(macOS)
    var inputImage: NSImage? = nil
#else
    var inputImage: UIImage? = nil
#endif
    var isProcessingImage: Bool = false
    var showImagePreview: Bool = false
    var isGenerating: Bool = false
    /// Overall 0…1 progress across generation phases.
    var progress: Double = 0.0
    /// Human-readable phase for the progress UI (e.g. "Sampling", "Extracting").
    var progressPhaseLabel: String = ""

    // MARK: - Generation history (shared — drives macOS chat panel)
    var generationDict: [UUID: GenerationRecord] = [:]
    var generationOrder: [UUID] = []
    
    var generationHistory: [GenerationRecord] {
        generationOrder.compactMap { generationDict[$0] }
    }

    // MARK: - Quality preset
    /// Applying a preset updates steps, grid, partials, and GPU defaults.
    var qualityPreset: QualityPreset = .standard {
        didSet { applyQualityPreset(qualityPreset) }
    }

    // MARK: - ShapERuntime parameters (shared)
    var batchSize: Int          = 1
    var guidanceScale: Double   = 15.0
    var numInferenceSteps: Int  = QualityPreset.standard.numInferenceSteps
    var gridSize: Int           = QualityPreset.standard.gridSize
    
#if os(macOS)
    var queryBatchSize: Int     = 4096
#else
    var queryBatchSize: Int     = 1024
#endif
    /// Fixed seed for reproducibility. Use the Random control to vary.
    var seed: Int               = 0
    /// Metal marching cubes for the **final** mesh extract.
    var usesGPU: Bool           = QualityPreset.standard.usesGPUForFinalExtract
    /// When true, intermediate meshes are extracted during sampling (expensive; can GPU-hang).
    var enableLivePartials: Bool = false

    // MARK: - Viewport Shading Mode
    enum ShadingMode: String, CaseIterable, Sendable {
        case smooth = "Smooth"
        case flat = "Flat"
        case wireframe = "Wireframe"
    }
    var shadingMode: ShadingMode = .smooth

    var shadingModeIndex: Int {
        ShadingMode.allCases.firstIndex(of: shadingMode) ?? 0
    }

    // MARK: - Director (on-device Foundation Models)
    var isCompiling: Bool = false
    var isInventing: Bool = false
    /// Bumped at the start of each compile/invent so a late result cannot apply over a newer request.
    var compileGeneration: UInt64 = 0
    var directorIntent: String?
    var lastCompilation: CompiledPrompt?
    var directorError: String?
    /// Persistent note after Generate at pins (skipped extras, leftover pins).
    var pinPlanNote: String?
    /// How many leftover empty pins may receive invented dressing. 0 = named objects only.
    var pinExtrasBudget: Int = 0

    /// Empty pins that remain after placing named objects from the current prompt.
    var extraPropsCapacity: Int {
        leftoverEmptyPinsAfterNamedCast.count
    }

    var clampedPinExtrasBudget: Int {
        min(max(0, pinExtrasBudget), extraPropsCapacity)
    }

    var leftoverEmptyPinsAfterNamedCast: [PlacementPin] {
        let empty = emptyPlacementPins
        let scene = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !empty.isEmpty, !scene.isEmpty else { return empty }
        let cast = DirectorStaging.resolvedCast(scene: scene, tagged: nil)
        let split = DirectorStaging.namedPinJobs(
            empty: empty,
            allPins: placementPins,
            cast: cast,
            already: identityKeysOnTable,
            seed: 0,
            alreadyIDs: inventoryIDsOnTable
        )
        return split.extraPins
    }
    var selectedPartID: UUID?
    var directorAvailability: DirectorAvailability = .checking
    /// Scene briefs the on-device director invented this session.
    var inventedPresets: [PromptPreset] = []
    /// User-clicked table points. Generate as set binds parts to these in order.
    var placementPins: [PlacementPin] = []

    var usesPlacementPins: Bool { !placementPins.isEmpty }

    func pinFillState(_ pin: PlacementPin) -> PinFillState {
        guard let recordID = pin.recordID, let rec = generationDict[recordID] else {
            return .empty
        }
        switch rec.status {
        case .generating:
            // A leftover in-flight record must not block Generate after a stuck run.
            return isGenerating ? .busy : .empty
        case .completed where rec.latestMesh != nil:
            return .filled
        default:
            return .empty
        }
    }

    var emptyPlacementPins: [PlacementPin] {
        placementPins.filter { pinFillState($0) == .empty }
    }

    /// Titles already sculpted on filled pins, in pin order.
    var titlesOnTable: [String] {
        filledPinRecords.compactMap { rec in
            let title = rec.partTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !title.isEmpty { return title }
            let prompt = rec.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            return prompt.isEmpty ? nil : prompt
        }
    }

    var inventoryIDsOnTable: Set<UUID> {
        Set(filledPinRecords.compactMap(\.inventoryID))
    }

    /// Full object phrases on filled pins, for conservative duplicate detection.
    var identityKeysOnTable: [String] {
        filledPinRecords.compactMap { rec in
            let prompt = rec.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !prompt.isEmpty { return prompt }
            let title = rec.partTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return title.isEmpty ? nil : title
        }
    }

    private var filledPinRecords: [GenerationRecord] {
        placementPins.compactMap { pin in
            guard pinFillState(pin) == .filled,
                  let rec = pin.recordID.flatMap({ generationDict[$0] }) else { return nil }
            return rec
        }
    }

    func bindPin(_ pinID: UUID, to recordID: UUID) {
        guard let i = placementPins.firstIndex(where: { $0.id == pinID }) else { return }

        if let previousRecordID = placementPins[i].recordID, previousRecordID != recordID {
            clearRecordPinID(previousRecordID, matching: pinID)
        }
        if let rec = generationDict[recordID], let oldPinID = rec.pinID, oldPinID != pinID {
            if let j = placementPins.firstIndex(where: { $0.id == oldPinID }),
               placementPins[j].recordID == recordID {
                placementPins[j].recordID = nil
            }
        }

        placementPins[i].recordID = recordID
        if var rec = generationDict[recordID] {
            rec.pinID = pinID
            generationDict[recordID] = rec
        }
    }

    /// Clears the pin, and the record that currently owns it. Pass `recordID`
    /// to no-op when the pin has already been given to a newer generation.
    func unbindPin(_ pinID: UUID, belongingTo recordID: UUID? = nil) {
        guard let i = placementPins.firstIndex(where: { $0.id == pinID }) else { return }
        if let recordID, placementPins[i].recordID != recordID {
            clearRecordPinID(recordID, matching: pinID)
            return
        }
        if let boundID = placementPins[i].recordID {
            clearRecordPinID(boundID, matching: pinID)
        }
        placementPins[i].recordID = nil
    }

    func removeGeneration(id: UUID) {
        if let rec = generationDict[id], let pinID = rec.pinID {
            unbindPin(pinID, belongingTo: id)
        }
        if let i = placementPins.firstIndex(where: { $0.recordID == id }) {
            unbindPin(placementPins[i].id, belongingTo: id)
        }
        generationDict.removeValue(forKey: id)
        generationOrder.removeAll { $0 == id }
    }

    private func clearRecordPinID(_ recordID: UUID, matching pinID: UUID) {
        guard var rec = generationDict[recordID], rec.pinID == pinID else { return }
        rec.pinID = nil
        generationDict[recordID] = rec
    }

    func addPlacementPin(x: Float, y: Float = 0, z: Float) {
        guard placementPins.count < PlacementPin.maxCount else { return }
        placementPins.append(PlacementPin(x: x, y: y, z: z))
    }

    func removePlacementPin(id: UUID) {
        placementPins.removeAll { $0.id == id }
    }

    func movePlacementPin(id: UUID, x: Float? = nil, y: Float? = nil, z: Float? = nil) {
        guard let i = placementPins.firstIndex(where: { $0.id == id }) else { return }
        if let x { placementPins[i].x = x }
        if let y { placementPins[i].y = min(PlacementPin.maxHeight, max(0, y)) }
        if let z { placementPins[i].z = z }
    }

    func clearPlacementPins() {
        placementPins.removeAll()
    }

    var isDirectorBusy: Bool { isGenerating || isCompiling || isInventing }

    var canCompile: Bool {
        inputMode == .text
            && !isDirectorBusy
            && directorAvailability.isAvailable
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canInvent: Bool {
        inputMode == .text
            && !isDirectorBusy
            && directorAvailability.isAvailable
    }

    // MARK: - visionOS-only state
#if os(visionOS)
    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState { case closed, inTransition, open }
    var immersiveSpaceState = ImmersiveSpaceState.closed
#endif

    init() {
        guard !RuntimeLaunchContext.isXcodePreview else { return }
        directorAvailability = DirectorAvailabilityChecker.current()
        Task {
            await ShapERuntimeStore.shared.preload()
        }
    }

    // MARK: - Presets

    func applyQualityPreset(_ preset: QualityPreset) {
        numInferenceSteps = preset.numInferenceSteps
        gridSize = preset.gridSize
        enableLivePartials = preset.enableLivePartials
        usesGPU = preset.usesGPUForFinalExtract
    }

    func resetGenerationParameters() {
        qualityPreset = .standard
        // Re-apply in case preset was already standard (didSet may not fire).
        applyQualityPreset(.standard)
        batchSize = 1
        guidanceScale = inputMode == .image ? 3.0 : 15.0
#if os(macOS)
        queryBatchSize = 4096
#else
        queryBatchSize = 1024
#endif
        seed = 0
    }

    /// Snapshot of params used for a generation (stored on completed records).
    func currentParamsSnapshot() -> GenerationParams {
        GenerationParams(
            qualityPreset: qualityPreset.rawValue,
            batchSize: batchSize,
            guidanceScale: guidanceScale,
            numInferenceSteps: numInferenceSteps,
            gridSize: gridSize,
            queryBatchSize: queryBatchSize,
            seed: seed,
            usesGPU: usesGPU,
            enableLivePartials: enableLivePartials,
            inputMode: inputMode == .image ? "image" : "text"
        )
    }
}
