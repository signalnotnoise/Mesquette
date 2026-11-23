import XCTest
@testable import Mesquette

final class MeshExporterTests: XCTestCase {

    func testValidatedFaceIndicesAcceptsInRangeTriangles() throws {
        let indices = try MeshExporter.validatedFaceIndices(
            [Int32(0), 1, 2, 2, 1, 0],
            vertexCount: 3
        )
        XCTAssertEqual(indices, [0, 1, 2, 2, 1, 0])
    }

    func testValidatedFaceIndicesRejectsNegative() {
        XCTAssertThrowsError(
            try MeshExporter.validatedFaceIndices([Int32(0), 1, -1], vertexCount: 3)
        ) { error in
            XCTAssertEqual(error as? MeshExporterError, .invalidFaceData)
        }
    }

    func testValidatedFaceIndicesRejectsPastVertexCount() {
        XCTAssertThrowsError(
            try MeshExporter.validatedFaceIndices([Int32(0), 1, 3], vertexCount: 3)
        ) { error in
            XCTAssertEqual(error as? MeshExporterError, .invalidFaceData)
        }
    }

    func testValidatedFaceIndicesRejectsInt64Overflow() {
        let tooBig = Int64(UInt32.max) + 1
        XCTAssertThrowsError(
            try MeshExporter.validatedFaceIndices([Int64(0), 1, tooBig], vertexCount: 4)
        ) { error in
            XCTAssertEqual(error as? MeshExporterError, .invalidFaceData)
        }
    }

    func testValidatedFaceIndicesRejectsNonTripleCount() {
        XCTAssertThrowsError(
            try MeshExporter.validatedFaceIndices([Int32(0), 1], vertexCount: 3)
        ) { error in
            XCTAssertEqual(error as? MeshExporterError, .invalidFaceData)
        }
    }

    func testPackageWavefrontExportIncludesOBJAndMTL() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let objURL = dir.appendingPathComponent("knight.obj")
        let mtlURL = MeshExporter.materialURL(forOBJ: objURL)
        try "mtllib knight.mtl\no knight\nv 0 0 0\n".write(to: objURL, atomically: true, encoding: .utf8)
        try "newmtl VertexColorAverage\nKd 0.2 0.2 0.2\n".write(to: mtlURL, atomically: true, encoding: .utf8)

        let zipURL = try MeshExporter.packageWavefrontExport(objURL: objURL)
        XCTAssertEqual(zipURL.pathExtension, "zip")
        let data = try Data(contentsOf: zipURL)
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4b])
        XCTAssertNotNil(data.range(of: Data("knight.obj".utf8)))
        XCTAssertNotNil(data.range(of: Data("knight.mtl".utf8)))
    }

    func testPackageWavefrontExportRequiresMTL() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let objURL = dir.appendingPathComponent("bare.obj")
        try "o bare\n".write(to: objURL, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try MeshExporter.packageWavefrontExport(objURL: objURL))
    }
}
