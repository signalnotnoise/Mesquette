// DirectorGenerable.swift
// Mesquette — Foundation Models guided types. Mapped to CompiledPrompt after decode.

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@Generable
enum GenerableDirectorKind {
    case single
    case set
}

@Generable
enum GenerableDirectorScale {
    case mug, figurine, tabletop, chair, lifeSize, building
}

@Generable
enum GenerableDirectorMaterial {
    case vertexColor, ceramic, metal, glass, clay, wood, stone
}

@Generable
enum GenerableDirectorLayout {
    case row, arc, cluster, placeSetting
}

@Generable
enum GenerableDirectorSlot {
    case heroCenter, leftHand, rightHand, near, far, accent
}

@Generable
struct GenerableCompiledPart {
    @Guide(description: "Short object name, a few words")
    var title: String

    @Guide(description: "10 to 24 word Shap-E prompt: name the object, then silhouette, material, color, one feature. Never write closed volume or prop instead of the name.")
    var shapEPrompt: String

    var scale: GenerableDirectorScale
    var material: GenerableDirectorMaterial
    var slot: GenerableDirectorSlot

    @Guide(description: "True for the one hero object, which must use heroCenter")
    var isHero: Bool
}

@Generable
struct GenerableCompiledPrompt {
    var kind: GenerableDirectorKind

    @Guide(description: "Short scene or object title")
    var title: String

    @Guide(description: "Shap-E prompt when kind is single; first object prompt when kind is set")
    var shapEPrompt: String

    var scale: GenerableDirectorScale
    var material: GenerableDirectorMaterial

    @Guide(description: "1, or 4 if the user asked for variations. Always 1 for sets.")
    var variationCount: Int

    @Guide(description: "One sentence naming invented objects and why they belong together")
    var rationale: String

    var layout: GenerableDirectorLayout

    @Guide(description: "Mood you invented, a few words. Empty for a single object.")
    var mood: String

    @Guide(description: "One part for a single object. Named objects are required parts; add at most two chunky dressing props. 5 to 6 parts only when the user named no objects")
    var parts: [GenerableCompiledPart]
}

extension GenerableCompiledPrompt {
    func asCompiledPrompt() -> CompiledPrompt {
        CompiledPrompt(
            kind: kind.asDirectorKind,
            title: title,
            shapEPrompt: shapEPrompt,
            scale: scale.asDirectorScale,
            material: material.asDirectorMaterial,
            variationCount: variationCount,
            rationale: rationale,
            layout: layout.asDirectorLayout,
            mood: mood,
            parts: parts.map { $0.asCompiledPart() }
        ).normalized()
    }
}

extension GenerableCompiledPart {
    func asCompiledPart() -> CompiledPart {
        CompiledPart(
            title: title,
            shapEPrompt: shapEPrompt,
            scale: scale.asDirectorScale,
            material: material.asDirectorMaterial,
            slot: slot.asDirectorSlot,
            isHero: isHero
        )
    }
}

extension GenerableDirectorKind {
    var asDirectorKind: DirectorKind {
        switch self {
        case .single: return .single
        case .set: return .set
        }
    }
}

extension GenerableDirectorScale {
    var asDirectorScale: DirectorScale {
        switch self {
        case .mug: return .mug
        case .figurine: return .figurine
        case .tabletop: return .tabletop
        case .chair: return .chair
        case .lifeSize: return .lifeSize
        case .building: return .building
        }
    }
}

extension GenerableDirectorMaterial {
    var asDirectorMaterial: DirectorMaterial {
        switch self {
        case .vertexColor: return .vertexColor
        case .ceramic: return .ceramic
        case .metal: return .metal
        case .glass: return .glass
        case .clay: return .clay
        case .wood: return .wood
        case .stone: return .stone
        }
    }
}

extension GenerableDirectorLayout {
    var asDirectorLayout: DirectorLayout {
        switch self {
        case .row: return .row
        case .arc: return .arc
        case .cluster: return .cluster
        case .placeSetting: return .placeSetting
        }
    }
}

extension GenerableDirectorSlot {
    var asDirectorSlot: DirectorSlot {
        switch self {
        case .heroCenter: return .heroCenter
        case .leftHand:   return .leftHand
        case .rightHand:  return .rightHand
        case .near:       return .near
        case .far:        return .far
        case .accent:     return .accent
        }
    }
}

@Generable
struct GenerableInventedPreset {
    @Guide(description: "Short chip title, 1 to 3 words, not a generic Bakery or Desk")
    var title: String

    @Guide(description: "One or two sentences: place, time, 5 to 6 named distinctive objects with material, color, and a signature feature. Hero is a landmark or character, not a mug.")
    var prompt: String

    @Guide(description: "Mood, a few words")
    var mood: String
}

extension GenerableInventedPreset {
    func asInventedPreset() -> InventedPreset {
        InventedPreset(title: title, prompt: prompt, mood: mood)
    }
}

@Generable
struct GenerablePinPlanItem {
    @Guide(description: "Pin number, matching the list you were given (1-based)")
    var pinIndex: Int

    @Guide(description: "Unique short name, never reused")
    var title: String

    @Guide(description: "Name the object, then silhouette, material, color, one feature. Never write closed volume, complementary prop, or the whole scene.")
    var shapEPrompt: String

    var scale: GenerableDirectorScale
    var material: GenerableDirectorMaterial

    @Guide(description: "Always false. Ground, sea surface, and grass sheets are never meshes. A named forest or meadow patch is one closed mound and does not grow.")
    var fillsToNeighbors: Bool
}

@Generable
struct GenerablePinPlanChunk {
    @Guide(description: "One item per pin in this batch")
    var items: [GenerablePinPlanItem]
}

@Generable
enum GenerableObjectHeight {
    case floor
    case airborne
}

@Generable
struct GenerableTaggedObject {
    @Guide(description: "The user's words for this one object, not the whole scene")
    var name: String

    var height: GenerableObjectHeight

    @Guide(description: "True for the main figure, usually the grounded subject")
    var isHero: Bool
}

@Generable
struct GenerableSceneCast {
    @Guide(description: "Place or setting, a few words. Empty if none.")
    var setting: String

    @Guide(description: "Distinct objects named in the scene. Skip lighting and palette. Keep an amber glass bottle. Red car and blue car are two objects.")
    var objects: [GenerableTaggedObject]
}

extension GenerableSceneCast {
    func asTaggedSceneCast() -> DirectorStaging.TaggedSceneCast {
        var tagged: [DirectorStaging.SceneObject] = []
        var seen: Set<String> = []
        for item in objects {
            let height: DirectorStaging.TaggedHeight = item.height == .airborne ? .airborne : .floor
            if let object = DirectorStaging.ingestTaggedObject(
                name: item.name,
                height: height,
                isHero: item.isHero,
                seenKeys: &seen
            ) {
                tagged.append(object)
            }
        }
        return DirectorStaging.TaggedSceneCast(
            setting: setting.trimmingCharacters(in: .whitespacesAndNewlines),
            objects: tagged
        )
    }
}
#endif
