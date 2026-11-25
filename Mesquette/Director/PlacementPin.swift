// PlacementPin.swift
// Mesquette — User-clicked table points. Beat LLM slots when present.

import Foundation

nonisolated enum PinFillState: String, Equatable, Sendable {
    case empty
    case busy
    case filled
}

/// A user-clicked table point in meters (+X right, Y height, +Z toward user).
/// `y` is clamped to `0...maxHeight`; `recordID` is the two-sided pin binding.
nonisolated struct PlacementPin: Identifiable, Equatable, Sendable {
    var id: UUID
    /// Right on the table, meters.
    var x: Float
    /// Height above the table, meters.
    var y: Float
    /// Toward the camera (+Z), meters.
    var z: Float
    /// Generation that currently occupies this pin, if any.
    var recordID: UUID?

    init(id: UUID = UUID(), x: Float, y: Float = 0, z: Float, recordID: UUID? = nil) {
        self.id = id
        self.x = x
        self.y = min(Self.maxHeight, max(0, y))
        self.z = z
        self.recordID = recordID
    }

    static let maxCount = 100
    /// Tabletop sky. Mountains sit on the floor; birds/planes/clouds use height.
    static let maxHeight: Float = 2.4
    static let airborneThreshold: Float = 0.15
}
