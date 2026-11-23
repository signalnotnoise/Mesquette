// PlacementDebug.swift
// Mesquette — Console traces for pin sit / scale / yaw. Search Xcode for [Mesquette][place].

import Foundation

enum PlacementDebug {
    static var enabled = true

    static func log(_ message: String) {
        guard enabled else { return }
        print("[Mesquette][place] \(message)")
    }
}
