// ContentViewViewModel+Planning.swift
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

    static func planPinsOrFallback(
        client: DirectorClient,
        scene: String,
        empty: [PlacementPin],
        already: [String],
        alreadyIDs: Set<UUID>,
        allPins: [PlacementPin],
        seed: Int,
        extrasBudget: Int
    ) async throws -> (jobs: [PinAssignment], note: String) {
        let tagged = await tagSceneCastOrNil(client: client, scene: scene)
        let cast = DirectorStaging.resolvedCast(scene: scene, tagged: tagged)
        let split = DirectorStaging.namedPinJobs(
            empty: empty,
            allPins: allPins,
            cast: cast,
            already: already,
            seed: seed,
            alreadyIDs: alreadyIDs
        )
        PlacementDebug.log(
            "cast \(cast.objects.map { "\($0.title)(\($0.prefersAirborne ? "air" : "floor"))" }.joined(separator: ", "))"
        )

        var jobs = split.jobs
        var extrasFailed = false
        var extras: [PinAssignment] = []
        let budgeted = extrasBudget <= 0 ? [] : Array(split.extraPins.prefix(extrasBudget))
        if !budgeted.isEmpty {
            do {
                extras = try await planExtraPins(
                    client: client,
                    scene: scene,
                    extraPins: budgeted,
                    already: already + jobs.map(\.title),
                    allPins: allPins,
                    setting: split.setting,
                    seed: seed &+ jobs.count
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                PlacementDebug.log("extra pin plan failed — skip leftovers: \(error)")
                extrasFailed = true
                extras = []
            }
        }
        jobs += extras

        if jobs.isEmpty {
            jobs = DirectorStaging.fallbackPinJobs(
                pins: empty,
                scene: scene,
                seed: seed,
                already: already,
                allPins: allPins
            )
        }

        let named = jobs.filter { $0.route == .named || $0.route == .fallback }.count
        let extraCount = jobs.filter { $0.route == .extra }.count
        let leftover = max(0, empty.count - jobs.count)
        let note = DirectorStaging.summarizePinPlan(
            named: named,
            extras: extraCount,
            leftoverPins: leftover,
            extrasBudget: extrasBudget,
            extrasFailed: extrasFailed || (extrasBudget > 0 && extraCount == 0 && !budgeted.isEmpty)
        )
        return (jobs, note)
    }

    static func tagSceneCastOrNil(
        client: DirectorClient,
        scene: String
    ) async -> DirectorStaging.TaggedSceneCast? {
        let planTask = Task { @MainActor in
            try await client.tagSceneCast(from: scene)
        }
        let timeoutTask = Task {
            // Hard timeout (documented exception): tagging must never block Generate.
            try await Task.sleep(for: .seconds(25))
            planTask.cancel()
        }
        defer {
            planTask.cancel()
            timeoutTask.cancel()
        }
        do {
            let tagged = try await planTask.value
            if tagged.objects.isEmpty { return nil }
            return tagged
        } catch is CancellationError {
            if Task.isCancelled { return nil }
            PlacementDebug.log("content tag timed out — code cast")
            return nil
        } catch {
            if Task.isCancelled { return nil }
            PlacementDebug.log("content tag failed — code cast: \(error)")
            return nil
        }
    }

    static func planExtraPins(
        client: DirectorClient,
        scene: String,
        extraPins: [PlacementPin],
        already: [String],
        allPins: [PlacementPin],
        setting: String,
        seed: Int
    ) async throws -> [PinAssignment] {
        let extraIntent = """
        Scene: \(scene)
        Setting: \(setting)
        Already placed: \(already.isEmpty ? "none" : already.joined(separator: ", "))
        Invent complementary objects that belong in THIS scene only. \
        Name each object. Omit a pin rather than write a generic prop. \
        Do not invent trees, forests, mountains, or a new biome.
        """
        let planTask = Task { @MainActor in
            try await client.planPins(
                intent: extraIntent,
                pins: extraPins,
                baseSeed: seed,
                alreadyOnTable: already,
                allPins: allPins,
                mode: .extras
            )
        }
        let timeoutTask = Task {
            // Hard timeout (documented exception): extras are optional dressing.
            try await Task.sleep(for: .seconds(40))
            planTask.cancel()
        }
        defer {
            planTask.cancel()
            timeoutTask.cancel()
        }
        do {
            let extras = try await planTask.value
            return extras
        } catch is CancellationError {
            if Task.isCancelled { throw CancellationError() }
            PlacementDebug.log("extra pin plan timed out — leave leftover pins empty")
            return []
        } catch {
            if Task.isCancelled { throw CancellationError() }
            PlacementDebug.log("extra pin plan failed — leave leftover pins empty: \(error)")
            return []
        }
    }
}
