// GenerationRecord.swift
// Mesquette — Shared across platforms

import Foundation
import ShapERuntime

/// Parameters used for a generation run (for library / iterate-from-this).
struct GenerationParams: Sendable, Codable, Equatable {
    var qualityPreset: String
    var batchSize: Int
    var guidanceScale: Double
    var numInferenceSteps: Int
    var gridSize: Int
    var queryBatchSize: Int
    var seed: Int
    var usesGPU: Bool
    var enableLivePartials: Bool
    var inputMode: String
}

/// A single entry in the generation history shown in the chat panel.
struct GenerationRecord: Identifiable, Sendable {
    let id: UUID
    let prompt: String
    let timestamp: Date
    var status: Status
    var latestMesh: MeshResult?
    /// Optional on-disk export of the **final** mesh only (not progressive partials).
    var finalMeshURL: URL?
    /// Snapshot of generation parameters (set when the run starts / completes).
    var params: GenerationParams?

    var userIntent: String?
    var compiledPrompt: String?
    var directorRationale: String?
    var suggestedScale: String?
    var suggestedMaterial: String?
    var setID: UUID?
    var setIndex: Int?
    var setTitle: String?
    /// Table-plane placement from the layout engine (meters, +Z toward the user).
    var offsetX: Float?
    var offsetY: Float?
    var offsetZ: Float?
    /// Yaw in degrees. Unused for auto-pose; lock-drag writes the node directly.
    var rotationY: Float?
    /// Uniform entity scale after sit-to-height. Nil until a mesh exists.
    var placementScale: Float?
    var slot: DirectorSlot?
    /// XZ collision radius after sit + scale, meters.
    var footprintRadius: Float?
    /// Forest/sea/grass patch — scale out until it touches the nearest neighbor.
    var fillsToNeighbors: Bool = false
    /// Pin this mesh was generated for, if any.
    var pinID: UUID?
    /// Short director title for this pin job.
    var partTitle: String?
    /// Stable inventory entry this record was generated from, if any.
    var inventoryID: UUID?
    /// named / extra / fallback — how the planner produced this job.
    var planRoute: PinPlanRoute?

    enum Status: Sendable {
        case generating
        case completed
        case failed(String)
    }

    init(
        id: UUID = UUID(),
        prompt: String,
        timestamp: Date = Date(),
        status: Status = .generating,
        latestMesh: MeshResult? = nil,
        finalMeshURL: URL? = nil,
        params: GenerationParams? = nil,
        userIntent: String? = nil,
        compiledPrompt: String? = nil,
        directorRationale: String? = nil,
        suggestedScale: String? = nil,
        suggestedMaterial: String? = nil,
        setID: UUID? = nil,
        setIndex: Int? = nil,
        setTitle: String? = nil,
        offsetX: Float? = nil,
        offsetY: Float? = nil,
        offsetZ: Float? = nil,
        rotationY: Float? = nil,
        placementScale: Float? = nil,
        slot: DirectorSlot? = nil,
        footprintRadius: Float? = nil,
        fillsToNeighbors: Bool = false,
        pinID: UUID? = nil,
        partTitle: String? = nil,
        inventoryID: UUID? = nil,
        planRoute: PinPlanRoute? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.timestamp = timestamp
        self.status = status
        self.latestMesh = latestMesh
        self.finalMeshURL = finalMeshURL
        self.params = params
        self.userIntent = userIntent
        self.compiledPrompt = compiledPrompt
        self.directorRationale = directorRationale
        self.suggestedScale = suggestedScale
        self.suggestedMaterial = suggestedMaterial
        self.setID = setID
        self.setIndex = setIndex
        self.setTitle = setTitle
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.offsetZ = offsetZ
        self.rotationY = rotationY
        self.placementScale = placementScale
        self.slot = slot
        self.footprintRadius = footprintRadius
        self.fillsToNeighbors = fillsToNeighbors
        self.pinID = pinID
        self.partTitle = partTitle
        self.inventoryID = inventoryID
        self.planRoute = planRoute
    }
}
