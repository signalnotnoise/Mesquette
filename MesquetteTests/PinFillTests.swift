import XCTest
@testable import Mesquette

@MainActor
final class PinFillTests: XCTestCase {

    func testNewPinsAreEmpty() {
        let app = AppModel()
        app.addPlacementPin(x: 1, z: 2)
        app.addPlacementPin(x: 3, z: 4)
        XCTAssertEqual(app.emptyPlacementPins.count, 2)
        XCTAssertEqual(app.pinFillState(app.placementPins[0]), .empty)
        XCTAssertTrue(app.titlesOnTable.isEmpty)
    }

    func testBindMakesPinBusyUntilMeshOrFailure() {
        let app = AppModel()
        app.addPlacementPin(x: 1, z: 2)
        let pinID = app.placementPins[0].id
        let rec = GenerationRecord(prompt: "a guitar", partTitle: "Guitar")
        app.generationDict[rec.id] = rec
        app.generationOrder.append(rec.id)
        app.bindPin(pinID, to: rec.id)

        XCTAssertEqual(app.placementPins[0].recordID, rec.id)
        XCTAssertEqual(app.generationDict[rec.id]?.pinID, pinID)
        XCTAssertEqual(app.pinFillState(app.placementPins[0]), .empty)
        app.isGenerating = true
        XCTAssertEqual(app.pinFillState(app.placementPins[0]), .busy)
        XCTAssertTrue(app.emptyPlacementPins.isEmpty)
        app.isGenerating = false
        XCTAssertEqual(app.pinFillState(app.placementPins[0]), .empty)

        var failed = rec
        failed.status = .failed("nope")
        app.generationDict[rec.id] = failed
        XCTAssertEqual(app.pinFillState(app.placementPins[0]), .empty)
        XCTAssertEqual(app.emptyPlacementPins.count, 1)
    }

    func testRemoveGenerationUnbindsPin() {
        let app = AppModel()
        app.addPlacementPin(x: 0, z: 0)
        let pinID = app.placementPins[0].id
        let rec = GenerationRecord(prompt: "a stool", partTitle: "Stool")
        app.generationDict[rec.id] = rec
        app.generationOrder.append(rec.id)
        app.bindPin(pinID, to: rec.id)
        app.removeGeneration(id: rec.id)
        XCTAssertNil(app.placementPins[0].recordID)
        XCTAssertNil(app.generationDict[rec.id])
        XCTAssertEqual(app.emptyPlacementPins.count, 1)
    }

    func testUnbindClearsBothSidesOfPinRelationship() {
        let app = AppModel()
        app.addPlacementPin(x: 0, z: 0)
        let pinID = app.placementPins[0].id
        let rec = GenerationRecord(prompt: "a stool", partTitle: "Stool")
        app.generationDict[rec.id] = rec
        app.generationOrder.append(rec.id)
        app.bindPin(pinID, to: rec.id)
        app.unbindPin(pinID)
        XCTAssertNil(app.placementPins[0].recordID)
        XCTAssertNil(app.generationDict[rec.id]?.pinID)
    }

    func testBindPinClearsPreviousRecordOwnership() {
        let app = AppModel()
        app.addPlacementPin(x: 0, z: 0)
        let pinID = app.placementPins[0].id
        let old = GenerationRecord(prompt: "old", partTitle: "Old")
        let new = GenerationRecord(prompt: "new", partTitle: "New")
        app.generationDict[old.id] = old
        app.generationDict[new.id] = new
        app.generationOrder = [old.id, new.id]
        app.bindPin(pinID, to: old.id)
        app.bindPin(pinID, to: new.id)
        XCTAssertNil(app.generationDict[old.id]?.pinID)
        XCTAssertEqual(app.generationDict[new.id]?.pinID, pinID)
        XCTAssertEqual(app.placementPins[0].recordID, new.id)
    }

    func testRemoveGenerationDoesNotUnbindReplacedPin() {
        let app = AppModel()
        app.addPlacementPin(x: 0, z: 0)
        let pinID = app.placementPins[0].id
        let old = GenerationRecord(prompt: "failed jar", partTitle: "Jar")
        let new = GenerationRecord(prompt: "iron knight", partTitle: "Knight")
        app.generationDict[old.id] = old
        app.generationDict[new.id] = new
        app.generationOrder = [old.id, new.id]
        app.bindPin(pinID, to: old.id)
        app.bindPin(pinID, to: new.id)

        var stale = app.generationDict[old.id]!
        stale.pinID = pinID
        app.generationDict[old.id] = stale

        app.removeGeneration(id: old.id)
        XCTAssertNil(app.generationDict[old.id])
        XCTAssertEqual(app.placementPins[0].recordID, new.id)
        XCTAssertEqual(app.generationDict[new.id]?.pinID, pinID)
    }

    func testPinPlanningNamesEmptyPinsAndExistingCast() {
        let first = PlacementPin(x: 0, z: 0)
        let second = PlacementPin(x: 1, y: 0.4, z: 0)
        let text = DirectorClient.pinPlanningPrompt(
            intent: "Berlin sound booth",
            chunk: [second],
            allPins: [first, second],
            alreadyOnTable: ["Guitar", "Stool"]
        )
        XCTAssertTrue(text.contains("Berlin sound booth"))
        XCTAssertTrue(text.contains("Already placed"))
        XCTAssertTrue(text.contains("Guitar"))
        XCTAssertTrue(text.contains("Stool"))
        XCTAssertTrue(text.contains("Pin 2"))
        XCTAssertTrue(text.contains("airborne"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("diorama"))
    }

    func testYorkshireForgeCastExtractsHeroAndDropsLighting() {
        let scene = "A rain-slicked Yorkshire forge at twilight: a blackened iron knight as the hero, a splintered oak anvil, a tarnished silver crow's nest, a coiled hemp winch, a cracked ceramic cauldron, a rusted leather satchel, dim lantern glow and soot-stained amber."
        let (setting, objects) = DirectorStaging.sceneCast(from: scene)
        XCTAssertTrue(setting.localizedCaseInsensitiveContains("Yorkshire forge"))
        XCTAssertEqual(objects.count, 6)
        XCTAssertEqual(objects.filter(\.isHero).count, 1)
        XCTAssertTrue(objects.contains { $0.isHero && $0.title.localizedCaseInsensitiveContains("Knight") })
        XCTAssertTrue(objects.contains { $0.title.localizedCaseInsensitiveContains("Anvil") })
        XCTAssertTrue(objects.contains { $0.title.localizedCaseInsensitiveContains("Nest") })
        XCTAssertTrue(objects.contains { $0.title.localizedCaseInsensitiveContains("Winch") })
        XCTAssertTrue(objects.contains { $0.title.localizedCaseInsensitiveContains("Cauldron") })
        XCTAssertTrue(objects.contains { $0.title.localizedCaseInsensitiveContains("Satchel") })
        XCTAssertFalse(objects.contains { $0.shapEPrompt.localizedCaseInsensitiveContains("amber") })
        XCTAssertFalse(objects.contains { $0.shapEPrompt.localizedCaseInsensitiveContains("glow") })
    }

    func testNamedPinJobsPutHeroOnCenterAndExtrasAreComplementary() {
        let scene = "A rain-slicked Yorkshire forge at twilight: a blackened iron knight as the hero, a splintered oak anvil, a tarnished silver crow's nest, a coiled hemp winch, a cracked ceramic cauldron, a rusted leather satchel, dim lantern glow and soot-stained amber."
        let pins = [
            PlacementPin(x: -2, z: 0),
            PlacementPin(x: 0, z: 0),
            PlacementPin(x: 2, z: 0),
            PlacementPin(x: 0, z: 2),
            PlacementPin(x: 0, z: -2),
            PlacementPin(x: 3, z: 3),
            PlacementPin(x: -3, z: 3),
            PlacementPin(x: 4, z: 0)
        ]
        let split = DirectorStaging.namedPinJobs(
            empty: pins,
            allPins: pins,
            scene: scene,
            already: [],
            seed: 1
        )
        XCTAssertEqual(split.jobs.count, 6)
        XCTAssertEqual(split.extraPins.count, 2)
        let hero = split.jobs.first { $0.title.localizedCaseInsensitiveContains("Knight") }
        XCTAssertNotNil(hero)
        XCTAssertEqual(hero?.pinID, pins[1].id)
        XCTAssertEqual(hero?.scale, .tabletop)
        XCTAssertTrue(hero?.shapEPrompt.localizedCaseInsensitiveContains("knight") == true)
        XCTAssertFalse(split.jobs.contains { $0.shapEPrompt.localizedCaseInsensitiveContains("tree") })
        XCTAssertTrue(DirectorStaging.complementaryPinJobs(
            pins: split.extraPins,
            setting: split.setting,
            seed: 10
        ).isEmpty)
        let note = DirectorStaging.summarizePinPlan(
            named: 6,
            extras: 0,
            leftoverPins: 2,
            extrasBudget: 0,
            extrasFailed: false
        )
        XCTAssertTrue(note.contains("6 objects generated"))
        XCTAssertTrue(note.contains("extra props off"))
    }

    func testSixNamedObjectsAcrossTwentyOnePinsLeaveLeftoversEmpty() {
        let scene = "A rain-slicked Yorkshire forge at twilight: a blackened iron knight as the hero, a splintered oak anvil, a tarnished silver crow's nest, a coiled hemp winch, a cracked ceramic cauldron, a rusted leather satchel, dim lantern glow and soot-stained amber."
        let pins = (0..<21).map { i in
            PlacementPin(x: Float(i % 7), z: Float(i / 7))
        }
        let split = DirectorStaging.namedPinJobs(
            empty: pins,
            allPins: pins,
            scene: scene,
            already: [],
            seed: 1
        )
        XCTAssertEqual(split.jobs.count, 6)
        XCTAssertEqual(split.extraPins.count, 15)
        XCTAssertTrue(split.jobs.allSatisfy { $0.route == .named })
        XCTAssertTrue(split.jobs.allSatisfy { $0.inventoryID != nil })
        XCTAssertFalse(split.jobs.contains { $0.shapEPrompt.localizedCaseInsensitiveContains("closed volume") })
        XCTAssertFalse(split.jobs.contains { $0.shapEPrompt.localizedCaseInsensitiveContains("complementary") })
        let note = DirectorStaging.summarizePinPlan(
            named: 6,
            extras: 0,
            leftoverPins: 15,
            extrasBudget: 0,
            extrasFailed: false
        )
        XCTAssertTrue(note.contains("15 pins left empty"))
    }

    func testExtraPropsSliderMaxIsLeftoverAfterNamedObjects() {
        let app = AppModel()
        app.prompt = "A rain-slicked Yorkshire forge at twilight: a blackened iron knight as the hero, a splintered oak anvil, a tarnished silver crow's nest, a coiled hemp winch, a cracked ceramic cauldron, a rusted leather satchel, dim lantern glow and soot-stained amber."
        for i in 0..<21 {
            app.addPlacementPin(x: Float(i % 7), z: Float(i / 7))
        }
        XCTAssertEqual(app.emptyPlacementPins.count, 21)
        XCTAssertEqual(app.extraPropsCapacity, 15)
        app.pinExtrasBudget = 15
        XCTAssertEqual(app.clampedPinExtrasBudget, 15)
        app.pinExtrasBudget = 40
        XCTAssertEqual(app.clampedPinExtrasBudget, 15)
        app.pinExtrasBudget = 0
        XCTAssertEqual(app.clampedPinExtrasBudget, 0)
    }

    func testKnightUnderMoonStaysOneCastObject() {
        let (_, objects) = DirectorStaging.sceneCast(from: "a darkened Knight under a pale moon")
        XCTAssertEqual(objects.count, 1)
        XCTAssertTrue(objects[0].shapEPrompt.localizedCaseInsensitiveContains("knight"))
        XCTAssertTrue(objects[0].shapEPrompt.localizedCaseInsensitiveContains("moon"))
    }

    func testSpatialPairPutsMoonInTheAir() {
        let pair = DirectorStaging.spatialPair(from: "a darkened Knight under a pale moon")
        XCTAssertNotNil(pair)
        XCTAssertTrue(pair?.floor.title.localizedCaseInsensitiveContains("Knight") == true)
        XCTAssertTrue(pair?.airborne.title.localizedCaseInsensitiveContains("Moon") == true)
        XCTAssertTrue(pair?.floor.shapEPrompt.localizedCaseInsensitiveContains("darkened") == true)
        XCTAssertFalse(pair?.floor.shapEPrompt.localizedCaseInsensitiveContains("moon") == true)
        XCTAssertEqual(pair?.airborne.shapEPrompt.lowercased(), "a pale moon")
        XCTAssertTrue(pair?.floor.isHero == true)
        XCTAssertTrue(pair?.airborne.prefersAirborne == true)

        let over = DirectorStaging.spatialPair(from: "a pale moon over a darkened knight")
        XCTAssertTrue(over?.floor.title.localizedCaseInsensitiveContains("Knight") == true)
        XCTAssertTrue(over?.airborne.title.localizedCaseInsensitiveContains("Moon") == true)
    }

    func testFallbackPutsMoonOnLiftedPin() {
        let floor = PlacementPin(x: 0, z: 0)
        let lifted = PlacementPin(x: 0.4, y: 0.8, z: 0)
        let jobs = DirectorStaging.fallbackPinJobs(
            pins: [floor, lifted],
            scene: "a darkened Knight under a pale moon",
            seed: 3,
            already: [],
            allPins: [floor, lifted]
        )
        XCTAssertEqual(jobs.count, 2)
        let knight = jobs.first { $0.title.localizedCaseInsensitiveContains("Knight") }
        let moon = jobs.first { $0.title.localizedCaseInsensitiveContains("Moon") }
        XCTAssertEqual(knight?.pinID, floor.id)
        XCTAssertEqual(moon?.pinID, lifted.id)
        XCTAssertTrue(knight?.shapEPrompt.localizedCaseInsensitiveContains("knight") == true)
        XCTAssertFalse(knight?.shapEPrompt.localizedCaseInsensitiveContains("moon") == true)
        XCTAssertTrue(moon?.shapEPrompt.localizedCaseInsensitiveContains("moon") == true)
        XCTAssertFalse(moon?.shapEPrompt.localizedCaseInsensitiveContains("knight") == true)
    }

    func testNamedCommaMoonGoesToLiftedPin() {
        let floor = PlacementPin(x: 0, z: 0)
        let lifted = PlacementPin(x: 0.5, y: 1.0, z: 0)
        let split = DirectorStaging.namedPinJobs(
            empty: [floor, lifted],
            allPins: [floor, lifted],
            scene: "a blackened iron knight as the hero, a pale moon",
            already: [],
            seed: 1
        )
        XCTAssertEqual(split.jobs.count, 2)
        let knight = split.jobs.first { $0.title.localizedCaseInsensitiveContains("Knight") }
        let moon = split.jobs.first { $0.title.localizedCaseInsensitiveContains("Moon") }
        XCTAssertEqual(knight?.pinID, floor.id)
        XCTAssertEqual(moon?.pinID, lifted.id)
    }

    func testResolvedCastUsesTaggedObjectsWhenThereAreTwo() {
        let tagged = DirectorStaging.TaggedSceneCast(
            setting: "twilight field",
            objects: [
                DirectorStaging.makeObject("a darkened knight", hero: true, prefersAirborne: false),
                DirectorStaging.makeObject("a pale moon", hero: false, prefersAirborne: true)
            ]
        )
        let cast = DirectorStaging.resolvedCast(
            scene: "a darkened Knight under a pale moon",
            tagged: tagged
        )
        XCTAssertEqual(cast.objects.count, 2)
        XCTAssertTrue(cast.objects.contains { $0.title.localizedCaseInsensitiveContains("Knight") && !$0.prefersAirborne })
        XCTAssertTrue(cast.objects.contains { $0.title.localizedCaseInsensitiveContains("Moon") && $0.prefersAirborne })
    }

    func testResolvedCastFallsBackToSpatialWhenTaggerReturnsOneObject() {
        let tagged = DirectorStaging.TaggedSceneCast(
            setting: "",
            objects: [
                DirectorStaging.makeObject("a darkened Knight under a pale moon", hero: true, prefersAirborne: true)
            ]
        )
        let cast = DirectorStaging.resolvedCast(
            scene: "a darkened Knight under a pale moon",
            tagged: tagged
        )
        XCTAssertEqual(cast.objects.count, 2)
        XCTAssertTrue(cast.objects.contains { $0.title.localizedCaseInsensitiveContains("Knight") && !$0.prefersAirborne })
        XCTAssertTrue(cast.objects.contains { $0.title.localizedCaseInsensitiveContains("Moon") && $0.prefersAirborne })
    }

    func testResolvedCastWithoutTaggerSplitsKnightUnderMoon() {
        let cast = DirectorStaging.resolvedCast(
            scene: "a darkened Knight under a pale moon",
            tagged: nil
        )
        XCTAssertEqual(cast.objects.count, 2)
        XCTAssertTrue(cast.objects.contains { $0.prefersAirborne && $0.title.localizedCaseInsensitiveContains("Moon") })
    }

    func testTaggedCastMoonGoesToLiftedPin() {
        let floor = PlacementPin(x: 0, z: 0)
        let lifted = PlacementPin(x: 0.4, y: 0.8, z: 0)
        let cast = DirectorStaging.TaggedSceneCast(
            setting: "night field",
            objects: [
                DirectorStaging.makeObject("a darkened knight", hero: true, prefersAirborne: false),
                DirectorStaging.makeObject("a pale moon", hero: false, prefersAirborne: true)
            ]
        )
        let split = DirectorStaging.namedPinJobs(
            empty: [floor, lifted],
            allPins: [floor, lifted],
            cast: cast,
            already: [],
            seed: 2
        )
        XCTAssertEqual(split.jobs.count, 2)
        XCTAssertTrue(split.extraPins.isEmpty)
        let knight = split.jobs.first { $0.title.localizedCaseInsensitiveContains("Knight") }
        let moon = split.jobs.first { $0.title.localizedCaseInsensitiveContains("Moon") }
        XCTAssertEqual(knight?.pinID, floor.id)
        XCTAssertEqual(moon?.pinID, lifted.id)
    }

    func testIngestKeepsRedAndBlueCarsAndDropsRepeatPhrase() {
        var seen = Set<String>()
        let red = DirectorStaging.ingestTaggedObject(
            name: "a red sports car",
            height: .floor,
            isHero: true,
            seenKeys: &seen
        )
        let blue = DirectorStaging.ingestTaggedObject(
            name: "a blue sports car",
            height: .floor,
            isHero: false,
            seenKeys: &seen
        )
        let again = DirectorStaging.ingestTaggedObject(
            name: "red sports car",
            height: .floor,
            isHero: false,
            seenKeys: &seen
        )
        XCTAssertNotNil(red)
        XCTAssertNotNil(blue)
        XCTAssertNil(again)
        XCTAssertNotEqual(red?.id, blue?.id)
        XCTAssertTrue(red?.title.localizedCaseInsensitiveContains("Car") == true)
        XCTAssertTrue(blue?.title.localizedCaseInsensitiveContains("Car") == true)
        XCTAssertNotEqual(
            DirectorStaging.normalizedIdentityKey(red!.sourcePhrase),
            DirectorStaging.normalizedIdentityKey(blue!.sourcePhrase)
        )
    }

    func testIngestTrustsExplicitFloorLantern() {
        var seen = Set<String>()
        let lantern = DirectorStaging.ingestTaggedObject(
            name: "a cracked ceramic lantern",
            height: .floor,
            isHero: false,
            seenKeys: &seen
        )
        XCTAssertNotNil(lantern)
        XCTAssertFalse(lantern!.prefersAirborne)
        XCTAssertTrue(DirectorStaging.looksAirborne("a cracked ceramic lantern"))
        let floor = PlacementPin(x: 0, z: 0)
        let lifted = PlacementPin(x: 0.4, y: 0.8, z: 0)
        let split = DirectorStaging.namedPinJobs(
            empty: [floor, lifted],
            allPins: [floor, lifted],
            cast: DirectorStaging.TaggedSceneCast(
                setting: "forge",
                objects: [lantern!]
            ),
            already: [],
            seed: 1
        )
        XCTAssertEqual(split.jobs.first?.pinID, floor.id)
    }

    func testAmberGlassBottleIsNotAtmosphere() {
        XCTAssertFalse(DirectorStaging.isAtmosphereClause("an amber glass bottle"))
        XCTAssertTrue(DirectorStaging.isAtmosphereClause("dim lantern glow and soot-stained amber"))
        var seen = Set<String>()
        let bottle = DirectorStaging.ingestTaggedObject(
            name: "an amber glass bottle",
            height: .floor,
            isHero: false,
            seenKeys: &seen
        )
        XCTAssertNotNil(bottle)
        XCTAssertTrue(bottle!.shapEPrompt.localizedCaseInsensitiveContains("bottle"))
    }

    func testCarvedDoesNotMatchCarScale() {
        XCTAssertEqual(
            DirectorStaging.inferredScale(title: "Idol", prompt: "a carved oak totem", current: .figurine),
            .figurine
        )
        XCTAssertEqual(
            DirectorStaging.inferredScale(title: "Racer", prompt: "a red sports car", current: .figurine),
            .tabletop
        )
    }

    func testObjectPromptIssueRejectsStructuralFailuresOnly() {
        XCTAssertEqual(DirectorStaging.objectPromptIssue(""), .empty)
        XCTAssertEqual(DirectorStaging.objectPromptIssue("a small closed volume"), .genericOnly)
        XCTAssertEqual(
            DirectorStaging.objectPromptIssue(
                "a complementary closed prop for a Yorkshire forge, chunky silhouette, one mass, not a tree"
            ),
            .genericOnly
        )
        XCTAssertEqual(
            DirectorStaging.objectPromptIssue("shapEPrompt: a knight", scene: nil),
            .fieldLabels
        )
        let scene = "a darkened Knight under a pale moon"
        XCTAssertEqual(DirectorStaging.objectPromptIssue(scene, scene: scene), .wholeScene)
        XCTAssertNil(DirectorStaging.objectPromptIssue("a rusted iron drill head"))
        XCTAssertNil(DirectorStaging.objectPromptIssue("a rusty steel drilling bit"))
        XCTAssertNil(DirectorStaging.objectPromptIssue("a stage prop treasure chest"))
        XCTAssertNil(DirectorStaging.objectPromptIssue("a brass propeller"))
    }

    func testPinIndexAssignmentsSkipInvalidAndNeverPasteTheScene() {
        let pins = [
            PlacementPin(x: 0, z: 0),
            PlacementPin(x: 1, z: 0),
            PlacementPin(x: 2, z: 0)
        ]
        let scene = "A rain-slicked Yorkshire forge at twilight: a blackened iron knight as the hero."
        let items = [
            DirectorClient.PlannedPinItem(
                pinIndex: 2,
                title: "Tongs",
                shapEPrompt: "iron forge tongs, riveted hinge, blackened jaws",
                scale: .figurine,
                material: .metal
            ),
            DirectorClient.PlannedPinItem(
                pinIndex: 2,
                title: "Duplicate",
                shapEPrompt: "another pair of tongs",
                scale: .figurine,
                material: .metal
            ),
            DirectorClient.PlannedPinItem(
                pinIndex: 9,
                title: "Ghost",
                shapEPrompt: "a bucket",
                scale: .figurine,
                material: .metal
            ),
            DirectorClient.PlannedPinItem(
                pinIndex: 3,
                title: "Scene",
                shapEPrompt: scene,
                scale: .figurine,
                material: .metal
            ),
            DirectorClient.PlannedPinItem(
                pinIndex: 1,
                title: "Volume",
                shapEPrompt: "a small closed volume",
                scale: .mug,
                material: .vertexColor
            )
        ]
        let resolved = DirectorClient.assignmentsMatchingPinIndex(
            items: items,
            chunk: pins,
            allPins: pins,
            scene: scene,
            baseSeed: 4
        )
        XCTAssertEqual(resolved.jobs.count, 1)
        XCTAssertEqual(resolved.jobs[0].pinID, pins[1].id)
        XCTAssertEqual(resolved.jobs[0].title, "Tongs")
        XCTAssertEqual(resolved.jobs[0].route, .extra)
        XCTAssertGreaterThanOrEqual(resolved.skipped, 4)
        XCTAssertFalse(resolved.jobs[0].shapEPrompt.localizedCaseInsensitiveContains("knight"))
    }

    func testSceneTagPromptNamesHeightSplit() {
        let text = DirectorClient.sceneTagPrompt(scene: "a darkened Knight under a pale moon")
        XCTAssertTrue(text.contains("a darkened Knight under a pale moon"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("knight floor"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("moon airborne"))
    }

    func testScenePinPlanningAsksForHeightSplit() {
        let floor = PlacementPin(x: 0, z: 0)
        let lifted = PlacementPin(x: 0, y: 0.6, z: 0)
        let text = DirectorClient.pinPlanningPrompt(
            intent: "a darkened Knight under a pale moon",
            chunk: [floor, lifted],
            allPins: [floor, lifted],
            alreadyOnTable: [],
            mode: .scene
        )
        XCTAssertTrue(text.contains("a darkened Knight under a pale moon"))
        XCTAssertTrue(text.contains("airborne"))
        XCTAssertTrue(text.contains("floor"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("moon"))
        XCTAssertFalse(text.contains("leftover pins need complementary"))
    }
}
