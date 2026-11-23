// CompiledPrompt.swift
// Mesquette — Director output: one Shap-E prompt, or a laid-out set of objects.

import Foundation

nonisolated enum DirectorKind: String, Codable, Equatable, Sendable {
    case single
    case set
}

nonisolated enum DirectorScale: String, Codable, CaseIterable, Equatable, Sendable {
    case mug, figurine, tabletop, chair, lifeSize, building

    var title: String {
        switch self {
        case .mug:       return "Mug"
        case .figurine:  return "Figurine"
        case .tabletop:  return "Tabletop"
        case .chair:     return "Chair"
        case .lifeSize:  return "Life-size"
        case .building:  return "Building"
        }
    }

    /// Fallback uniform scale when no mesh AABB is available yet.
    var placementScale: Float { targetHeight }
}

nonisolated enum DirectorLayout: String, Codable, CaseIterable, Equatable, Sendable {
    case row, arc, cluster, placeSetting

    var title: String {
        switch self {
        case .row:          return "Row"
        case .arc:          return "Arc"
        case .cluster:      return "Cluster"
        case .placeSetting: return "Place setting"
        }
    }
}

nonisolated enum DirectorMaterial: String, Codable, CaseIterable, Equatable, Sendable {
    case vertexColor, ceramic, metal, glass, clay, wood, stone

    var title: String {
        switch self {
        case .vertexColor: return "Vertex color"
        case .ceramic:     return "Ceramic"
        case .metal:       return "Metal"
        case .glass:       return "Glass"
        case .clay:        return "Clay"
        case .wood:        return "Wood"
        case .stone:       return "Stone"
        }
    }
}

/// One object in a directed scene. Offsets are engine-owned meters on the table
/// (+X right, +Z toward the user). The LLM picks `slot` and `layout`.
nonisolated struct CompiledPart: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var shapEPrompt: String
    var scale: DirectorScale
    var material: DirectorMaterial
    var slot: DirectorSlot
    /// Meters, +X is right of center. Filled by DirectorLayoutEngine.
    var offsetX: Float
    /// Meters, +Z toward the user. Filled by DirectorLayoutEngine.
    var offsetZ: Float
    /// Degrees around Y. 0 faces the user.
    var rotationY: Float
    /// Hero sits near center; supporting pieces orbit it.
    var isHero: Bool

    var placementScale: Float { scale.placementScale }

    init(
        id: UUID = UUID(),
        title: String,
        shapEPrompt: String,
        scale: DirectorScale,
        material: DirectorMaterial,
        slot: DirectorSlot = .heroCenter,
        offsetX: Float = 0,
        offsetZ: Float = 0,
        rotationY: Float = 0,
        isHero: Bool = false
    ) {
        self.id = id
        self.title = title
        self.shapEPrompt = shapEPrompt
        self.scale = scale
        self.material = material
        self.slot = slot
        self.offsetX = offsetX
        self.offsetZ = offsetZ
        self.rotationY = rotationY
        self.isHero = isHero
    }
}

nonisolated struct CompiledPrompt: Codable, Equatable, Sendable {
    var kind: DirectorKind
    var title: String
    var shapEPrompt: String
    var scale: DirectorScale
    var material: DirectorMaterial
    var variationCount: Int
    var rationale: String
    /// How the set is staged on the table. Ignored for singles.
    var layout: DirectorLayout
    /// Short mood the director invented around ("cozy morning"). Empty for singles.
    var mood: String
    var parts: [CompiledPart]

    /// Clamp counts, coerce illegal sets, and guarantee `parts` is never empty.
    func normalized() -> CompiledPrompt {
        var copy = self
        copy.variationCount = min(4, max(1, variationCount))
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.shapEPrompt = shapEPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.rationale = rationale.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.mood = mood.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts = parts.map { part -> CompiledPart in
            var p = part
            p.title = p.title.trimmingCharacters(in: .whitespacesAndNewlines)
            p.shapEPrompt = DirectorStaging.objectPrompt(p.shapEPrompt)
            if p.title.isEmpty { p.title = "Object" }
            p.scale = DirectorStaging.inferredScale(title: p.title, prompt: p.shapEPrompt, current: p.scale)
            p.material = DirectorStaging.inferredMaterial(title: p.title, prompt: p.shapEPrompt, current: p.material)
            p.rotationY = min(180, max(-180, p.rotationY))
            return p
        }
        .filter { !$0.shapEPrompt.isEmpty }

        if parts.isEmpty {
            let prompt = copy.shapEPrompt.isEmpty ? copy.title : copy.shapEPrompt
            parts = [
                CompiledPart(
                    title: copy.title.isEmpty ? "Object" : copy.title,
                    shapEPrompt: prompt,
                    scale: copy.scale,
                    material: copy.material
                )
            ]
        }

        if parts.count > 6 {
            parts = Array(parts.prefix(6))
        }

        if copy.kind == .set && parts.count < 2 {
            copy.kind = .single
        }
        if copy.kind == .single {
            copy.variationCount = min(4, max(1, copy.variationCount))
            if parts.count > 1 {
                // A "single" that still listed extras: keep the first as the generate prompt.
                parts = [parts[0]]
            }
            parts[0].offsetX = 0
            parts[0].offsetZ = 0
            parts[0].rotationY = 0
            parts[0].isHero = true
            copy.mood = ""
            if copy.shapEPrompt.isEmpty {
                copy.shapEPrompt = parts[0].shapEPrompt
            }
        } else {
            copy.variationCount = 1
            if copy.shapEPrompt.isEmpty {
                copy.shapEPrompt = parts[0].shapEPrompt
            }
            if !parts.contains(where: \.isHero) {
                parts[0].isHero = true
            }
            parts = parts.filter { !DirectorStaging.isGroundLike($0) }
            if parts.count >= 2 {
                parts = DirectorLayoutEngine.applyTemplate(layout: copy.layout, parts: parts)
            } else {
                copy.kind = .single
                if let only = parts.first {
                    copy.shapEPrompt = only.shapEPrompt
                }
            }
        }

        if parts.isEmpty {
            let prompt = copy.shapEPrompt.isEmpty ? (copy.title.isEmpty ? "a ceramic mug" : copy.title) : copy.shapEPrompt
            parts = [
                CompiledPart(
                    title: copy.title.isEmpty ? "Object" : copy.title,
                    shapEPrompt: prompt,
                    scale: copy.scale,
                    material: copy.material,
                    isHero: true
                )
            ]
            copy.kind = .single
        }

        if copy.title.isEmpty {
            copy.title = copy.kind == .set ? "Scene" : parts[0].title
        }

        copy.parts = parts
        return copy
    }

    var selectedPart: CompiledPart? {
        parts.first
    }
}
