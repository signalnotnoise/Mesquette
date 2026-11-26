// DirectorClient.swift
// Mesquette — On-device director via Foundation Models.
//
// Not Core ML + a bundled LLM: Shap-E already occupies GPU/RAM through MLX.
// Foundation Models is the system Apple Intelligence LLM (no extra weights, no API key).
// Guided generation (@Generable) is the structured-output path.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
/// The Director surface `ContentViewModel` depends on. Composite flows
/// (e.g. `planPinsOrFallback`) may call several of these in sequence:
/// tagging first, then extras planning only when the budget allows.
protocol DirectorServicing {
    func compile(intent: String) async throws -> CompiledPrompt
    func inventPreset(seed: String, avoidingTitles: [String]) async throws -> InventedPreset
    func planPins(
        intent: String,
        pins: [PlacementPin],
        baseSeed: Int,
        alreadyOnTable: [String],
        allPins: [PlacementPin],
        mode: PinPlanMode
    ) async throws -> [PinAssignment]
    func tagSceneCast(from scene: String) async throws -> DirectorStaging.TaggedSceneCast
}

/// Foundation Models implementation. Every method checks availability first and
/// maps failures to `DirectorError`; sessions are created per call.
struct DirectorClient: DirectorServicing {
    func compile(intent: String) async throws -> CompiledPrompt {
        let trimmed = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DirectorError.emptyIntent }
        try requireAvailable()
        return try await compileOnDevice(intent: trimmed)
    }

    func inventPreset(seed: String, avoidingTitles: [String]) async throws -> InventedPreset {
        try requireAvailable()
        return try await inventOnDevice(
            seed: seed.trimmingCharacters(in: .whitespacesAndNewlines),
            avoidingTitles: avoidingTitles
        )
    }

    func planPins(
        intent: String,
        pins: [PlacementPin],
        baseSeed: Int,
        alreadyOnTable: [String],
        allPins: [PlacementPin],
        mode: PinPlanMode
    ) async throws -> [PinAssignment] {
        let trimmed = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DirectorError.emptyIntent }
        guard !pins.isEmpty else { throw DirectorError.emptyIntent }
        try requireAvailable()
        return try await planPinsOnDevice(
            intent: trimmed,
            pins: pins,
            baseSeed: baseSeed,
            alreadyOnTable: alreadyOnTable,
            allPins: allPins.isEmpty ? pins : allPins,
            mode: mode
        )
    }

    func tagSceneCast(from scene: String) async throws -> DirectorStaging.TaggedSceneCast {
        let trimmed = scene.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DirectorError.emptyIntent }
        try requireAvailable()
        return try await tagSceneCastOnDevice(scene: trimmed)
    }

    private func requireAvailable() throws {
        switch DirectorAvailabilityChecker.current() {
        case .available:
            break
        case .checking:
            throw DirectorError.unavailable("Apple Intelligence is not ready yet.")
        case .unavailable(let message):
            throw DirectorError.unavailable(message)
        }
    }

    private func compileOnDevice(intent: String) async throws -> CompiledPrompt {
#if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        let session = LanguageModelSession(
            model: model,
            instructions: DirectorSystemPrompt.text
        )
        do {
            let response = try await session.respond(
                to: Self.userPrompt(for: intent),
                generating: GenerableCompiledPrompt.self
            )
            let compiled = response.content.asCompiledPrompt()
            guard compiled.parts.contains(where: { !$0.shapEPrompt.isEmpty }) else {
                throw DirectorError.emptyResult
            }
            return compiled
        } catch let error as DirectorError {
            throw error
        } catch {
            throw DirectorError.generationFailed(
                "Couldn’t compile that prompt. Try a shorter description."
            )
        }
#else
        throw DirectorError.unavailable("This OS build does not include Foundation Models.")
#endif
    }

    private func inventOnDevice(seed: String, avoidingTitles: [String]) async throws -> InventedPreset {
#if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        let session = LanguageModelSession(
            model: model,
            instructions: DirectorSystemPrompt.inventText
        )
        do {
            let response = try await session.respond(
                to: Self.inventUserPrompt(seed: seed, avoidingTitles: avoidingTitles),
                generating: GenerableInventedPreset.self
            )
            let invented = response.content.asInventedPreset()
            guard !invented.prompt.isEmpty else { throw DirectorError.emptyResult }
            return invented
        } catch let error as DirectorError {
            throw error
        } catch {
            throw DirectorError.generationFailed(
                "Couldn’t invent a scene. Try again, or pick a library idea."
            )
        }
#else
        throw DirectorError.unavailable("This OS build does not include Foundation Models.")
#endif
    }

    private static let pinChunkSize = 8

    private func planPinsOnDevice(
        intent: String,
        pins: [PlacementPin],
        baseSeed: Int,
        alreadyOnTable: [String],
        allPins: [PlacementPin],
        mode: PinPlanMode
    ) async throws -> [PinAssignment] {
#if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        let instructions = mode == .scene
            ? DirectorSystemPrompt.scenePinPlanText
            : DirectorSystemPrompt.pinPlanText
        let session = LanguageModelSession(
            model: model,
            instructions: instructions
        )
        var planned: [PinAssignment] = []
        var usedTitles = alreadyOnTable
        let chunks = stride(from: 0, to: pins.count, by: Self.pinChunkSize).map { start in
            Array(pins[start..<min(start + Self.pinChunkSize, pins.count)])
        }
        do {
            for chunk in chunks {
                let response = try await session.respond(
                    to: Self.pinPlanningPrompt(
                        intent: intent,
                        chunk: chunk,
                        allPins: allPins,
                        alreadyOnTable: usedTitles,
                        mode: mode
                    ),
                    generating: GenerablePinPlanChunk.self
                )
                let items = response.content.items.map {
                    PlannedPinItem(
                        pinIndex: $0.pinIndex,
                        title: $0.title,
                        shapEPrompt: $0.shapEPrompt,
                        scale: $0.scale.asDirectorScale,
                        material: $0.material.asDirectorMaterial
                    )
                }
                let resolved = Self.assignmentsMatchingPinIndex(
                    items: items,
                    chunk: chunk,
                    allPins: allPins,
                    scene: intent,
                    baseSeed: baseSeed &+ planned.count,
                    alreadyKeys: Set(usedTitles.map { DirectorStaging.normalizedIdentityKey($0) })
                )
                planned.append(contentsOf: resolved.jobs)
                usedTitles.append(contentsOf: resolved.jobs.map(\.title))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as DirectorError {
            throw error
        } catch {
            if error is CancellationError { throw error }
            throw DirectorError.generationFailed(
                "Couldn’t plan objects for those pins. Try a shorter scene description."
            )
        }
        return planned
#else
        throw DirectorError.unavailable("This OS build does not include Foundation Models.")
#endif
    }

    /// One extras/scene item as returned by the model, before pin lookup.
    struct PlannedPinItem: Equatable, Sendable {
        var pinIndex: Int
        var title: String
        var shapEPrompt: String
        var scale: DirectorScale
        var material: DirectorMaterial
    }

    /// Match items to the listed pins by 1-based `pinIndex`. Invalid, duplicate,
    /// or generic prompts are skipped — never the whole scene, never a zip-by-order fill.
    static func assignmentsMatchingPinIndex(
        items: [PlannedPinItem],
        chunk: [PlacementPin],
        allPins: [PlacementPin],
        scene: String,
        baseSeed: Int,
        alreadyKeys: Set<String> = []
    ) -> (jobs: [PinAssignment], skipped: Int) {
        var pinForNumber: [Int: PlacementPin] = [:]
        for (i, pin) in allPins.enumerated() {
            pinForNumber[i + 1] = pin
        }
        let chunkIDs = Set(chunk.map(\.id))
        var claimed = Set<UUID>()
        var seen = alreadyKeys
        var jobs: [PinAssignment] = []
        var skipped = 0
        for (offset, item) in items.enumerated() {
            guard let pin = pinForNumber[item.pinIndex],
                  chunkIDs.contains(pin.id),
                  !claimed.contains(pin.id)
            else {
                skipped += 1
                continue
            }
            var title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { title = DirectorStaging.shortObjectTitle(item.shapEPrompt) }
            let prompt = DirectorStaging.objectPrompt(item.shapEPrompt)
            if DirectorStaging.objectPromptIssue(prompt, scene: scene) != nil {
                skipped += 1
                continue
            }
            let titleKey = DirectorStaging.normalizedIdentityKey(title)
            let promptKey = DirectorStaging.normalizedIdentityKey(prompt)
            if (!titleKey.isEmpty && seen.contains(titleKey))
                || (!promptKey.isEmpty && seen.contains(promptKey)) {
                skipped += 1
                continue
            }
            claimed.insert(pin.id)
            if !titleKey.isEmpty { seen.insert(titleKey) }
            if !promptKey.isEmpty { seen.insert(promptKey) }
            jobs.append(
                PinAssignment(
                    pinID: pin.id,
                    title: title,
                    shapEPrompt: prompt,
                    scale: item.scale,
                    material: item.material,
                    fillsToNeighbors: false,
                    seed: baseSeed &+ offset,
                    route: .extra
                )
            )
        }
        return (jobs, skipped)
    }

    private func tagSceneCastOnDevice(scene: String) async throws -> DirectorStaging.TaggedSceneCast {
#if canImport(FoundationModels)
        let model = SystemLanguageModel(useCase: .contentTagging)
        switch model.availability {
        case .available:
            break
        case .unavailable:
            throw DirectorError.unavailable("Content tagging is not available on this device.")
        @unknown default:
            throw DirectorError.unavailable("Content tagging is not available on this device.")
        }
        let session = LanguageModelSession(
            model: model,
            instructions: DirectorSystemPrompt.contentTagText
        )
        do {
            let response = try await session.respond(
                to: Self.sceneTagPrompt(scene: scene),
                generating: GenerableSceneCast.self
            )
            return response.content.asTaggedSceneCast()
        } catch let error as DirectorError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DirectorError.generationFailed(
                "Couldn’t tag objects in that scene. Try a shorter description."
            )
        }
#else
        throw DirectorError.unavailable("This OS build does not include Foundation Models.")
#endif
    }

    /// Visible for tests.
    static func sceneTagPrompt(scene: String) -> String {
        """
        Scene:
        \(scene)

        Tag every named closed object. One object per tag. \
        Knight under a pale moon is two objects: knight floor, moon airborne.
        """
    }

    /// Visible for tests. Empty pins only; `alreadyOnTable` is what is already sculpted.
    static func pinPlanningPrompt(
        intent: String,
        chunk: [PlacementPin],
        allPins: [PlacementPin],
        alreadyOnTable: [String],
        mode: PinPlanMode = .extras
    ) -> String {
        let lines = chunk.map { pin in
            let n = (allPins.firstIndex(where: { $0.id == pin.id }) ?? 0) + 1
            let height = pin.y >= PlacementPin.airborneThreshold ? "airborne" : "floor"
            return "Pin \(n): x \(String(format: "%.2f", pin.x)) y \(String(format: "%.2f", pin.y)) z \(String(format: "%.2f", pin.z)) (\(height))"
        }.joined(separator: "\n")
        let used = alreadyOnTable.isEmpty ? "none" : alreadyOnTable.joined(separator: ", ")
        let job = mode == .scene
            ? """
            Assign the objects named in this scene onto these pins. \
            Split spatial phrases: a knight under a pale moon → knight on a floor pin, moon on an airborne pin. \
            Do not paste the whole sentence into every shapEPrompt. \
            pinIndex is the Pin N number below. Skip a pin rather than invent a generic object.
            """
            : """
            These leftover pins may receive complementary dressing for the SAME scene. \
            pinIndex is the Pin N number below. One concrete named object per item. \
            If you cannot name a real object for a pin, omit that pin. \
            Do not invent a forest or a new cast.
            """
        return """
        Scene:
        \(intent)

        Already placed (do not repeat): \(used)

        \(job)
        \(lines)

        Do not emit Euler angles. Code plants as generated.
        """
    }

    private static func userPrompt(for intent: String) -> String {
        """
        Direct this intent for Shap-E.

        Settings are allowed: mood + layout + optional chunky landmarks. The ground \
        of the setting (track, road, sea, cobbles) is the studio floor — never a mesh.

        If the user named specific objects, emit those as required parts. You may add \
        at most two set-dressing props that belong to the setting. Do not pad to 5–6. \
        Three named cars → three streamlined sports cars (coupe, roadster, fastback), layout arc or row, metal. No ring or track. Never write tabletop or diorama into shapEPrompt.

        If it is only a mood and they named no objects, invent 5 to 6 distinctive \
        closed volumes for THAT world (landmark hero plus tools, creatures, furniture, \
        machines). Do not default to mug, jam jar, croissant, or closed book. \
        Never emit cobbles, ground, track, or weather. One creature, vehicle, or \
        building → compress to a single prompt.

        Intent:
        \(intent)
        """
    }

    private static let spices: [String] = [
        "Kyoto dusk", "Antarctic hut", "jazz club after hours", "Venetian glass workshop",
        "Andean market", "Baltic sauna", "Saharan caravanserai", "Coney Island boardwalk",
        "Trans-Siberian sleeper", "Oaxacan chocolate mill", "Shetland knitters' parlor",
        "1968 recording booth", "Malian dye pit", "Alpine hut at blue hour",
        "Macau herbal hall", "Patagonian estancia", "Istanbul copper souk",
        "New Orleans brass shop", "Faroe boathouse", "Tbilisi wine cellar",
        "Hokkaido onsen porch", "Zanzibar spice loft", "Yorkshire tackle shed",
        "Lisbon tile atelier", "Yukon trapper cabin",
    ]

    private static func inventUserPrompt(seed: String, avoidingTitles: [String]) -> String {
        let spice = spices.randomElement() ?? "harbor dusk"
        let avoid = avoidingTitles.prefix(16).joined(separator: ", ")
        let hint = seed.isEmpty
            ? "No user hint — surprise. Do not default to bakery, breakfast, a writing desk, or tableware."
            : "Honor this user hint as the theme:\n\(seed)"
        return """
        Invent ONE new Mesquette scene preset.

        Spice (must flavor the setting): \(spice)
        Avoid these titles: \(avoid.isEmpty ? "none" : avoid)

        \(hint)
        """
    }
}
