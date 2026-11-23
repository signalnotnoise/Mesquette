import XCTest
@testable import Mesquette

final class DirectorCompiledPromptTests: XCTestCase {
    func testNormalizesVariationCount() {
        var compiled = sampleSingle()
        compiled.variationCount = 0
        XCTAssertEqual(compiled.normalized().variationCount, 1)
        compiled.variationCount = 9
        XCTAssertEqual(compiled.normalized().variationCount, 4)
    }

    func testSetWithOnePartBecomesSingle() {
        var compiled = sampleSet()
        compiled.parts = [compiled.parts[0]]
        let normalized = compiled.normalized()
        XCTAssertEqual(normalized.kind, .single)
        XCTAssertEqual(normalized.parts.count, 1)
        XCTAssertEqual(normalized.parts[0].offsetX, 0)
        XCTAssertEqual(normalized.parts[0].offsetZ, 0)
    }

    func testSingleDropsExtraParts() {
        var compiled = sampleSingle()
        compiled.parts.append(
            CompiledPart(
                title: "Extra",
                shapEPrompt: "a spare mug",
                scale: .mug,
                material: .ceramic,
                offsetX: 1,
                offsetZ: 0
            )
        )
        let normalized = compiled.normalized()
        XCTAssertEqual(normalized.kind, .single)
        XCTAssertEqual(normalized.parts.count, 1)
        XCTAssertEqual(normalized.shapEPrompt, "a bronze owl figurine, perched")
    }

    func testEmptyPartsWrapsPrompt() {
        var compiled = sampleSingle()
        compiled.parts = []
        let normalized = compiled.normalized()
        XCTAssertEqual(normalized.parts.count, 1)
        XCTAssertEqual(normalized.parts[0].shapEPrompt, compiled.shapEPrompt)
    }

    func testSetUsesPlaceSettingSlotsNotLLMMeters() {
        let normalized = sampleSet().normalized()
        XCTAssertEqual(normalized.kind, .set)
        XCTAssertEqual(normalized.parts.count, 3)
        XCTAssertEqual(normalized.variationCount, 1)
        XCTAssertEqual(normalized.layout, .placeSetting)
        XCTAssertEqual(normalized.mood, "cozy morning")
        let croissant = normalized.parts.first { $0.title == "Croissant" }
        let mug = normalized.parts.first { $0.title == "Mug" }
        let vase = normalized.parts.first { $0.title == "Vase" }
        XCTAssertNotNil(croissant)
        XCTAssertNotNil(mug)
        XCTAssertNotNil(vase)
        XCTAssertEqual(mug!.slot, .heroCenter)
        XCTAssertEqual(mug!.offsetX, 0, accuracy: 0.01)
        XCTAssertEqual(mug!.offsetZ, 0, accuracy: 0.01)
        XCTAssertEqual(croissant!.slot, .leftHand)
        XCTAssertLessThan(croissant!.offsetX, mug!.offsetX)
        XCTAssertEqual(vase!.slot, .rightHand)
        XCTAssertGreaterThan(vase!.offsetX, mug!.offsetX)
        XCTAssertEqual(Set(normalized.parts.map(\.slot)).count, 3)
        XCTAssertTrue(normalized.parts.contains(where: \.isHero))
        XCTAssertEqual(mug!.scale, .mug)
    }

    func testNormalizedDropsCobblesThenSlots() {
        var compiled = sampleSet()
        compiled.parts.append(
            CompiledPart(title: "Wet Cobbles", shapEPrompt: "wet cobbles", scale: .figurine, material: .stone)
        )
        let normalized = compiled.normalized()
        XCTAssertEqual(normalized.parts.count, 3)
        XCTAssertFalse(normalized.parts.contains { $0.title.localizedCaseInsensitiveContains("cobble") })
    }

    func testObjectPromptStripsPoisonKeepsTheRest() {
        let cleaned = DirectorStaging.objectPrompt(
            "a pile of papers scattered across the desk, highly detailed, 8K, CAD"
        )
        XCTAssertTrue(cleaned.localizedCaseInsensitiveContains("desk"))
        XCTAssertTrue(cleaned.localizedCaseInsensitiveContains("scattered"))
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("highly detailed"))
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("8K"))
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("CAD"))
    }

    func testDropsTrackAndRingAsGround() {
        XCTAssertTrue(DirectorStaging.isGroundLike(
            CompiledPart(title: "Circular Track", shapEPrompt: "a circular racetrack ring", scale: .tabletop, material: .stone)
        ))
        XCTAssertTrue(DirectorStaging.isGroundLike(
            CompiledPart(title: "Ring", shapEPrompt: "a white hoop", scale: .figurine, material: .metal)
        ))
        XCTAssertFalse(DirectorStaging.isGroundLike(
            CompiledPart(title: "Jaguar", shapEPrompt: "a black Jaguar E-Type toy car", scale: .tabletop, material: .metal)
        ))
        XCTAssertFalse(DirectorStaging.isGroundLike(
            CompiledPart(title: "Roadster", shapEPrompt: "a vintage blue roadster", scale: .tabletop, material: .metal)
        ))
        XCTAssertFalse(DirectorStaging.isGroundLike(
            CompiledPart(title: "Spring", shapEPrompt: "a coiled spring during repair", scale: .figurine, material: .metal)
        ))
    }

    func testNormalizedDropsTrackKeepsCars() {
        var compiled = CompiledPrompt(
            kind: .set,
            title: "Race",
            shapEPrompt: "cars",
            scale: .tabletop,
            material: .metal,
            variationCount: 1,
            rationale: "Three cars.",
            layout: .arc,
            mood: "race",
            parts: [
                CompiledPart(title: "Jaguar", shapEPrompt: "a black Jaguar toy car", scale: .tabletop, material: .metal, isHero: true),
                CompiledPart(title: "Porsche", shapEPrompt: "a red Porsche toy car", scale: .tabletop, material: .metal),
                CompiledPart(title: "Track", shapEPrompt: "a circular racetrack", scale: .tabletop, material: .stone),
                CompiledPart(title: "Ferrari", shapEPrompt: "a blue Ferrari toy car", scale: .tabletop, material: .metal)
            ]
        )
        let normalized = compiled.normalized()
        XCTAssertEqual(normalized.parts.count, 3)
        XCTAssertFalse(normalized.parts.contains { $0.title.localizedCaseInsensitiveContains("track") })
    }

    func testDropsCobblesAndSeparatesOverlap() {
        let packed = [
            CompiledPart(title: "Church", shapEPrompt: "a compact gothic church", scale: .figurine, material: .stone, offsetX: 0.10, offsetZ: 0.01, isHero: true),
            CompiledPart(title: "Fountain", shapEPrompt: "a stone fountain", scale: .figurine, material: .stone, offsetX: 0.15, offsetZ: -0.09),
            CompiledPart(title: "Wet Cobbles", shapEPrompt: "wet cobbles", scale: .figurine, material: .stone, offsetX: 0.15, offsetZ: -0.14)
        ]
        let staged = DirectorStaging.separate(packed)
        XCTAssertFalse(staged.contains { $0.title.localizedCaseInsensitiveContains("cobble") })
        XCTAssertEqual(staged.count, 2)
        let d = hypot(staged[1].offsetX - staged[0].offsetX, staged[1].offsetZ - staged[0].offsetZ)
        XCTAssertGreaterThan(d, 0.5)
    }

    func testRecenterPullsClusterToOrigin() {
        let parts = [
            CompiledPart(title: "A", shapEPrompt: "a ceramic mug", scale: .mug, material: .ceramic, offsetX: 0.30, offsetZ: 0.50),
            CompiledPart(title: "B", shapEPrompt: "a paint jar", scale: .figurine, material: .glass, offsetX: 0.70, offsetZ: 0.20)
        ]
        let centered = DirectorStaging.recenter(parts)
        let cx = centered.map(\.offsetX).reduce(0, +) / Float(centered.count)
        let cz = centered.map(\.offsetZ).reduce(0, +) / Float(centered.count)
        XCTAssertEqual(cx, 0, accuracy: 0.01)
        XCTAssertEqual(cz, 0, accuracy: 0.01)
    }

    func testJSONRoundTrip() throws {
        let data = try JSONEncoder().encode(sampleSet())
        let decoded = try JSONDecoder().decode(CompiledPrompt.self, from: data)
        XCTAssertEqual(decoded.kind, .set)
        XCTAssertEqual(decoded.parts.map(\.title), ["Mug", "Croissant", "Vase"])
    }

    func testVehicleInferencesAndSanitization() {
        let scale = DirectorStaging.inferredScale(title: "Porsche", prompt: "a red Porsche 911 coupe", current: .figurine)
        XCTAssertEqual(scale, .tabletop)
        XCTAssertEqual(
            DirectorStaging.inferredScale(title: "Peak", prompt: "a snow-capped mountain", current: .figurine),
            .building
        )

        let material = DirectorStaging.inferredMaterial(title: "Racer", prompt: "a vintage roadster", current: .vertexColor)
        XCTAssertEqual(material, .metal)

        let cleaned = DirectorStaging.objectPrompt(
            "a red Ferrari racing around a circular track with sponsor decals and side mirrors, photorealistic"
        )
        XCTAssertTrue(cleaned.localizedCaseInsensitiveContains("track"))
        XCTAssertTrue(cleaned.localizedCaseInsensitiveContains("decals"))
        XCTAssertTrue(cleaned.localizedCaseInsensitiveContains("mirrors"))
        XCTAssertTrue(cleaned.localizedCaseInsensitiveContains("Ferrari"))
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("photorealistic"))
    }

    func testObjectPromptDoesNotClipLength() {
        let cleaned = DirectorStaging.objectPrompt(
            "a brass diving helmet, round viewport, riveted collar, verdigris, barrel neck, extra silhouette words that used to be chopped"
        )
        XCTAssertTrue(cleaned.localizedCaseInsensitiveContains("viewport"))
        XCTAssertTrue(cleaned.localizedCaseInsensitiveContains("verdigris"))
        XCTAssertTrue(cleaned.localizedCaseInsensitiveContains("chopped"))
    }

    private func sampleSingle() -> CompiledPrompt {
        CompiledPrompt(
            kind: .single,
            title: "Bronze owl",
            shapEPrompt: "a bronze owl figurine, perched",
            scale: .figurine,
            material: .metal,
            variationCount: 1,
            rationale: "One object.",
            layout: .cluster,
            mood: "",
            parts: [
                CompiledPart(
                    title: "Owl",
                    shapEPrompt: "a bronze owl figurine, perched",
                    scale: .figurine,
                    material: .metal
                )
            ]
        )
    }

    private func sampleSet() -> CompiledPrompt {
        CompiledPrompt(
            kind: .set,
            title: "Breakfast",
            shapEPrompt: "a ceramic coffee mug",
            scale: .mug,
            material: .ceramic,
            variationCount: 4,
            rationale: "Mug back left, croissant in front, vase to the right.",
            layout: .placeSetting,
            mood: "cozy morning",
            parts: [
                CompiledPart(title: "Mug", shapEPrompt: "a ceramic coffee mug, handle on the right", scale: .mug, material: .ceramic, offsetX: -0.18, offsetZ: 0.12, rotationY: 20, isHero: true),
                CompiledPart(title: "Croissant", shapEPrompt: "a golden croissant, flaky", scale: .figurine, material: .clay, offsetX: 0.02, offsetZ: -0.16, rotationY: -12),
                CompiledPart(title: "Vase", shapEPrompt: "a small round vase with a single flower", scale: .figurine, material: .ceramic, offsetX: 0.22, offsetZ: 0.08, rotationY: -25)
            ]
        )
    }
}
