import RuntimeWrapper
import XCTest
@testable import Mesquette

final class HFBundleDownloaderTests: XCTestCase {

    func testPinnedRevision() {
        XCTAssertEqual(HFBundleDownloader.repoID, "signalNotNoise/shap-e-mlx")
        XCTAssertEqual(HFBundleDownloader.revision, "d71f70a09b9c03535188d006a719edda5c19a6eb")
    }

    func testTextScopeExcludesImageFamilies() {
        let globs = HFBundleDownloader.globs(for: .text)
        XCTAssertTrue(globs.contains("manifest.json"))
        XCTAssertTrue(globs.contains("text300m/*.bin"))
        XCTAssertFalse(globs.contains("clip_vision/*.bin"))
        XCTAssertFalse(globs.contains("image300m/*.bin"))
    }

    func testFullScopeIncludesImageFamilies() {
        let globs = HFBundleDownloader.globs(for: .full)
        XCTAssertTrue(globs.contains("clip_vision/*.bin"))
        XCTAssertTrue(globs.contains("image300m/*.bin"))
    }

    func testChecksumParsingAndScopeFilter() throws {
        let d = String(repeating: "a", count: 64)
        let text = """
        \(d)  manifest.json
        \(d)  text300m/w.bin
        \(d)  clip_vision/w.bin
        \(d)  validation/l2.log
        """
        let all = try HFBundleDownloader.checksumEntries(in: text)
        XCTAssertEqual(all.count, 4)
        let scoped = HFBundleDownloader.entries(all, within: .text)
        XCTAssertEqual(scoped.map(\.path), ["manifest.json", "text300m/w.bin"])
    }

    func testChecksumParsingRejectsMalformedLine() {
        XCTAssertThrowsError(try HFBundleDownloader.checksumEntries(in: "not-a-checksum-line"))
    }

    func testStampSatisfiesWeakerScope() {
        XCTAssertTrue(HFBundleDownloader.scope(.full, satisfies: .text))
        XCTAssertTrue(HFBundleDownloader.scope(.text, satisfies: .text))
        XCTAssertFalse(HFBundleDownloader.scope(.text, satisfies: .full))
    }

    func testTripoSRPinnedArtifacts() {
        XCTAssertEqual(HFBundleDownloader.tripoRepoID, "signalNotNoise/triposr-mlx")
        XCTAssertEqual(HFBundleDownloader.tripoRevision, "17a0c5286e2b2bb6fc9e3654ca31cfc9dc4b2041")
        XCTAssertEqual(HFBundleDownloader.tripoWeightsFile, "triposr_swift_ready.safetensors")
        XCTAssertEqual(HFBundleDownloader.tripoWeightsSHA256,
                       "83563625f39180f505a3ccb855e67b59b65989f6545015672465d7487c4bc2cb")
    }

    func testVerifyRejectsCorruptedFile() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hf-bundle-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("manifest".utf8).write(to: dir.appendingPathComponent("manifest.json"))
        // SHA-256 of "manifest" is not all-zero; verification must fail closed.
        let sums = String(repeating: "0", count: 64) + "  manifest.json\n"
        try sums.write(to: dir.appendingPathComponent("checksums.sha256"), atomically: true, encoding: .utf8)
        do {
            try await HFBundleDownloader.verify(bundleURL: dir, scope: .text)
            XCTFail("expected checksum mismatch")
        } catch {
            // expected
        }
    }
}

@MainActor
final class ModelSelectionTests: XCTestCase {
    func testDefaultModelIsShapEOrPersisted() {
        let app = AppModel()
        XCTAssertTrue([ThreeDGenerationModel.shapE, .tripoSR].contains(app.generationModel))
    }

    func testSelectingTripoSRForcesImageMode() {
        let app = AppModel()
        app.generationModel = .shapE
        app.inputMode = .text
        app.generationModel = .tripoSR
        XCTAssertEqual(app.inputMode, .image)
        app.generationModel = .shapE  // restore persisted default for other tests
    }
}
