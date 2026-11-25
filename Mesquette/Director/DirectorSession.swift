// DirectorSession.swift
// Mesquette — Pure apply/revert of a compilation onto AppModel.

import Foundation

/// Applies/reverts compilations and invented presets onto `AppModel`, and stamps
/// generations that still match a compilation. Pure state edits, no async work.
enum DirectorSession {
    /// Drop an invented brief into the prompt and pin it at the top of For you.
    @discardableResult
    static func applyInvented(_ invented: InventedPreset, to appModel: AppModel) -> PromptPreset {
        let preset = invented.asPromptPreset()
        appModel.inputMode = .text
        appModel.prompt = preset.prompt
        appModel.lastCompilation = nil
        appModel.directorIntent = nil
        appModel.selectedPartID = nil
        appModel.directorError = nil
        appModel.inventedPresets.removeAll {
            $0.title.caseInsensitiveCompare(preset.title) == .orderedSame
        }
        appModel.inventedPresets.insert(preset, at: 0)
        if appModel.inventedPresets.count > 12 {
            appModel.inventedPresets = Array(appModel.inventedPresets.prefix(12))
        }
        return preset
    }

    /// Capture intent, store the compilation, and for a single object fill the Shap-E field.
    static func applyCompile(
        intent: String,
        compiled raw: CompiledPrompt,
        to appModel: AppModel
    ) {
        let compiled = raw.normalized()
        appModel.directorIntent = intent
        appModel.lastCompilation = compiled
        appModel.directorError = nil
        appModel.selectedPartID = compiled.parts.first?.id

        if compiled.kind == .single {
            appModel.prompt = compiled.shapEPrompt
        }
        // Sets do not smash the field into one combined sentence.
    }

    static func revert(to appModel: AppModel) {
        if let intent = appModel.directorIntent {
            appModel.prompt = intent
        }
        appModel.directorError = nil
        appModel.pinPlanNote = nil
        appModel.lastCompilation = nil
        appModel.directorIntent = nil
        appModel.selectedPartID = nil
        appModel.clearPlacementPins()
    }

    static func useFirstPart(on appModel: AppModel) {
        guard let part = selectedPart(in: appModel) ?? appModel.lastCompilation?.parts.first else {
            return
        }
        appModel.prompt = part.shapEPrompt
        appModel.selectedPartID = part.id
        if var compiled = appModel.lastCompilation {
            compiled.kind = .single
            compiled.shapEPrompt = part.shapEPrompt
            compiled.parts = [part]
            compiled.variationCount = 1
            appModel.lastCompilation = compiled.normalized()
        }
    }

    static func applyVariations(to appModel: AppModel) {
        guard let compiled = appModel.lastCompilation, compiled.kind == .single else { return }
        appModel.batchSize = min(4, max(1, compiled.variationCount))
    }

    static func removePart(id: UUID, on appModel: AppModel) {
        guard var compiled = appModel.lastCompilation else { return }
        compiled.parts.removeAll { $0.id == id }
        compiled = compiled.normalized()
        appModel.lastCompilation = compiled
        if appModel.selectedPartID == id {
            appModel.selectedPartID = compiled.parts.first?.id
        }
    }

    static func selectPart(id: UUID, on appModel: AppModel) {
        appModel.selectedPartID = id
    }

    static func selectedPart(in appModel: AppModel) -> CompiledPart? {
        guard let compiled = appModel.lastCompilation else { return nil }
        if let id = appModel.selectedPartID,
           let part = compiled.parts.first(where: { $0.id == id }) {
            return part
        }
        return compiled.parts.first
    }

    /// Metadata stamped onto a generation that still matches the compilation.
    static func stamp(
        forPrompt prompt: String,
        appModel: AppModel,
        setID: UUID?,
        setIndex: Int?,
        setTitle: String?
    ) -> DirectorStamp {
        let compiled = appModel.lastCompilation
        let matchingPart = compiled?.parts.first { $0.shapEPrompt == prompt }
        let usedDirector = matchingPart != nil || compiled?.shapEPrompt == prompt

        return DirectorStamp(
            userIntent: usedDirector ? appModel.directorIntent : nil,
            compiledPrompt: matchingPart?.shapEPrompt ?? (usedDirector ? compiled?.shapEPrompt : nil),
            directorRationale: usedDirector ? compiled?.rationale : nil,
            suggestedScale: usedDirector ? (matchingPart?.scale.rawValue ?? compiled?.scale.rawValue) : nil,
            suggestedMaterial: usedDirector ? (matchingPart?.material.rawValue ?? compiled?.material.rawValue) : nil,
            setID: setID,
            setIndex: setIndex,
            setTitle: setTitle
        )
    }
}

nonisolated struct DirectorStamp: Equatable, Sendable {
    var userIntent: String?
    var compiledPrompt: String?
    var directorRationale: String?
    var suggestedScale: String?
    var suggestedMaterial: String?
    var setID: UUID?
    var setIndex: Int?
    var setTitle: String?
}
