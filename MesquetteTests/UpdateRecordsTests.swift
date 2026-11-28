import XCTest
import ShapERuntime
@testable import Mesquette

@MainActor
final class UpdateRecordsTests: XCTestCase {

    private func tinyMesh(seed: Float) throws -> MeshResult {
        let verts: [Float] = [seed, 0, 0, seed + 1, 0, 0, seed, 1, 0]
        let faces: [Int32] = [0, 1, 2]
        return try MeshResult(
            vertices: RuntimeTensor(name: "v", shape: [3, 3], dataType: .float32,
                                    data: verts.withUnsafeBytes { Data($0) }),
            faces: RuntimeTensor(name: "f", shape: [1, 3], dataType: .int32,
                                 data: faces.withUnsafeBytes { Data($0) }),
            vertexChannels: nil,
            bbox: BoundingBox(minCorner: [seed, 0, 0], maxCorner: [seed + 1, 1, 0]),
            timings: [:],
            artifactInfo: ArtifactVersionInfo(artifactVersion: 0, manifestPath: "test")
        )
    }

    /// Regression for PR #3 finding 3: upstream conversion may drop a row
    /// (compactMap). A short partial list must never be zipped positionally:
    /// row 2's mesh must not appear on record 1 in a two-row batch.
    func testShortPartialListIsNotAppliedPositionally() throws {
        let app = AppModel()
        let vm = ContentViewModel()
        let first = GenerationRecord(prompt: "a")
        let second = GenerationRecord(prompt: "b")
        app.generationDict[first.id] = first
        app.generationDict[second.id] = second
        app.generationOrder = [first.id, second.id]

        // One surviving partial (conceptually row 2's) for two records.
        vm.updateRecords(
            in: app,
            ids: [first.id, second.id],
            status: .generating,
            meshResults: [try tinyMesh(seed: 9)],
            persistFinal: false
        )
        XCTAssertNil(app.generationDict[first.id]?.latestMesh)
        XCTAssertNil(app.generationDict[second.id]?.latestMesh)

        // A complete, aligned update still lands on both records.
        vm.updateRecords(
            in: app,
            ids: [first.id, second.id],
            status: .completed,
            meshResults: [try tinyMesh(seed: 1), try tinyMesh(seed: 5)],
            persistFinal: true
        )
        XCTAssertNotNil(app.generationDict[first.id]?.latestMesh)
        XCTAssertNotNil(app.generationDict[second.id]?.latestMesh)
    }
}
