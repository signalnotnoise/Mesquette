// DirectorCompileBarViewModel.swift
// Mesquette — Compile intent with the on-device Foundation Model.

import Foundation
import Observation

@Observable
@MainActor
final class DirectorCompileBarViewModel {
    private let client: any DirectorServicing

    init(client: any DirectorServicing = DirectorClient()) {
        self.client = client
    }

    func refreshAvailability(appModel: AppModel) {
        appModel.directorAvailability = DirectorAvailabilityChecker.current()
    }

    func compile(appModel: AppModel) async {
        guard appModel.canCompile else { return }
        let intent = appModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        appModel.compileGeneration += 1
        let generation = appModel.compileGeneration
        appModel.isCompiling = true
        appModel.directorError = nil
        defer {
            if appModel.compileGeneration == generation {
                appModel.isCompiling = false
            }
        }

        do {
            let compiled = try await client.compile(intent: intent)
            guard appModel.compileGeneration == generation else { return }
            let current = appModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard current == intent else { return }
            DirectorSession.applyCompile(intent: intent, compiled: compiled, to: appModel)
        } catch let error as DirectorError {
            guard appModel.compileGeneration == generation else { return }
            appModel.directorError = error.localizedDescription
        } catch {
            guard appModel.compileGeneration == generation else { return }
            appModel.directorError = DirectorError.generationFailed(
                "Couldn’t compile that prompt. Try a shorter description."
            ).localizedDescription
        }
    }

    func invent(appModel: AppModel) async {
        guard appModel.canInvent else { return }
        let seed = appModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        appModel.compileGeneration += 1
        let generation = appModel.compileGeneration
        appModel.isInventing = true
        appModel.directorError = nil
        defer {
            if appModel.compileGeneration == generation {
                appModel.isInventing = false
            }
        }

        let avoiding = appModel.inventedPresets.map(\.title)
            + Array(PromptPresetLibrary.all.map(\.title).shuffled().prefix(12))

        do {
            let invented = try await client.inventPreset(
                seed: seed,
                avoidingTitles: avoiding
            )
            guard appModel.compileGeneration == generation else { return }
            DirectorSession.applyInvented(invented, to: appModel)
        } catch let error as DirectorError {
            guard appModel.compileGeneration == generation else { return }
            appModel.directorError = error.localizedDescription
        } catch {
            guard appModel.compileGeneration == generation else { return }
            appModel.directorError = DirectorError.generationFailed(
                "Couldn’t invent a scene. Try again, or pick a library idea."
            ).localizedDescription
        }
    }
}
