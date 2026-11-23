// visionOS/ImmersiveStudio.swift
// Mesquette — Table in front of the user. Director offsets are tabletop-scale.

#if os(visionOS)
import RealityKit
import UIKit
import simd

enum ImmersiveStudio {
    static let tableName = "studio-table"
    /// Standing / counter height. Mixed immersion origin is the floor.
    static let tableHeight: Float = 0.72
    /// Meters forward (−Z) so the set is at arm’s length, not at your feet.
    static let tableDistance: Float = 1.25
    static let tableWidth: Float = 1.8
    static let tableDepth: Float = 1.15
    static let maxX: Float = 0.78
    static let maxZ: Float = 0.48

    @discardableResult
    static func install(in root: Entity) -> Entity {
        if let existing = root.findEntity(named: tableName) {
            return existing
        }

        let table = Entity()
        table.name = tableName
        table.position = SIMD3(0, tableHeight, -tableDistance)

        let topMesh = MeshResource.generatePlane(width: tableWidth, depth: tableDepth)
        let glass = SimpleMaterial(
            color: UIColor(white: 1, alpha: 0.22),
            roughness: 0.22,
            isMetallic: false
        )
        let top = ModelEntity(mesh: topMesh, materials: [glass])
        top.name = "studio-table-top"
        table.addChild(top)

        root.addChild(table)
        return table
    }

    static func stage(in root: Entity) -> Entity {
        install(in: root)
    }

    /// Director +X is right, +Z is away from the user. Table local −Z is toward
    /// the far edge (away). Clamp so 5–6 pieces stay on the glass.
    static func slot(
        record: GenerationRecord,
        peers: [GenerationRecord],
        index: Int
    ) -> (x: Float, z: Float) {
        if record.offsetX != nil || record.offsetZ != nil {
            // Engine +Z is toward the user = table local +Z.
            return (
                clamp(record.offsetX ?? 0, maxX),
                clamp(record.offsetZ ?? 0, maxZ)
            )
        }
        let k = peers.prefix(index).filter { $0.offsetX == nil && $0.offsetZ == nil }.count
        return (clamp(Float(k) * 0.38, maxX), 0)
    }

    private static func clamp(_ value: Float, _ limit: Float) -> Float {
        min(limit, max(-limit, value))
    }
}
#endif
