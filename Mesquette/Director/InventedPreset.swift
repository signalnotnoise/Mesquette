// InventedPreset.swift
// Mesquette — LLM-written scene brief, same shape as a library preset.

import Foundation

/// A director-invented idea, ready to drop into the prompt field.
/// One Director-invented scene preset (title + brief) before it becomes a `PromptPreset`.
nonisolated struct InventedPreset: Equatable, Sendable {
    var title: String
    var prompt: String
    var mood: String

    func asPromptPreset() -> PromptPreset {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedTitle.isEmpty ? "Invented scene" : trimmedTitle
        return PromptPreset(
            id: "invented-\(UUID().uuidString)",
            title: name,
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            category: .scenes,
            systemImage: "dice.fill"
        )
    }
}
