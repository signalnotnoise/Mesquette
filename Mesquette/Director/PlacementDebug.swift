// PlacementDebug.swift
// Mesquette — Console traces for pin sit / scale / yaw.
// Filter Console (or Xcode) by subsystem = bundle id, category "place".

import Foundation
import os

enum PlacementDebug {
    static var enabled = true

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.visionarydevops.Mesquette",
        category: "place"
    )

    static func log(_ message: String) {
        guard enabled else { return }
        // Messages may include user prompt fragments: keep them private.
        logger.debug("[place] \(message, privacy: .private)")
    }
}
