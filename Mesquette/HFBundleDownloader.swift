// HFBundleDownloader.swift
// Mesquette — Fallback acquisition of the published Shap-E weights bundle
// from Hugging Face, pinned and checksum-verified. Resolution order in
// RuntimeAssetLocator: bundled copy → Background Assets → this downloader.

import CryptoKit
import Foundation
import Hub

nonisolated enum HFBundleScope: String, Sendable, Equatable {
    case text
    case full
}

nonisolated enum HFBundleError: Error, LocalizedError, Sendable {
    case malformedChecksums(String)
    case missingFile(String)
    case checksumMismatch(String)

    var errorDescription: String? {
        switch self {
        case .malformedChecksums(let line): return "Malformed checksums.sha256 line: \(line)"
        case .missingFile(let path): return "Downloaded bundle is missing \(path)."
        case .checksumMismatch(let path): return "Checksum mismatch for \(path)."
        }
    }
}

nonisolated enum HFBundleDownloader {
    static let repoID = "signalNotNoise/shap-e-mlx"
    /// v0.1.0. Bump only after a replacement snapshot passes foundations'
    /// release procedure (docs/RELEASE-STATUS.md in apple-mlx-foundations).
    static let revision = "d71f70a09b9c03535188d006a719edda5c19a6eb"

    static let textFamilies = ["clip_text", "text300m", "diffusion", "decoder_params", "renderer"]
    static let imageFamilies = ["clip_vision", "image300m"]
    static let rootFiles = ["manifest.json", "bpe_simple_vocab_16e6.txt.gz", "checksums.sha256", "provenance.json", "LICENSE"]

    static func families(for scope: HFBundleScope) -> [String] {
        scope == .full ? textFamilies + imageFamilies : textFamilies
    }

    static func globs(for scope: HFBundleScope) -> [String] {
        rootFiles + families(for: scope).map { "\($0)/*.bin" }
    }

    static func scope(_ have: HFBundleScope, satisfies want: HFBundleScope) -> Bool {
        have == .full || want == .text
    }

    // MARK: - Checksums

    struct ChecksumEntry: Equatable, Sendable {
        let path: String
        let digest: String
    }

    static func checksumEntries(in text: String) throws -> [ChecksumEntry] {
        var entries: [ChecksumEntry] = []
        for raw in text.split(separator: "\n") {
            let line = String(raw)
            guard let sep = line.range(of: "  ") else { throw HFBundleError.malformedChecksums(line) }
            let digest = String(line[line.startIndex..<sep.lowerBound]).lowercased()
            let path = String(line[sep.upperBound...])
            guard digest.count == 64, !path.isEmpty else { throw HFBundleError.malformedChecksums(line) }
            entries.append(ChecksumEntry(path: path, digest: digest))
        }
        return entries
    }

    static func entries(_ all: [ChecksumEntry], within scope: HFBundleScope) -> [ChecksumEntry] {
        let families = Set(families(for: scope))
        return all.filter { entry in
            if rootFiles.contains(entry.path) { return true }
            guard let slash = entry.path.firstIndex(of: "/") else { return false }
            return families.contains(String(entry.path[..<slash]))
        }
    }

    /// Verify every in-scope payload file in `bundleURL` against its
    /// published `checksums.sha256`. Fails closed on any miss.
    static func verify(bundleURL: URL, scope: HFBundleScope) async throws {
        let sumsURL = bundleURL.appendingPathComponent("checksums.sha256")
        let text = try String(contentsOf: sumsURL, encoding: .utf8)
        for entry in try entries(checksumEntries(in: text), within: scope) {
            let file = bundleURL.appendingPathComponent(entry.path)
            guard FileManager.default.fileExists(atPath: file.path) else {
                throw HFBundleError.missingFile(entry.path)
            }
            let digest = try sha256Hex(of: file)
            guard digest == entry.digest else { throw HFBundleError.checksumMismatch(entry.path) }
        }
    }

    private static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }  // best-effort close; nothing actionable on failure
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Download

    /// Caches directory the materialized snapshot lives under
    /// (`HubApi` returns `<base>/models/<repoID>`).
    static var downloadBase: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface", isDirectory: true)
    }

    static func snapshotURL() -> URL {
        downloadBase.appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(repoID, isDirectory: true)
    }

    private static func stampURL(in bundle: URL, scope: HFBundleScope) -> URL {
        bundle.appendingPathComponent(".mesquette-verified-\(revision)-\(scope.rawValue)")
    }

    /// A snapshot is reusable offline once its scope passed full checksum
    /// verification (stamped). A full stamp also satisfies a text request.
    static func verifiedLocalBundle(scope want: HFBundleScope) -> URL? {
        let bundle = snapshotURL()
        guard FileManager.default.fileExists(atPath: bundle.appendingPathComponent("manifest.json").path) else { return nil }
        for have in [HFBundleScope.full, .text] where scope(have, satisfies: want) {
            if FileManager.default.fileExists(atPath: stampURL(in: bundle, scope: have).path) { return bundle }
        }
        return nil
    }

    // MARK: - TripoSR weights

    static let tripoRepoID = "signalNotNoise/triposr-mlx"
    static let tripoRevision = "17a0c5286e2b2bb6fc9e3654ca31cfc9dc4b2041"
    static let tripoWeightsFile = "triposr_swift_ready.safetensors"
    /// SHA-256 of `triposr_swift_ready.safetensors` at `tripoRevision`
    /// (also listed in that repo's `checksums.sha256`).
    static let tripoWeightsSHA256 = "83563625f39180f505a3ccb855e67b59b65989f6545015672465d7487c4bc2cb"

    static func tripoSnapshotURL() -> URL {
        downloadBase.appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(tripoRepoID, isDirectory: true)
    }

    /// Verified local TripoSR weights file, if a previous resolve stamped it.
    static func verifiedTripoWeightsURL() -> URL? {
        let dir = tripoSnapshotURL()
        let weights = dir.appendingPathComponent(tripoWeightsFile)
        let stamp = dir.appendingPathComponent(".mesquette-verified-\(tripoRevision)")
        guard FileManager.default.fileExists(atPath: weights.path),
              FileManager.default.fileExists(atPath: stamp.path) else { return nil }
        return weights
    }

    /// Download (or reuse) the pinned TripoSR weights and verify the digest
    /// against both the bundle's `checksums.sha256` and the pinned constant.
    static func resolveTripoSRWeights(progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        if let local = verifiedTripoWeightsURL() { return local }
        let api = HubApi(downloadBase: downloadBase)
        let bundle = try await api.snapshot(
            from: tripoRepoID,
            revision: tripoRevision,
            matching: [tripoWeightsFile, "checksums.sha256"]
        ) { p in
            if p.totalUnitCount > 0 { progress?(Double(p.completedUnitCount) / Double(p.totalUnitCount)) }
        }
        let weights = bundle.appendingPathComponent(tripoWeightsFile)
        guard FileManager.default.fileExists(atPath: weights.path) else {
            throw HFBundleError.missingFile(tripoWeightsFile)
        }
        let sumsText = try String(contentsOf: bundle.appendingPathComponent("checksums.sha256"), encoding: .utf8)
        let listed = try checksumEntries(in: sumsText).first { $0.path == tripoWeightsFile }?.digest
        guard listed == tripoWeightsSHA256 else { throw HFBundleError.checksumMismatch("checksums.sha256") }
        guard try sha256Hex(of: weights) == tripoWeightsSHA256 else {
            throw HFBundleError.checksumMismatch(tripoWeightsFile)
        }
        try Data().write(to: bundle.appendingPathComponent(".mesquette-verified-\(tripoRevision)"))
        return weights
    }

    /// Download (or reuse) the pinned public bundle and verify it.
    /// Returns a directory ShapERuntime can treat as `modelBundleURL`.
    static func resolveBundle(scope: HFBundleScope, progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        if let local = verifiedLocalBundle(scope: scope) { return local }
        let api = HubApi(downloadBase: downloadBase)
        let bundle = try await api.snapshot(
            from: repoID,
            revision: revision,
            matching: globs(for: scope)
        ) { p in
            if p.totalUnitCount > 0 { progress?(Double(p.completedUnitCount) / Double(p.totalUnitCount)) }
        }
        try await verify(bundleURL: bundle, scope: scope)
        try Data().write(to: stampURL(in: bundle, scope: scope))
        return bundle
    }
}
