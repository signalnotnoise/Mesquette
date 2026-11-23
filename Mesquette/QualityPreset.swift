// QualityPreset.swift
// Mesquette — Shared quality presets for 3D generation

import Foundation

/// User-facing quality ladder. Maps to concrete generation parameters.
///
/// - **preview**: Fast, safer on device; no live partial mesh extracts.
/// - **standard**: Balanced default for most prompts.
/// - **high**: Higher grid / steps (prefer macOS; can pressure iOS/visionOS).
enum QualityPreset: String, CaseIterable, Identifiable, Sendable {
    case preview
    case standard
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preview:  return "Preview"
        case .standard: return "Standard"
        case .high:     return "High"
        }
    }

    var subtitle: String {
        switch self {
        case .preview:  return "Fast drafts · low GPU load"
        case .standard: return "Balanced quality & speed"
        case .high:     return "Finer grid · longer run"
        }
    }

    var systemImage: String {
        switch self {
        case .preview:  return "hare"
        case .standard: return "square.grid.2x2"
        case .high:     return "sparkles"
        }
    }

    var numInferenceSteps: Int {
        switch self {
        case .preview:  return 16
        case .standard: return 32
        case .high:     return 64
        }
    }

    var gridSize: Int {
        switch self {
        case .preview:  return 48
        case .standard: return 64
        case .high:     return 128
        }
    }

    /// Live partial mesh extraction during sampling. Off for all presets by default
    /// (partials stack MLX + marching cubes + RealityKit and cause GPU hangs).
    var enableLivePartials: Bool { false }

    /// Metal marching cubes for the **final** extract only. Partials always use CPU
    /// when enabled, to reduce multi-queue contention.
    var usesGPUForFinalExtract: Bool {
        switch self {
        case .preview:  return false
        case .standard: return true
        case .high:     return true
        }
    }
}
