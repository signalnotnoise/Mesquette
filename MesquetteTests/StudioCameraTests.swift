import XCTest
import simd
@testable import Mesquette

@MainActor
final class StudioCameraTests: XCTestCase {

    func testHomeLooksSlightlyDownNotAtZenith() {
        let home = StudioCameraRig.home
        XCTAssertEqual(home.view, .orbit)
        XCTAssertGreaterThan(home.pitch, 0.1)
        XCTAssertLessThan(home.pitch, 0.5)
        XCTAssertGreaterThan(home.position.y, home.pivot.y)
    }

    func testOrbitPitchReachesNearlyTopDown() {
        var rig = StudioCameraRig.home
        rig.orbit(dx: 0, dy: 400)
        XCTAssertEqual(rig.pitch, StudioCameraRig.maxOrbitPitch, accuracy: 0.001)
        XCTAssertGreaterThan(rig.position.y, rig.pivot.y + 0.8)
        let look = rig.lookDirection
        XCTAssertLessThan(look.y, -0.95)
    }

    func testOrbitDoesNotFlipPastZenith() {
        var rig = StudioCameraRig.home
        for _ in 0..<40 {
            rig.orbit(dx: 12, dy: 80)
        }
        XCTAssertLessThanOrEqual(rig.pitch, StudioCameraRig.maxOrbitPitch)
        XCTAssertGreaterThanOrEqual(rig.pitch, StudioCameraRig.minOrbitPitch)
        XCTAssertGreaterThan(rig.position.y, 0)
    }

    func testWalkCanLookDownAtFeet() {
        var rig = StudioCameraRig.home
        rig.adoptView(.walk)
        rig.look(dx: 0, dy: 500)
        XCTAssertEqual(rig.pitch, StudioCameraRig.maxWalkPitch, accuracy: 0.001)
        XCTAssertLessThan(rig.lookDirection.y, -0.98)
    }

    func testWalkKeepsEyeWhenLeavingOrbit() {
        var rig = StudioCameraRig.home
        let pos = rig.position
        rig.adoptView(.walk)
        XCTAssertEqual(rig.view, .walk)
        XCTAssertEqual(rig.eye.x, pos.x, accuracy: 0.001)
        XCTAssertEqual(rig.eye.y, pos.y, accuracy: 0.001)
        XCTAssertEqual(rig.eye.z, pos.z, accuracy: 0.001)
    }

    func testTopSnapsPitchWithoutMovingPivot() {
        var rig = StudioCameraRig.home
        let pivot = rig.pivot
        rig.adoptView(.top)
        XCTAssertEqual(rig.view, .top)
        XCTAssertEqual(rig.pitch, StudioCameraRig.topPitch, accuracy: 0.001)
        XCTAssertEqual(rig.pivot.x, pivot.x, accuracy: 0.001)
        XCTAssertEqual(rig.pivot.z, pivot.z, accuracy: 0.001)
        XCTAssertGreaterThan(rig.position.y, rig.pivot.y + 1)
    }

    func testFramePutsPivotOnCenter() {
        var rig = StudioCameraRig.home
        let center = SIMD3<Float>(2, 0.4, -1)
        rig.frame(center: center, radius: 1.2)
        XCTAssertEqual(rig.pivot.x, center.x, accuracy: 0.001)
        XCTAssertEqual(rig.pivot.y, center.y, accuracy: 0.001)
        XCTAssertEqual(rig.pivot.z, center.z, accuracy: 0.001)
        XCTAssertGreaterThan(rig.distance, 1.3)
    }

    func testWalkFrameStandsAtEyeHeight() {
        var rig = StudioCameraRig.home
        rig.view = .walk
        rig.frame(center: SIMD3(0, 0.2, 0), radius: 0.8)
        XCTAssertGreaterThanOrEqual(rig.eye.y, 1.5)
        XCTAssertGreaterThan(rig.eye.z, 0.2)
        let toCenter = SIMD3<Float>(0, 0.2, 0) - rig.eye
        let aligned = simd_dot(simd_normalize(toCenter), rig.lookDirection)
        XCTAssertGreaterThan(aligned, 0.98)
    }
}
