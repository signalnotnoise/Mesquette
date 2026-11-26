// DirectorLayoutEngine.swift
// Mesquette — LLM picks layout and slots; code owns meters and packing. No sit.

import Foundation
import simd
import ShapERuntime

/// Named places on the table. +X is right, +Z is toward the user.
nonisolated enum DirectorSlot: String, Codable, CaseIterable, Equatable, Sendable {
    case heroCenter
    case leftHand
    case rightHand
    case near
    case far
    case accent

    var title: String {
        switch self {
        case .heroCenter: return "Center"
        case .leftHand:   return "Left"
        case .rightHand:  return "Right"
        case .near:       return "Near"
        case .far:        return "Far"
        case .accent:     return "Accent"
        }
    }

    /// Fill order after the hero takes center.
    static let supportOrder: [DirectorSlot] = [.leftHand, .rightHand, .near, .far, .accent]
}

nonisolated extension DirectorScale {
    /// Longest AABB side on the table, meters. Never scale from the thin axis —
    /// that turns awnings and frames into giant walls.
    var targetSpan: Float {
        switch self {
        case .mug:       return 0.13
        case .figurine:  return 0.22
        case .tabletop:  return 0.34
        case .chair:     return 0.40
        case .lifeSize:  return 0.58
        case .building:  return 0.50
        }
    }

    var targetHeight: Float { targetSpan }

    var estimatedRadius: Float { max(0.06, targetSpan * 0.52) }
}

nonisolated struct DirectorFootprint: Equatable, Sendable {
    var scale: Float
    var radius: Float
    var satHeight: Float
}

nonisolated enum DirectorLayoutEngine {

    // MARK: - Compile-time: slots → rest poses (no mesh yet)

    static func applyTemplate(layout: DirectorLayout, parts: [CompiledPart]) -> [CompiledPart] {
        var staged = assignSlots(parts)
        let n = staged.count
        var supportOrdinal = 0
        for i in staged.indices {
            let isHero = staged[i].isHero || staged[i].slot == .heroCenter
            let pose = restPose(
                layout: layout,
                slot: staged[i].slot,
                index: i,
                count: n,
                isHero: isHero,
                supportIndex: supportOrdinal
            )
            if !isHero { supportOrdinal += 1 }
            staged[i].offsetX = pose.x
            staged[i].offsetZ = pose.z
            staged[i].rotationY = pose.yaw
        }
        return staged
    }

    /// Bind the first N parts to user pins (in order). Extra parts keep slot
    /// offsets relative to the first pin so the cluster follows the click.
    static func applyPins(
        _ pins: [PlacementPin],
        to parts: [CompiledPart],
        layout: DirectorLayout
    ) -> [CompiledPart] {
        guard !pins.isEmpty else { return applyTemplate(layout: layout, parts: parts) }
        var staged = applyTemplate(layout: layout, parts: parts)
        let origin = pins[0]
        for i in staged.indices {
            if i < pins.count {
                staged[i].offsetX = pins[i].x
                staged[i].offsetZ = pins[i].z
            } else {
                staged[i].offsetX += origin.x
                staged[i].offsetZ += origin.z
            }
        }
        return staged
    }

    static func assignSlots(_ parts: [CompiledPart]) -> [CompiledPart] {
        var staged = parts
        var used: Set<DirectorSlot> = []

        if let hero = staged.firstIndex(where: \.isHero) {
            staged[hero].slot = .heroCenter
            used.insert(.heroCenter)
        }

        for i in staged.indices {
            if staged[i].isHero { continue }
            let candidate = staged[i].slot
            if candidate != .heroCenter, !used.contains(candidate) {
                used.insert(candidate)
                continue
            }
            if let next = DirectorSlot.supportOrder.first(where: { !used.contains($0) }) {
                staged[i].slot = next
                used.insert(next)
            } else {
                staged[i].slot = .accent
            }
        }
        return staged
    }

    /// Rest pose before AABB packing. +Z toward the user (Mac camera / table local).
    static func restPose(
        layout: DirectorLayout,
        slot: DirectorSlot,
        index: Int,
        count: Int,
        isHero: Bool,
        supportIndex: Int = 0
    ) -> (x: Float, z: Float, yaw: Float) {
        let yaw: Float = 0
        switch layout {
        case .placeSetting:
            let p = placeSettingRest(slot)
            return (p.x, p.z, yaw)
        case .row:
            let span = Float(max(count - 1, 1))
            let x = (Float(index) - span / 2) * 0.34
            return (x, 0, yaw)
        case .arc:
            let span = Float(max(count - 1, 1))
            let t = Float(index) / span
            let theta = (-0.70) + (1.40) * t
            let r: Float = 0.38
            return (sin(theta) * r, -cos(theta) * r, yaw)
        case .cluster:
            if isHero || slot == .heroCenter {
                return (0, 0, yaw)
            }
            let others = max(count - 1, 1)
            let angle = Float(supportIndex) * (2 * .pi / Float(others))
            let r: Float = 0.32
            return (cos(angle) * r, sin(angle) * r, yaw)
        }
    }

    static func placeSettingRest(_ slot: DirectorSlot) -> (x: Float, z: Float) {
        switch slot {
        case .heroCenter: return (0, 0)
        case .leftHand:   return (-0.28, 0.05)
        case .rightHand:  return (0.28, 0.05)
        case .near:       return (0.00, 0.30)
        case .far:        return (0.00, -0.30)
        case .accent:     return (0.24, -0.18)
        }
    }

    // MARK: - After mesh: sit extents, scale to height, pack

    static func rawExtents(from mesh: MeshResult) -> SIMD3<Float>? {
        // try?: a tensor that cannot materialize has no extents; callers treat nil as no-fit.
        guard let verts = try? mesh.vertices.float32Values(), verts.count >= 3 else {
            return nil
        }
        var minV = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxV = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        let n = verts.count / 3
        for i in 0..<n {
            let p = SIMD3(verts[i * 3], verts[i * 3 + 1], verts[i * 3 + 2])
            minV = min(minV, p)
            maxV = max(maxV, p)
        }
        let e = maxV - minV
        guard e.x.isFinite, e.y.isFinite, e.z.isFinite else { return nil }
        return SIMD3(max(e.x, 1e-4), max(e.y, 1e-4), max(e.z, 1e-4))
    }

    static func fit(
        mesh: MeshResult,
        scale: DirectorScale,
        worldScale: Float = 1
    ) -> DirectorFootprint? {
        guard let raw = rawExtents(from: mesh) else { return nil }
        let longest = max(raw.x, max(raw.y, raw.z))
        let s = uniformScale(span: longest, target: scale.targetSpan) * max(1, worldScale)
        let radius = max(0.05, 0.5 * max(raw.x, raw.z) * s + 0.03)
        return DirectorFootprint(scale: s, radius: radius, satHeight: raw.y)
    }

    /// Pins 10 m apart should not get 12 cm figurines. Table-sized clusters stay 1×.
    static func pinWorldScale(_ pins: [PlacementPin]) -> Float {
        guard pins.count >= 2 else { return 1 }
        let xs = pins.map(\.x)
        let zs = pins.map(\.z)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minZ = zs.min(), let maxZ = zs.max() else { return 1 }
        let span = max(maxX - minX, maxZ - minZ, 0.8)
        let table = DirectorScale.figurine.targetSpan * 8
        return min(8, max(1, span / table))
    }

    static func uniformScale(span: Float, target: Float) -> Float {
        let d = max(span, 1e-4)
        return min(1.6, max(0.04, target / d))
    }

    /// Push overlapping footprints apart while staying near rest poses.
    static func pack(
        rest: [(x: Float, z: Float)],
        radii: [Float],
        locked: [Bool] = [],
        gap: Float = 0.04,
        recenter: Bool = true
    ) -> [(x: Float, z: Float)] {
        let n = rest.count
        guard n == radii.count, n >= 2 else { return rest }
        var pos = rest.map { SIMD2($0.x, $0.z) }
        let restV = pos
        let lock: [Bool] = (0..<n).map { $0 < locked.count ? locked[$0] : false }
        func resolveCollisions() {
            for i in 0..<n {
                for j in (i + 1)..<n {
                    var delta = pos[j] - pos[i]
                    let dist = length(delta)
                    let need = radii[i] + radii[j] + gap
                    if dist < 1e-4 {
                        if lock[i] && lock[j] { continue }
                        let angle = Float(j) * (2 * .pi / Float(n))
                        let kick = SIMD2(cos(angle), sin(angle)) * need
                        if lock[i] { pos[j] += kick }
                        else if lock[j] { pos[i] -= kick }
                        else { pos[j] += kick }
                        continue
                    }
                    if dist < need {
                        delta /= dist
                        let overlap = need - dist
                        if lock[i] && lock[j] { continue }
                        if lock[i] {
                            pos[j] += delta * overlap
                        } else if lock[j] {
                            pos[i] -= delta * overlap
                        } else {
                            pos[i] -= delta * overlap * 0.5
                            pos[j] += delta * overlap * 0.5
                        }
                    }
                }
            }
        }
        for _ in 0..<20 { resolveCollisions() }
        for _ in 0..<8 {
            for i in 0..<n where !lock[i] {
                pos[i] += (restV[i] - pos[i]) * 0.05
            }
            resolveCollisions()
        }
        if recenter {
            let center = pos.reduce(SIMD2<Float>.zero, +) / Float(n)
            pos = pos.map { $0 - center }
        }
        for _ in 0..<8 { resolveCollisions() }
        let limit: Float = recenter ? 0.85 : 5.5
        return pos.map { p in
            (min(limit, max(-limit, p.x)), min(limit, max(-limit, p.y)))
        }
    }

    static func packRecords(
        _ records: inout [GenerationRecord],
        layout: DirectorLayout,
        pins: [PlacementPin] = []
    ) {
        guard records.count >= 2 else { return }
        let pinByID = Dictionary(uniqueKeysWithValues: pins.map { ($0.id, $0) })
        var supportOrdinal = 0
        var rest: [(x: Float, z: Float)] = []
        rest.reserveCapacity(records.count)
        var locked = [Bool](repeating: false, count: records.count)

        for (i, rec) in records.enumerated() {
            let pinned: PlacementPin?
            if let pinID = rec.pinID, let pin = pinByID[pinID] {
                pinned = pin
            } else if rec.pinID == nil, i < pins.count {
                pinned = pins[i]
            } else {
                pinned = nil
            }
            if let pin = pinned {
                rest.append((pin.x, pin.z))
                locked[i] = true
                records[i].offsetX = pin.x
                records[i].offsetY = pin.y
                records[i].offsetZ = pin.z
                continue
            }
            let slot = rec.slot ?? DirectorSlot.supportOrder[min(i, 4)]
            let isHero = rec.slot == .heroCenter
            let pose = restPose(
                layout: layout,
                slot: slot,
                index: i,
                count: records.count,
                isHero: isHero,
                supportIndex: supportOrdinal
            )
            if !isHero { supportOrdinal += 1 }
            if let origin = pins.first {
                rest.append((origin.x + pose.x, origin.z + pose.z))
            } else {
                rest.append((pose.x, pose.z))
            }
        }

        let radii: [Float] = records.map { rec in
            if let r = rec.footprintRadius, r > 0 { return r }
            if let raw = rec.suggestedScale, let scale = DirectorScale(rawValue: raw) {
                return scale.estimatedRadius
            }
            return DirectorScale.figurine.estimatedRadius
        }
        if locked.allSatisfy({ $0 }) {
            return
        }
        let packed = pack(rest: rest, radii: radii, locked: locked, recenter: pins.isEmpty)
        for i in records.indices where !locked[i] {
            records[i].offsetX = packed[i].x
            records[i].offsetZ = packed[i].z
        }
    }

    /// Forest / sea patches grow in XZ until they touch the nearest other object.
    static func expandFills(_ records: inout [GenerationRecord]) {
        guard records.count >= 2 else { return }
        for i in records.indices {
            guard records[i].fillsToNeighbors else { continue }
            let x = records[i].offsetX ?? 0
            let z = records[i].offsetZ ?? 0
            var bestGap: Float = .greatestFiniteMagnitude
            for j in records.indices where j != i {
                let ox = records[j].offsetX ?? 0
                let oz = records[j].offsetZ ?? 0
                let dist = hypot(ox - x, oz - z)
                let otherR = records[j].footprintRadius
                    ?? DirectorScale.figurine.estimatedRadius
                let meet = records[j].fillsToNeighbors
                    ? dist * 0.5
                    : max(0.06, dist - otherR)
                if meet < bestGap { bestGap = meet }
            }
            guard bestGap.isFinite, bestGap > 0.04 else { continue }
            let targetR = min(2.4, bestGap)
            let currentR = max(records[i].footprintRadius ?? 0.08, 0.04)
            let factor = targetR / currentR
            let currentScale = records[i].placementScale ?? 1
            records[i].placementScale = min(8, max(0.04, currentScale * factor))
            records[i].footprintRadius = targetR
        }
    }
}
