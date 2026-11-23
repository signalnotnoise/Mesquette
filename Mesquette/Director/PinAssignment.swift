// PinAssignment.swift
// Mesquette — Per-pin Shap-E job. Pins are the scene list; no compile.

import Foundation

/// How the director fills empty pins.
enum PinPlanMode: Sendable {
    /// Leftover pins after code placed a comma-separated named cast.
    case extras
    /// No named list — split the user's scene onto these pins, honoring floor vs airborne.
    case scene
}

/// How a pin job was produced. Logged so a screenshot can tell named vs extras vs fallback.
nonisolated enum PinPlanRoute: String, Equatable, Sendable {
    case named
    case extra
    case fallback
}

nonisolated struct PinAssignment: Equatable, Sendable, Identifiable {
    var id: UUID { pinID }
    var pinID: UUID
    var title: String
    var shapEPrompt: String
    var scale: DirectorScale
    var material: DirectorMaterial
    var fillsToNeighbors: Bool
    var seed: Int
    var inventoryID: UUID? = nil
    var route: PinPlanRoute = .named

    static func looksLikeFill(title: String, prompt: String) -> Bool {
        let blob = (title + " " + prompt).lowercased()
        let keys = [
            "forest", "woods", "grove", "trees", "canopy", "thicket",
            "sea", "ocean", "lake", "kelp", "reef patch",
            "grass", "meadow", "undergrowth",
            "forest patch", "sea swell", "grass patch", "meadow patch", "moss patch"
        ]
        return keys.contains { DirectorStaging.containsToken(blob, $0) }
    }
}
