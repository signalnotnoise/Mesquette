// DirectorResultCardViewModel.swift
// Mesquette — Actions on a compiled single prompt or laid-out set.

import Foundation
import Observation

@Observable
@MainActor
/// Presentation state for a compiled set card (selection, part removal, generate-set).
final class DirectorResultCardViewModel {
    func revert(appModel: AppModel) {
        DirectorSession.revert(to: appModel)
    }

    func useFirstPart(appModel: AppModel) {
        DirectorSession.useFirstPart(on: appModel)
    }

    func applyVariations(appModel: AppModel) {
        DirectorSession.applyVariations(to: appModel)
    }

    func removePart(id: UUID, appModel: AppModel) {
        DirectorSession.removePart(id: id, on: appModel)
    }

    func selectPart(id: UUID, appModel: AppModel) {
        DirectorSession.selectPart(id: id, on: appModel)
    }

    func layoutSummary(for compiled: CompiledPrompt) -> String {
        guard compiled.kind == .set else { return compiled.rationale }
        let names = compiled.parts.map(\.title).joined(separator: " · ")
        return "Scene: \(names)"
    }
}
