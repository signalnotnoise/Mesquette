// ContentViewViewModel+Progress.swift
// Mesquette — Split from ContentViewViewModel.swift verbatim (pure code motion).

import SwiftUI
import RealityKit
import RuntimeWrapper
import ShapERuntime
import MLX
#if canImport(UIKit)
import UIKit
#endif

extension ContentViewModel {

    func phaseWeight(_ phase: String) -> Int {
        switch phase {
        case "embedding": return 0
        case "sampling": return 1
        case "projecting": return 2
        // Final extract sub-stages (in order)
        case "volume": return 3
        case "meshing": return 4
        case "colors": return 5
        case "resolving": return 6
        case "extracting": return 3 // legacy single-shot extract
        default: return -1
        }
    }

    func phaseLabel(_ phase: String, step: Int, total: Int) -> String {
        switch phase {
        case "embedding":
            return "Embedding"
        case "sampling":
            return total > 1 ? "Sampling \(step)/\(total)" : "Sampling"
        case "projecting":
            return "Projecting latent"
        case "volume":
            return total > 1 ? "Volume sample \(step)/\(total)" : "Sampling volume"
        case "meshing":
            return total > 1 ? "Meshing \(step)/\(total)" : "Building mesh"
        case "colors":
            return total > 1 ? "Vertex colors \(step)/\(total)" : "Vertex colors"
        case "resolving":
            return "Finalizing geometry"
        case "extracting":
            return "Extracting mesh"
        default:
            return "Generating"
        }
    }

    /// Maps phase + step into a monotonic-ish 0…1 overall progress for the UI bar.
    ///
    /// Spans: embed 0–5%, sample 5–70%, project 70–75%,
    /// volume 75–90%, meshing 90–93%, colors 93–98%, resolve 98–100%.
    func overallProgress(phase: String, currentStep: Int, totalSteps: Int) -> Double {
        let safeTotal = max(totalSteps, 1)
        let local = min(1.0, max(0.0, Double(currentStep) / Double(safeTotal)))
        switch phase {
        case "embedding":
            return 0.05 * local
        case "sampling":
            return 0.05 + 0.65 * local
        case "projecting":
            return 0.70 + 0.05 * local
        case "volume":
            return 0.75 + 0.15 * local
        case "meshing":
            return 0.90 + 0.03 * local
        case "colors":
            return 0.93 + 0.05 * local
        case "resolving":
            return 0.98 + 0.02 * local
        case "extracting":
            return 0.75 + 0.25 * local
        default:
            return appProgressFloor(for: phase)
        }
    }

    func appProgressFloor(for phase: String) -> Double {
        switch phaseWeight(phase) {
        case 0: return 0.0
        case 1: return 0.05
        case 2: return 0.70
        case 3: return 0.75
        case 4: return 0.90
        case 5: return 0.93
        case 6: return 0.98
        default: return 0.0
        }
    }
}
