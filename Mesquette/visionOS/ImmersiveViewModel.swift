#if os(visionOS)
import RealityKit
import SwiftUI
import os
import simd
import ShapERuntime

@Observable
/// Mirrors `AppModel` generation records into the immersive RealityKit scene.
/// Sync is coalesced: concurrent callers set `needsResync` instead of dropping updates.
class ImmersiveViewModel {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.visionarydevops.Mesquette", category: "immersive")
    
    // Small hop onto the table — not a leap from the user's head.
    let jumpDuration: TimeInterval = 0.7
    let jumpHeight: Float = 0.22

    // Transient state for scene entities
    var addedEntities: [UUID: ModelEntity] = [:]
    var lowLevelMeshes: [UUID: LowLevelMesh] = [:]
    /// True while a sync pass is in flight. Concurrent callers set `needsResync`
    /// instead of bailing out so the latest mesh/status is never dropped.
    private var isSyncing = false
    private var needsResync = false

    // Gesture transient state — owned here so the view never writes to @State
    // from inside a gesture handler that runs during a view-update pass.
    var initialOrientation: simd_quatf? = nil
    var initialScale: SIMD3<Float>? = nil
    
    @MainActor
    func sync(with appModel: AppModel, rootEntity: Entity) async {
        // If a sync is already running, mark dirty and return. The in-flight
        // pass will loop again after it finishes so the newest state is applied.
        if isSyncing {
            needsResync = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        
        repeat {
            needsResync = false
            
            let stage = ImmersiveStudio.stage(in: rootEntity)
            let recordsWithMesh = appModel.generationOrder
                .compactMap { appModel.generationDict[$0] }
                .filter { $0.latestMesh != nil }
            
            for (i, record) in recordsWithMesh.enumerated() {
                guard let meshResult = record.latestMesh else { continue }
                let isPartial: Bool
                if case .generating = record.status {
                    isPartial = true
                } else {
                    isPartial = false
                }
                
                do {
                    if let existingEntity = addedEntities[record.id],
                       let lowLevelMesh = lowLevelMeshes[record.id] {
                        
                        var texture: TextureResource? = nil
                        var didUpdate = false
                        
                        do {
                            // 1. Try updating the existing LowLevelMesh buffers in-place
                            texture = try await ShapEMeshAdapter.updateLowLevelMesh(lowLevelMesh, from: meshResult, isPartial: isPartial)
                            didUpdate = true
                        } catch ShapEMeshAdapterError.capacityExceeded {
                            // Final coloured meshes expand to 3 verts per triangle
                            // (per-triangle colour atlas). Size capacity for that.
                            let faceCount = meshResult.faces.elementCount
                            let needed = max(faceCount, try meshResult.vertices.float32Values().count / 3)
                            let newCapacity = Int(Double(needed) * 1.25) + 1024
                            
                            Self.logger.debug("Reallocating LowLevelMesh capacity to \(newCapacity) verts/indices")
                            
                            let newLowLevelMesh = try ShapEMeshAdapter.createLowLevelMesh(
                                vertexCapacity: newCapacity,
                                indexCapacity: newCapacity
                            )
                            
                            texture = try await ShapEMeshAdapter.updateLowLevelMesh(
                                newLowLevelMesh,
                                from: meshResult,
                                isPartial: isPartial
                            )
                            
                            let meshResource = try await MeshResource(from: newLowLevelMesh)
                            
                            if var modelComponent = existingEntity.components[ModelComponent.self] {
                                modelComponent.mesh = meshResource
                                existingEntity.components.set(modelComponent)
                            }
                            
                            lowLevelMeshes[record.id] = newLowLevelMesh
                            didUpdate = true
                        }
                        
                        if didUpdate {
                            // 3. Swap material when partial (grey) → final (vertex colours).
                            // Unlit + per-triangle colour atlas matches SceneKit constant shading.
                            if var modelComponent = existingEntity.components[ModelComponent.self] {
                                let material = ShapEMeshAdapter.makeMaterial(texture: texture)
                                modelComponent.materials = [material]
                                existingEntity.components.set(modelComponent)
                            }

                            if record.setID != nil {
                                let packedScale = record.placementScale ?? 1
                                existingEntity.scale = SIMD3<Float>(repeating: packedScale)
                                existingEntity.position = Self.stagedPosition(
                                    for: existingEntity,
                                    record: record,
                                    peers: recordsWithMesh,
                                    index: i
                                )
                            }
                            
                            // 4. Mark final status. Re-sit Y so a fatter final mesh
                            // does not hover; keep X/Z so a user drag is not undone
                            // once the set is no longer packing.
                            if !isPartial && existingEntity.components[GeneratedEntityTag.self]?.isFinal == false {
                                existingEntity.components.set(GeneratedEntityTag(entityID: ObjectIdentifier(existingEntity), isFinal: true))
                                if record.setID == nil {
                                    Self.restOnStage(existingEntity)
                                }
                            }
                        }
                    } else {
                        // Create new entity
                        // Coloured meshes expand to 3 verts/triangle — size capacity from the mesh.
                        let estimatedVerts = max(
                            (meshResult.faces.elementCount),
                            3_000
                        )
                        let capacity = Int(Double(estimatedVerts) * 1.25)
                        let lowLevelMesh = try ShapEMeshAdapter.createLowLevelMesh(
                            vertexCapacity: capacity,
                            indexCapacity: capacity
                        )
                        
                        let texture = try await ShapEMeshAdapter.updateLowLevelMesh(
                            lowLevelMesh,
                            from: meshResult,
                            isPartial: isPartial
                        )
                        
                        let meshResource = try await MeshResource(from: lowLevelMesh)
                        let material = ShapEMeshAdapter.makeMaterial(texture: texture)
                        
                        let newEntity = ModelEntity(mesh: meshResource, materials: [material])
                        newEntity.generateCollisionShapes(recursive: true)
                        newEntity.components.set(InputTargetComponent(allowedInputTypes: .indirect))
                        
                        newEntity.name = "gen_\(record.id)"
                        newEntity.components.set(GeneratedEntityTag(entityID: ObjectIdentifier(newEntity), isFinal: !isPartial))
                        
                        let endScale = record.placementScale ?? 1
                        newEntity.scale = .one
                        newEntity.orientation = .init(angle: 0, axis: SIMD3<Float>(0, 1, 0))
                        newEntity.position = .zero
                        stage.addChild(newEntity)
                        newEntity.scale = SIMD3<Float>(repeating: endScale)
                        newEntity.orientation = .init(angle: 0, axis: SIMD3<Float>(0, 1, 0))
                        let planted = Self.stagedPosition(
                            for: newEntity,
                            record: record,
                            peers: recordsWithMesh,
                            index: i
                        )
                        newEntity.position = planted

                        addedEntities[record.id] = newEntity
                        lowLevelMeshes[record.id] = lowLevelMesh
                        
                        applyJumpAnimation(
                            to: newEntity,
                            endPosition: planted,
                            endScale: endScale,
                            endOrientation: newEntity.orientation
                        )
                    }
                } catch {
                    Self.logger.error("Failed to sync mesh for record \(record.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            // If another caller requested sync while we were working, re-read
            // AppModel and apply the latest meshes/status before releasing the lock.
        } while needsResync
    }
    
    /// Local slot on the studio table. Sit on y = 0 (the glass).
    private static func stagedPosition(
        for entity: Entity,
        record: GenerationRecord,
        peers: [GenerationRecord],
        index: Int
    ) -> SIMD3<Float> {
        let slot = ImmersiveStudio.slot(record: record, peers: peers, index: index)
        return plantedPosition(for: entity, x: slot.x, y: record.offsetY ?? 0, z: slot.z)
    }

    /// Pin is feet for grounded objects, bbox center for airborne ones.
    private static func plantedPosition(for entity: Entity, x: Float, y: Float, z: Float) -> SIMD3<Float> {
        let bounds = entity.visualBounds(relativeTo: entity)
        let cx = (bounds.min.x + bounds.max.x) * 0.5
        let cz = (bounds.min.z + bounds.max.z) * 0.5
        let localY = y >= PlacementPin.airborneThreshold
            ? (bounds.min.y + bounds.max.y) * 0.5
            : bounds.min.y
        let local = SIMD3(cx, localY, cz)
        let s = entity.scale
        let scaled = SIMD3(local.x * s.x, local.y * s.y, local.z * s.z)
        let rotated = entity.orientation.act(scaled)
        return SIMD3(x, y, z) - rotated
    }

    private static func restOnStage(_ entity: Entity) {
        guard let parent = entity.parent else { return }
        let bounds = entity.visualBounds(relativeTo: parent)
        entity.position.y -= bounds.min.y
    }

    @MainActor
    func applyJumpAnimation(
        to entity: ModelEntity,
        endPosition: SIMD3<Float>? = nil,
        endScale: Float = 1,
        endOrientation: simd_quatf? = nil
    ) {
        let landing = endPosition ?? entity.position
        let orientation = endOrientation ?? entity.orientation
        entity.scale = SIMD3<Float>(0.01, 0.01, 0.01)
        entity.position = SIMD3(landing.x, landing.y + jumpHeight, landing.z)
        entity.orientation = orientation
        
        var midTransform = entity.transform
        midTransform.translation = SIMD3(landing.x, landing.y + jumpHeight * 0.45, landing.z)
        midTransform.scale = SIMD3<Float>(repeating: max(0.08, endScale * 0.5))
        midTransform.rotation = orientation
        
        var endTransform = midTransform
        endTransform.translation = landing
        endTransform.scale = SIMD3<Float>(repeating: endScale)
        endTransform.rotation = orientation
        
        // We can do a sequence of FromToByAnimations or a Timeline, but the simplest way given
        // visionOS realities is to use playAnimation with AnimationResource.
        // It's robust to do two FromToBy Animations sequenced.
        
        do {
            let upAnim = FromToByAnimation<Transform>(
                name: "jumpUp",
                from: entity.transform,
                to: midTransform,
                duration: jumpDuration / 2,
                timing: .easeOut,
                bindTarget: .transform
            )
            
            let downAnim = FromToByAnimation<Transform>(
                name: "jumpDown",
                from: midTransform,
                to: endTransform,
                duration: jumpDuration / 2,
                timing: .easeIn,
                bindTarget: .transform
            )
            
            let upResource = try AnimationResource.generate(with: upAnim)
            let downResource = try AnimationResource.generate(with: downAnim)
            
            let sequence = try AnimationResource.sequence(with: [upResource, downResource])
            
            entity.playAnimation(sequence)
            
        } catch {
            Self.logger.error("Failed to generate jump animation: \(error.localizedDescription, privacy: .public)")
            // Fallback
            entity.transform = endTransform
        }
    }
}
#endif
