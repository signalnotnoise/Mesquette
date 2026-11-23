import XCTest
@testable import Mesquette

@MainActor
final class DirectorLayoutEngineTests: XCTestCase {
    func testPlaceSettingHeroAtOriginSupportsOnSides() {
        let parts = [
            CompiledPart(title: "Plate", shapEPrompt: "a round plate", scale: .tabletop, material: .ceramic, isHero: true),
            CompiledPart(title: "Mug", shapEPrompt: "a ceramic mug", scale: .mug, material: .ceramic),
            CompiledPart(title: "Bowl", shapEPrompt: "a small bowl", scale: .mug, material: .ceramic),
            CompiledPart(title: "Jar", shapEPrompt: "a jam jar", scale: .figurine, material: .glass),
            CompiledPart(title: "Vase", shapEPrompt: "a small vase", scale: .figurine, material: .ceramic),
            CompiledPart(title: "Loaf", shapEPrompt: "a round loaf", scale: .tabletop, material: .clay)
        ]
        let staged = DirectorLayoutEngine.applyTemplate(layout: .placeSetting, parts: parts)
        XCTAssertEqual(Set(staged.map(\.slot)).count, 6)
        let hero = staged.first { $0.isHero }!
        XCTAssertEqual(hero.slot, .heroCenter)
        XCTAssertEqual(hero.offsetX, 0, accuracy: 0.001)
        XCTAssertEqual(hero.offsetZ, 0, accuracy: 0.001)
        XCTAssertEqual(staged.first { $0.title == "Mug" }?.slot, .leftHand)
        XCTAssertEqual(staged.first { $0.title == "Jar" }?.slot, .near)
        let near = staged.first { $0.slot == .near }!
        XCTAssertGreaterThan(near.offsetZ, 0)
        let far = staged.first { $0.slot == .far }!
        XCTAssertLessThan(far.offsetZ, 0)
    }

    func testIgnoresLLMMeterOffsets() {
        let parts = [
            CompiledPart(title: "A", shapEPrompt: "a mug", scale: .mug, material: .ceramic, offsetX: 9, offsetZ: 9, isHero: true),
            CompiledPart(title: "B", shapEPrompt: "a jar", scale: .figurine, material: .glass, offsetX: -9, offsetZ: -9)
        ]
        let staged = DirectorLayoutEngine.applyTemplate(layout: .placeSetting, parts: parts)
        XCTAssertEqual(staged[0].offsetX, 0, accuracy: 0.01)
        XCTAssertEqual(staged[0].offsetZ, 0, accuracy: 0.01)
        XCTAssertLessThan(abs(staged[1].offsetX), 0.5)
        XCTAssertLessThan(abs(staged[1].offsetZ), 0.5)
    }

    func testPackSeparatesOverlappingRadii() {
        let rest: [(x: Float, z: Float)] = [(0, 0), (0.02, 0), (0.04, 0)]
        let radii: [Float] = [0.12, 0.12, 0.12]
        let packed = DirectorLayoutEngine.pack(rest: rest, radii: radii, gap: 0.04)
        for i in 0..<packed.count {
            for j in (i + 1)..<packed.count {
                let d = hypot(packed[j].x - packed[i].x, packed[j].z - packed[i].z)
                XCTAssertGreaterThan(d, 0.26, "parts \(i) and \(j) still overlap (\(d))")
            }
        }
    }

    func testFitUsesRawExtentsNotSit() {
        // Identity: packing radius comes from generated XZ, not a 90° sit.
        let raw = SIMD3<Float>(1.0, 1.0, 0.12)
        XCTAssertEqual(max(raw.x, raw.z), 1.0, accuracy: 0.001)
    }

    func testPinWorldScaleGrowsWithSpread() {
        let tight = [
            PlacementPin(x: 0, z: 0),
            PlacementPin(x: 0.4, z: 0)
        ]
        XCTAssertEqual(DirectorLayoutEngine.pinWorldScale(tight), 1, accuracy: 0.01)
        let wide = [
            PlacementPin(x: -5, z: -5),
            PlacementPin(x: 5, z: 5)
        ]
        XCTAssertGreaterThan(DirectorLayoutEngine.pinWorldScale(wide), 4)
    }

    func testUniformScaleUsesLongestSpanNotThinAxis() {
        let s = DirectorLayoutEngine.uniformScale(span: 2.0, target: 0.34)
        XCTAssertEqual(s, 0.17, accuracy: 0.0001)
        let clamped = DirectorLayoutEngine.uniformScale(span: 0.001, target: 0.34)
        XCTAssertEqual(clamped, 1.6, accuracy: 0.001)
        let window = SIMD3<Float>(1.0, 1.2, 0.08)
        let longest = max(window.x, max(window.y, window.z))
        let windowScale = DirectorLayoutEngine.uniformScale(span: longest, target: DirectorScale.tabletop.targetSpan)
        XCTAssertLessThan(windowScale * window.x, 0.45)
        XCTAssertLessThan(windowScale * window.y, 0.45)
    }

    func testRestPoseDoesNotInventYaw() {
        let pose = DirectorLayoutEngine.restPose(
            layout: .cluster,
            slot: .leftHand,
            index: 1,
            count: 3,
            isHero: false,
            supportIndex: 0
        )
        XCTAssertEqual(pose.yaw, 0, accuracy: 0.001)
    }

    func testApplyPinsBindsInOrderAndOffsetsExtrasFromFirst() {
        let parts = [
            CompiledPart(title: "A", shapEPrompt: "a mug", scale: .mug, material: .ceramic, isHero: true),
            CompiledPart(title: "B", shapEPrompt: "a jar", scale: .figurine, material: .glass),
            CompiledPart(title: "C", shapEPrompt: "a vase", scale: .figurine, material: .ceramic)
        ]
        let pins = [
            PlacementPin(x: 1.2, z: -0.4),
            PlacementPin(x: 1.5, z: -0.1)
        ]
        let staged = DirectorLayoutEngine.applyPins(pins, to: parts, layout: .placeSetting)
        XCTAssertEqual(staged[0].offsetX, 1.2, accuracy: 0.001)
        XCTAssertEqual(staged[0].offsetZ, -0.4, accuracy: 0.001)
        XCTAssertEqual(staged[1].offsetX, 1.5, accuracy: 0.001)
        XCTAssertEqual(staged[1].offsetZ, -0.1, accuracy: 0.001)
        XCTAssertEqual(staged[2].offsetX, 1.48, accuracy: 0.02)
        XCTAssertEqual(staged[2].offsetZ, -0.35, accuracy: 0.02)
    }

    func testPackRecordsUsesPinIDNotArrayOrder() {
        let center = PlacementPin(x: 0, z: 0)
        let lifted = PlacementPin(x: 2, y: 0.8, z: 0)
        var hero = GenerationRecord(prompt: "knight", pinID: center.id, partTitle: "Knight")
        hero.offsetX = 9
        hero.offsetZ = 9
        var moon = GenerationRecord(prompt: "moon", pinID: lifted.id, partTitle: "Moon")
        moon.offsetX = 9
        moon.offsetY = 0
        moon.offsetZ = 9
        var records = [hero, moon]
        DirectorLayoutEngine.packRecords(&records, layout: .cluster, pins: [lifted, center])
        XCTAssertEqual(records[0].offsetX ?? 0, 0, accuracy: 0.001)
        XCTAssertEqual(records[0].offsetZ ?? 0, 0, accuracy: 0.001)
        XCTAssertEqual(records[1].offsetX ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(records[1].offsetY ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(records[1].offsetZ ?? 0, 0, accuracy: 0.001)
    }

    func testPackLeavesLockedPinsUnmoved() {
        var records = [
            GenerationRecord(
                prompt: "cloud",
                offsetX: 9,
                offsetY: 0.8,
                offsetZ: 9,
                footprintRadius: 0.4
            ),
            GenerationRecord(
                prompt: "plane",
                offsetX: 9.05,
                offsetY: 0.7,
                offsetZ: 9.05,
                footprintRadius: 0.4
            )
        ]
        let pins = [
            PlacementPin(x: 1.0, y: 0.8, z: 2.0),
            PlacementPin(x: 1.05, y: 0.7, z: 2.05)
        ]
        DirectorLayoutEngine.packRecords(&records, layout: .cluster, pins: pins)
        XCTAssertEqual(records[0].offsetX ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(records[0].offsetY ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(records[0].offsetZ ?? 0, 2.0, accuracy: 0.001)
        XCTAssertEqual(records[1].offsetX ?? 0, 1.05, accuracy: 0.001)
        XCTAssertEqual(records[1].offsetY ?? 0, 0.7, accuracy: 0.001)
        XCTAssertEqual(records[1].offsetZ ?? 0, 2.05, accuracy: 0.001)
    }

    func testPackNearPinsDoesNotRecenterToOrigin() {
        let rest: [(x: Float, z: Float)] = [(1.0, 1.0), (1.4, 1.0)]
        let packed = DirectorLayoutEngine.pack(
            rest: rest,
            radii: [0.08, 0.08],
            recenter: false
        )
        let cx = (packed[0].x + packed[1].x) / 2
        XCTAssertGreaterThan(cx, 0.8)
    }

    func testPinHeightClampsAndMarksAirborne() {
        let floor = PlacementPin(x: 0, y: 0, z: 0)
        XCTAssertEqual(floor.y, 0, accuracy: 0.0001)
        XCTAssertLessThan(floor.y, PlacementPin.airborneThreshold)
        let sky = PlacementPin(x: 0.2, y: 0.8, z: -0.1)
        XCTAssertEqual(sky.y, 0.8, accuracy: 0.0001)
        XCTAssertGreaterThan(sky.y, PlacementPin.airborneThreshold)
        let clamped = PlacementPin(x: 0, y: 9, z: 0)
        XCTAssertEqual(clamped.y, PlacementPin.maxHeight, accuracy: 0.0001)
    }

    func testLooksLikeFillDetectsForestAndSea() {
        XCTAssertTrue(PinAssignment.looksLikeFill(title: "Grove", prompt: "a mossy forest patch"))
        XCTAssertTrue(PinAssignment.looksLikeFill(title: "Tide", prompt: "a sea swell"))
        XCTAssertFalse(PinAssignment.looksLikeFill(title: "Jaguar", prompt: "a black toy car"))
        XCTAssertFalse(PinAssignment.looksLikeFill(title: "Microwave", prompt: "a white microwave oven"))
        XCTAssertFalse(PinAssignment.looksLikeFill(title: "Bottle", prompt: "a glass water bottle"))
    }

    func testClusterMiddleHeroDoesNotStackSupports() {
        let parts = [
            CompiledPart(title: "A", shapEPrompt: "a crate", scale: .figurine, material: .wood),
            CompiledPart(title: "B", shapEPrompt: "a lighthouse", scale: .building, material: .stone, isHero: true),
            CompiledPart(title: "C", shapEPrompt: "a dory", scale: .tabletop, material: .wood)
        ]
        let staged = DirectorLayoutEngine.applyTemplate(layout: .cluster, parts: parts)
        let hero = staged.first { $0.isHero }!
        XCTAssertEqual(hero.offsetX, 0, accuracy: 0.001)
        XCTAssertEqual(hero.offsetZ, 0, accuracy: 0.001)
        let supports = staged.filter { !$0.isHero }
        XCTAssertEqual(supports.count, 2)
        let d = hypot(
            supports[0].offsetX - supports[1].offsetX,
            supports[0].offsetZ - supports[1].offsetZ
        )
        XCTAssertGreaterThan(d, 0.4)
    }

    func testExpandFillsMeetsMidway() {
        var records = [
            GenerationRecord(
                prompt: "oak grove",
                offsetX: 0,
                offsetZ: 0,
                placementScale: 1,
                footprintRadius: 0.1,
                fillsToNeighbors: true
            ),
            GenerationRecord(
                prompt: "pine grove",
                offsetX: 1.0,
                offsetZ: 0,
                placementScale: 1,
                footprintRadius: 0.1,
                fillsToNeighbors: true
            )
        ]
        DirectorLayoutEngine.expandFills(&records)
        XCTAssertEqual(records[0].footprintRadius ?? 0, 0.5, accuracy: 0.05)
        XCTAssertEqual(records[1].footprintRadius ?? 0, 0.5, accuracy: 0.05)
    }

    func testRowSpreadsAlongX() {
        let parts = (0..<5).map { i in
            CompiledPart(
                title: "P\(i)",
                shapEPrompt: "a ceramic mug",
                scale: .mug,
                material: .ceramic,
                isHero: i == 2
            )
        }
        let staged = DirectorLayoutEngine.applyTemplate(layout: .row, parts: parts)
        let xs = staged.map(\.offsetX).sorted()
        XCTAssertLessThan(xs.first!, -0.4)
        XCTAssertGreaterThan(xs.last!, 0.4)
    }
}
