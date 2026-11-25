// DirectorAvailabilityViewModel.swift
// Mesquette — Apple Intelligence status for Settings / About.

import Foundation
import Observation

@Observable
@MainActor
/// Polls `DirectorAvailabilityChecker` into view-ready availability state.
final class DirectorAvailabilityViewModel {
    func refresh(appModel: AppModel) {
        appModel.directorAvailability = DirectorAvailabilityChecker.current()
    }

    var headline: String { "Director" }

    var detail: String {
        "Director uses Apple’s on-device Foundation Model (Apple Intelligence) to rewrite prompts and lay out multi-object scenes. It does not load a separate Core ML LLM, so it will not fight Shap-E for GPU memory."
    }
}
