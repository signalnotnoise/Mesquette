// DirectorError.swift
// Mesquette — User-facing director failures (no secrets, no model dumps).

import Foundation

/// User-safe Director failures. Every Foundation Models error is mapped into
/// one of these before it reaches the UI.
nonisolated enum DirectorError: LocalizedError, Equatable, Sendable {
    case unavailable(String)
    case emptyIntent
    case emptyResult
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        case .emptyIntent:
            return "Describe what you want before compiling."
        case .emptyResult:
            return "Director returned an unusable prompt."
        case .generationFailed(let message):
            return message
        }
    }
}

nonisolated enum DirectorAvailability: Equatable, Sendable {
    case checking
    case available
    case unavailable(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .checking:
            return "Checking Apple Intelligence…"
        case .available:
            return "On-device Apple Intelligence"
        case .unavailable(let reason):
            return reason
        }
    }
}
