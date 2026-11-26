// HFBundleDownloader.swift
// Mesquette — Fallback acquisition of the published Shap-E weights bundle
// from Hugging Face, pinned and checksum-verified. Resolution order in
// RuntimeAssetLocator: bundled copy → Background Assets → this downloader.

import CryptoKit
import Foundation

nonisolated enum HFBundleScope: String, Sendable, Equatable {
    case text
    case full
}

nonisolated enum HFBundleError: Error, LocalizedError, Sendable {
    case malformedChecksums(String)
    case missingFile(String)
    case checksumMismatch(String)
    case httpStatus(Int, String)
    case insufficientCoverage(String)

    var errorDescription: String? {
        switch self {
        case .malformedChecksums(let line): return "Malformed checksums.sha256 line: \(line)"
        case .missingFile(let path): return "Downloaded bundle is missing \(path)."
        case .checksumMismatch(let path): return "Checksum mismatch for \(path)."
        case .httpStatus(let code, let path): return "HTTP \(code) downloading \(path)."
        case .insufficientCoverage(let what): return "Published bundle manifest is incomplete: \(what)."
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
    /// (`<base>/models/<repoID>`, the layout HubApi used previously).
    static var downloadBase: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface", isDirectory: true)
    }

    static var endpoint: String {
        let raw = ProcessInfo.processInfo.environment["HF_ENDPOINT"] ?? "https://huggingface.co"
        return raw.hasSuffix("/") ? String(raw.dropLast()) : raw
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
        let bundle = tripoSnapshotURL()
        try await fetchFiles(
            repoID: tripoRepoID, revision: tripoRevision,
            entries: [ChecksumEntry(path: tripoWeightsFile, digest: tripoWeightsSHA256),
                      ChecksumEntry(path: "checksums.sha256", digest: "")],
            into: bundle, progress: progress
        )
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
        // Checksums first: they are the trust anchor and define the file list.
        let bundle = snapshotURL()
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let sumsURL = bundle.appendingPathComponent("checksums.sha256")
        try await fetchFiles(
            repoID: repoID, revision: revision,
            entries: [ChecksumEntry(path: "checksums.sha256", digest: "")],
            into: bundle, progress: nil
        )
        let all = try checksumEntries(in: String(contentsOf: sumsURL, encoding: .utf8))
        let wanted = entries(all, within: scope)
        try validateCoverage(entries: all, scope: scope)
        try await fetchFiles(
            repoID: repoID, revision: revision,
            entries: wanted, into: bundle, progress: progress
        )
        // fetchFiles verifies every file's SHA-256 (downloaded or pre-existing),
        // which is the same gate verify() applies; no second pass needed.
        try Data().write(to: stampURL(in: bundle, scope: scope))
        return bundle
    }
    /// The manifest must actually cover what the scope will run on; an empty
    /// or truncated `checksums.sha256` must fail here, never reach the stamp.
    static func validateCoverage(entries all: [ChecksumEntry], scope: HFBundleScope) throws {
        guard !all.isEmpty else { throw HFBundleError.insufficientCoverage("empty checksums.sha256") }
        guard all.contains(where: { $0.path == "manifest.json" }) else {
            throw HFBundleError.insufficientCoverage("missing manifest.json")
        }
        for family in families(for: scope) {
            guard all.contains(where: { $0.path.hasPrefix(family + "/") }) else {
                throw HFBundleError.insufficientCoverage("no files for family \(family)")
            }
        }
    }

    // MARK: - Parallel fetch engine

    /// Concurrent workers; the previous HubApi snapshot loop was strictly
    /// one-file-at-a-time, which made a ~1,100-file bundle take minutes of
    /// per-file redirect/TLS overhead on a single connection.
    static let maxConcurrentDownloads = 12

    private actor FetchCursor {
        private var index = 0
        func next(_ count: Int) -> Int? {
            guard index < count else { return nil }
            defer { index += 1 }
            return index
        }
    }

    private actor ByteProgress {
        private var done: Int64 = 0
        private let total: Int64
        private let callback: (@Sendable (Double) -> Void)?
        init(total: Int64, callback: (@Sendable (Double) -> Void)?) {
            self.total = max(total, 1)
            self.callback = callback
        }
        func add(_ bytes: Int64) {
            done += bytes
            callback?(min(1, Double(done) / Double(total)))
        }
    }

    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        struct Job {
            let destination: URL
            let path: String
            let continuation: CheckedContinuation<Void, Error>
        }
        private let lock = NSLock()
        private var jobs: [Int: Job] = [:]
        var onBytes: (@Sendable (Int64) -> Void)?

        func register(taskID: Int, destination: URL, path: String, continuation: CheckedContinuation<Void, Error>) {
            lock.lock(); jobs[taskID] = Job(destination: destination, path: path, continuation: continuation); lock.unlock()
        }
        private func take(_ taskID: Int) -> Job? {
            lock.lock(); defer { lock.unlock() }
            return jobs.removeValue(forKey: taskID)
        }
        private func peek(_ taskID: Int) -> Job? {
            lock.lock(); defer { lock.unlock() }
            return jobs[taskID]
        }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            onBytes?(bytesWritten)
        }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            guard let job = peek(downloadTask.taskIdentifier) else { return }
            // A non-2xx body (e.g. a 404 error page) must never be moved into
            // place: digests would catch most cases, but `checksums.sha256`
            // itself has no digest to catch it with.
            if let http = downloadTask.response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                take(downloadTask.taskIdentifier)?.continuation.resume(
                    throwing: HFBundleError.httpStatus(http.statusCode, job.path))
                return
            }
            do {
                try FileManager.default.createDirectory(
                    at: job.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: job.destination.path) {
                    try FileManager.default.removeItem(at: job.destination)
                }
                try FileManager.default.moveItem(at: location, to: job.destination)
            } catch {
                take(downloadTask.taskIdentifier)?.continuation.resume(throwing: error)
            }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let job = take(task.taskIdentifier) else { return }
            if let error { job.continuation.resume(throwing: error) } else { job.continuation.resume() }
        }
    }

    private static func resolveURL(repoID: String, revision: String, path: String) -> URL {
        var url = URL(string: "\(endpoint)/\(repoID)/resolve/\(revision)")!
        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        return url
    }

    /// Best-effort per-file sizes for byte-accurate progress; failures only
    /// degrade progress weighting, never correctness (digests still gate).
    private static func fetchSizes(repoID: String, revision: String) async -> [String: Int64] {
        guard let url = URL(string: "\(endpoint)/api/models/\(repoID)/revision/\(revision)?blobs=true"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let siblings = root["siblings"] as? [[String: Any]] else { return [:] }
        var sizes: [String: Int64] = [:]
        for sib in siblings {
            if let name = sib["rfilename"] as? String, let size = sib["size"] as? Int64 {
                sizes[name] = size
            }
        }
        return sizes
    }

    /// Download `entries` into `bundle` concurrently, verifying each file's
    /// SHA-256 (entries with an empty digest are fetched unverified — used
    /// only for `checksums.sha256` itself, whose *contents* are then the
    /// trust anchor). Existing files with a matching digest are skipped.
    private static func fetchFiles(
        repoID: String,
        revision: String,
        entries: [ChecksumEntry],
        into bundle: URL,
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let sizes = await fetchSizes(repoID: repoID, revision: revision)
        let total = entries.reduce(Int64(0)) { $0 + (sizes[$1.path] ?? 0) }
        let byteProgress = ByteProgress(total: total > 0 ? total : Int64(entries.count), callback: progress)
        let useBytes = total > 0

        let delegate = DownloadDelegate()
        delegate.onBytes = { delta in
            if useBytes { Task { await byteProgress.add(delta) } }
        }
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = maxConcurrentDownloads
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let cursor = FetchCursor()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<min(maxConcurrentDownloads, max(entries.count, 1)) {
                group.addTask {
                    while let i = await cursor.next(entries.count) {
                        let entry = entries[i]
                        let dest = bundle.appendingPathComponent(entry.path)
                        if !entry.digest.isEmpty,
                           FileManager.default.fileExists(atPath: dest.path),
                           (try? sha256Hex(of: dest)) == entry.digest {
                            await byteProgress.add(useBytes ? (sizes[entry.path] ?? 0) : 1)
                            continue
                        }
                        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                            let task = session.downloadTask(with: resolveURL(repoID: repoID, revision: revision, path: entry.path))
                            delegate.register(taskID: task.taskIdentifier, destination: dest, path: entry.path, continuation: cont)
                            task.resume()
                        }
                        if !entry.digest.isEmpty {
                            guard try sha256Hex(of: dest) == entry.digest else {
                                try? FileManager.default.removeItem(at: dest)
                                throw HFBundleError.checksumMismatch(entry.path)
                            }
                        }
                        if !useBytes { await byteProgress.add(1) }
                    }
                }
            }
            try await group.waitForAll()
        }
        progress?(1)
    }

}
