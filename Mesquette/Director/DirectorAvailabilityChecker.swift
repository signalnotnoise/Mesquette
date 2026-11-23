// DirectorAvailabilityChecker.swift
// Mesquette — On-device Apple Intelligence, not a bundled Core ML LLM.

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

nonisolated enum DirectorAvailabilityChecker {
    /// Foundation Models is the on-device LLM already on the system.
    /// Do not load a third-party LLM via Core ML: Shap-E already owns GPU/RAM via MLX.
    static func current() -> DirectorAvailability {
#if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(message(for: reason))
        @unknown default:
            return .unavailable("Apple Intelligence is not available on this device.")
        }
#else
        return .unavailable("This OS build does not include Foundation Models.")
#endif
    }

#if canImport(FoundationModels)
    private static func message(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This device does not support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings to use Director."
        case .modelNotReady:
            return "Apple Intelligence is still downloading. Try again in a moment."
        @unknown default:
            return "Apple Intelligence is not available right now."
        }
    }
#endif
}
