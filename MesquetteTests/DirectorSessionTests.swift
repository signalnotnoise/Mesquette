import XCTest
@testable import Mesquette

@MainActor
final class DirectorSessionTests: XCTestCase {
    func testApplySingleOverwritesPrompt() {
        let app = AppModel()
        app.prompt = "cute bronze owl for my desk"
        let compiled = CompiledPrompt(
            kind: .single,
            title: "Owl",
            shapEPrompt: "a bronze owl figurine, perched",
            scale: .figurine,
            material: .metal,
            variationCount: 1,
            rationale: "Compressed to one subject.",
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
        DirectorSession.applyCompile(intent: "cute bronze owl for my desk", compiled: compiled, to: app)
        XCTAssertEqual(app.prompt, "a bronze owl figurine, perched")
        XCTAssertEqual(app.directorIntent, "cute bronze owl for my desk")
        XCTAssertEqual(app.lastCompilation?.kind, .single)
    }

    func testApplySetDoesNotSmashPrompt() {
        let app = AppModel()
        app.prompt = "breakfast on the table"
        let compiled = CompiledPrompt(
            kind: .set,
            title: "Breakfast",
            shapEPrompt: "a ceramic coffee mug",
            scale: .mug,
            material: .ceramic,
            variationCount: 1,
            rationale: "Separate objects.",
            layout: .placeSetting,
            mood: "cozy morning",
            parts: [
                CompiledPart(title: "Mug", shapEPrompt: "a ceramic coffee mug", scale: .mug, material: .ceramic, offsetX: -0.2, offsetZ: 0.1, isHero: true),
                CompiledPart(title: "Plate", shapEPrompt: "a round breakfast plate", scale: .tabletop, material: .ceramic, offsetX: 0.2, offsetZ: -0.1)
            ]
        )
        DirectorSession.applyCompile(intent: "breakfast on the table", compiled: compiled, to: app)
        XCTAssertEqual(app.prompt, "breakfast on the table")
        XCTAssertEqual(app.lastCompilation?.kind, .set)
        XCTAssertEqual(app.lastCompilation?.parts.count, 2)
    }

    func testRevertRestoresIntent() {
        let app = AppModel()
        app.prompt = "cute bronze owl"
        let compiled = CompiledPrompt(
            kind: .single,
            title: "Owl",
            shapEPrompt: "a bronze owl figurine, perched",
            scale: .figurine,
            material: .metal,
            variationCount: 1,
            rationale: "One object.",
            layout: .cluster,
            mood: "",
            parts: [
                CompiledPart(title: "Owl", shapEPrompt: "a bronze owl figurine, perched", scale: .figurine, material: .metal)
            ]
        )
        DirectorSession.applyCompile(intent: "cute bronze owl", compiled: compiled, to: app)
        DirectorSession.revert(to: app)
        XCTAssertEqual(app.prompt, "cute bronze owl")
        XCTAssertNil(app.lastCompilation)
        XCTAssertNil(app.directorIntent)
        XCTAssertNil(app.selectedPartID)
    }

    func testUseFirstPartCollapsesSet() {
        let app = AppModel()
        app.prompt = "breakfast on the table"
        let compiled = CompiledPrompt(
            kind: .set,
            title: "Breakfast",
            shapEPrompt: "a ceramic coffee mug",
            scale: .mug,
            material: .ceramic,
            variationCount: 1,
            rationale: "Separate objects.",
            layout: .placeSetting,
            mood: "cozy morning",
            parts: [
                CompiledPart(title: "Mug", shapEPrompt: "a ceramic coffee mug", scale: .mug, material: .ceramic, offsetX: -0.2, offsetZ: 0.1, isHero: true),
                CompiledPart(title: "Plate", shapEPrompt: "a round breakfast plate", scale: .tabletop, material: .ceramic, offsetX: 0.2, offsetZ: -0.1)
            ]
        )
        DirectorSession.applyCompile(intent: "breakfast on the table", compiled: compiled, to: app)
        DirectorSession.useFirstPart(on: app)
        XCTAssertEqual(app.prompt, "a ceramic coffee mug")
        XCTAssertEqual(app.lastCompilation?.kind, .single)
        XCTAssertEqual(app.lastCompilation?.parts.count, 1)
    }

    func testApplyInventedFillsPromptAndPinsForYou() {
        let app = AppModel()
        app.prompt = ""
        app.lastCompilation = CompiledPrompt(
            kind: .single,
            title: "Old",
            shapEPrompt: "a leftover mug",
            scale: .mug,
            material: .ceramic,
            variationCount: 1,
            rationale: "old",
            layout: .cluster,
            mood: "",
            parts: [
                CompiledPart(title: "Mug", shapEPrompt: "a leftover mug", scale: .mug, material: .ceramic)
            ]
        )
        let invented = InventedPreset(
            title: "Copper Souk",
            prompt: "an Istanbul copper souk stall at dusk: a beaten copper ewer as the hero, a stack of trays, a brass lantern, a clay water jug, warm metal and indigo shadow",
            mood: "warm dusk"
        )
        let preset = DirectorSession.applyInvented(invented, to: app)
        XCTAssertEqual(app.prompt, invented.prompt)
        XCTAssertEqual(app.inputMode, .text)
        XCTAssertNil(app.lastCompilation)
        XCTAssertNil(app.directorIntent)
        XCTAssertEqual(app.inventedPresets.count, 1)
        XCTAssertEqual(app.inventedPresets.first?.title, "Copper Souk")
        XCTAssertEqual(preset.id, app.inventedPresets.first?.id)
        let framed = InventedPreset(
            title: "Booth",
            prompt: "a sound booth as a tabletop diorama: a guitar, a stool",
            mood: "warm"
        )
        XCTAssertTrue(framed.asPromptPreset().prompt.localizedCaseInsensitiveContains("tabletop"))
        XCTAssertTrue(framed.asPromptPreset().prompt.localizedCaseInsensitiveContains("guitar"))
        DirectorSession.applyInvented(invented, to: app)
        XCTAssertEqual(app.inventedPresets.count, 1)
    }

    func testApplyInventedCapsAtTwelve() {
        let app = AppModel()
        for i in 1...13 {
            DirectorSession.applyInvented(
                InventedPreset(title: "Scene \(i)", prompt: "a chunky scene \(i) with a mug, a lantern, and a crate", mood: "test"),
                to: app
            )
        }
        XCTAssertEqual(app.inventedPresets.count, 12)
        XCTAssertEqual(app.inventedPresets.first?.title, "Scene 13")
        XCTAssertEqual(app.inventedPresets.last?.title, "Scene 2")
    }

    func testStampDoesNotAttachLeftoverCompileToPinJobs() {
        let app = AppModel()
        let compiled = CompiledPrompt(
            kind: .set,
            title: "Breakfast",
            shapEPrompt: "a ceramic coffee mug",
            scale: .mug,
            material: .ceramic,
            variationCount: 1,
            rationale: "Separate objects.",
            layout: .placeSetting,
            mood: "cozy morning",
            parts: [
                CompiledPart(title: "Mug", shapEPrompt: "a ceramic coffee mug", scale: .mug, material: .ceramic, isHero: true),
                CompiledPart(title: "Plate", shapEPrompt: "a round breakfast plate", scale: .tabletop, material: .ceramic)
            ]
        )
        DirectorSession.applyCompile(intent: "breakfast on the table", compiled: compiled, to: app)
        let stamp = DirectorSession.stamp(
            forPrompt: "a gnarled oak",
            appModel: app,
            setID: UUID(),
            setIndex: 0,
            setTitle: "forest"
        )
        XCTAssertNil(stamp.userIntent)
        XCTAssertNil(stamp.compiledPrompt)
        XCTAssertNil(stamp.directorRationale)
        XCTAssertNil(stamp.suggestedScale)
        XCTAssertNil(stamp.suggestedMaterial)
        XCTAssertEqual(stamp.setTitle, "forest")
    }

    func testStampMatchesCompiledPartPrompt() {
        let app = AppModel()
        let compiled = CompiledPrompt(
            kind: .set,
            title: "Breakfast",
            shapEPrompt: "a ceramic coffee mug",
            scale: .mug,
            material: .ceramic,
            variationCount: 1,
            rationale: "Separate objects.",
            layout: .placeSetting,
            mood: "cozy morning",
            parts: [
                CompiledPart(title: "Mug", shapEPrompt: "a ceramic coffee mug", scale: .mug, material: .ceramic, isHero: true),
                CompiledPart(title: "Plate", shapEPrompt: "a round breakfast plate", scale: .tabletop, material: .ceramic)
            ]
        )
        DirectorSession.applyCompile(intent: "breakfast on the table", compiled: compiled, to: app)
        let stamp = DirectorSession.stamp(
            forPrompt: "a ceramic coffee mug",
            appModel: app,
            setID: UUID(),
            setIndex: 0,
            setTitle: "Breakfast"
        )
        XCTAssertEqual(stamp.userIntent, "breakfast on the table")
        XCTAssertEqual(stamp.compiledPrompt, "a ceramic coffee mug")
        XCTAssertEqual(stamp.directorRationale, "Separate objects.")
        XCTAssertEqual(stamp.suggestedScale, DirectorScale.mug.rawValue)
        XCTAssertEqual(stamp.suggestedMaterial, DirectorMaterial.ceramic.rawValue)
    }

    func testApplyVariationsSetsBatchSize() {
        let app = AppModel()
        app.batchSize = 1
        let compiled = CompiledPrompt(
            kind: .single,
            title: "Owl",
            shapEPrompt: "a bronze owl figurine, perched",
            scale: .figurine,
            material: .metal,
            variationCount: 4,
            rationale: "Variations.",
            layout: .cluster,
            mood: "",
            parts: [
                CompiledPart(title: "Owl", shapEPrompt: "a bronze owl figurine, perched", scale: .figurine, material: .metal)
            ]
        )
        DirectorSession.applyCompile(intent: "owl", compiled: compiled, to: app)
        DirectorSession.applyVariations(to: app)
        XCTAssertEqual(app.batchSize, 4)
    }
}
