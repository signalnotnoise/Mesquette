// MeshExporter.swift
// Mesquette — Export MeshResult to OBJ / USDZ for DCC and share workflows

import Foundation
import ModelIO
import ShapERuntime
import UniformTypeIdentifiers

nonisolated enum MeshExporterError: LocalizedError, Sendable, Equatable {
    case invalidVertexData
    case invalidFaceData
    case emptyMesh
    case exportFailed(String)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .invalidVertexData: return "Mesh vertex data is invalid."
        case .invalidFaceData: return "Mesh face/index data is invalid."
        case .emptyMesh: return "Mesh has no triangles to export."
        case .exportFailed(let msg): return "Export failed: \(msg)"
        case .unsupportedFormat: return "Unsupported export format."
        }
    }
}

nonisolated enum MeshExportFormat: String, CaseIterable, Identifiable, Sendable {
    case obj
    case usdz

    var id: String { rawValue }

    var title: String {
        switch self {
        case .obj:  return "OBJ"
        case .usdz: return "USDZ"
        }
    }

    var pathExtension: String { rawValue }

    var contentType: UTType {
        switch self {
        case .obj:  return .wavefrontOBJ
        case .usdz: return .usdz // system UTType.usdz (do not redefine — infinite recursion)
        }
    }

    var systemImage: String {
        switch self {
        case .obj:  return "doc.plaintext"
        case .usdz: return "cube.transparent"
        }
    }
}

/// Shared mesh export helpers. Pure data path — no UI.
nonisolated enum MeshExporter {

    // MARK: - Public

    /// Export `mesh` to `url`. Format is inferred from the path extension (`.obj` / `.usdz`).
    nonisolated static func export(_ mesh: MeshResult, to url: URL) throws {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "obj":
            try exportOBJ(mesh, to: url)
        case "usdz":
            try exportUSDZ(mesh, to: url)
        default:
            throw MeshExporterError.unsupportedFormat
        }
    }

    /// Write Wavefront OBJ (+ optional MTL with a simple material). Vertex colors
    /// are written as a companion `.mtl` note via `Kd` average; per-vertex colors
    /// go into an extended OBJ `vc` comment block is avoided — colors are
    /// exported as a PLY-style side channel is not used; instead we bake average
    /// albedo into the MTL for DCC previews.
    nonisolated static func exportOBJ(_ mesh: MeshResult, to url: URL) throws {
        let geometry = try extractGeometry(from: mesh)
        guard geometry.faceCount > 0 else { throw MeshExporterError.emptyMesh }

        let baseName = url.deletingPathExtension().lastPathComponent
        let mtlName = baseName + ".mtl"
        let mtlURL = url.deletingLastPathComponent().appendingPathComponent(mtlName)

        var obj = String()
        obj.reserveCapacity(geometry.positions.count * 24 + geometry.indices.count * 12)
        obj += "# Mesquette OBJ export\n"
        obj += "mtllib \(mtlName)\n"
        obj += "o \(sanitize(baseName))\n"
        obj += "usemtl VertexColorAverage\n"

        for i in stride(from: 0, to: geometry.positions.count, by: 3) {
            obj += "v \(geometry.positions[i]) \(geometry.positions[i + 1]) \(geometry.positions[i + 2])\n"
        }

        // Optional: write vertex colors as `v x y z r g b` (common DCC extension).
        // We already wrote positions; many tools prefer separate. Re-write if colors exist:
        // (skipped — standard `v` only for max compatibility; colors go to MTL average)

        for i in stride(from: 0, to: geometry.indices.count, by: 3) {
            // OBJ is 1-based
            let a = geometry.indices[i] + 1
            let b = geometry.indices[i + 1] + 1
            let c = geometry.indices[i + 2] + 1
            obj += "f \(a) \(b) \(c)\n"
        }

        try obj.write(to: url, atomically: true, encoding: .utf8)

        let avg = averageColor(geometry.colors, vertexCount: geometry.vertexCount)
        let mtl = """
        # Mesquette MTL
        newmtl VertexColorAverage
        Ka 0.1 0.1 0.1
        Kd \(avg.0) \(avg.1) \(avg.2)
        Ks 0.05 0.05 0.05
        Ns 20
        d 1.0
        illum 2
        """
        try mtl.write(to: mtlURL, atomically: true, encoding: .utf8)
    }

    /// Companion `.mtl` written next to an OBJ.
    nonisolated static func materialURL(forOBJ url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("mtl")
    }

    /// Zip the OBJ and its MTL so share/save deliver both files together.
    nonisolated static func packageWavefrontExport(objURL: URL) throws -> URL {
        let mtlURL = materialURL(forOBJ: objURL)
        guard FileManager.default.fileExists(atPath: objURL.path),
              FileManager.default.fileExists(atPath: mtlURL.path) else {
            throw MeshExporterError.exportFailed("OBJ export is missing its companion MTL file.")
        }
        let zipURL = objURL.deletingPathExtension().appendingPathExtension("zip")
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }
        try ZipStore.write(
            entries: [
                (objURL.lastPathComponent, try Data(contentsOf: objURL)),
                (mtlURL.lastPathComponent, try Data(contentsOf: mtlURL))
            ],
            to: zipURL
        )
        return zipURL
    }

    /// Export USDZ via Model I/O (positions + indices; optional vertex colors).
    nonisolated static func exportUSDZ(_ mesh: MeshResult, to url: URL) throws {
        let geometry = try extractGeometry(from: mesh)
        guard geometry.faceCount > 0 else { throw MeshExporterError.emptyMesh }

        let asset = try makeMDLAsset(geometry: geometry)
        // Model I/O requires the destination directory to exist.
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        do {
            try asset.export(to: url)
        } catch {
            throw MeshExporterError.exportFailed(error.localizedDescription)
        }
    }

    /// Default filename stem from a prompt + short id.
    nonisolated static func suggestedFileName(prompt: String, id: UUID, format: MeshExportFormat) -> String {
        let slug = prompt
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(6)
            .joined(separator: "-")
        let base = slug.isEmpty ? "mesh" : String(slug.prefix(48))
        let short = id.uuidString.prefix(8)
        return "\(base)-\(short).\(format.pathExtension)"
    }

    /// Application Support exports directory.
    nonisolated static func exportsDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = root
            .appendingPathComponent("Mesquette", isDirectory: true)
            .appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Geometry extraction

    nonisolated struct Geometry: Sendable {
        var positions: [Float]   // xyz * vertexCount
        var indices: [UInt32]    // triangle list
        var colors: [Float]?     // rgba * vertexCount
        var vertexCount: Int
        var faceCount: Int
    }

    nonisolated static func extractGeometry(from mesh: MeshResult) throws -> Geometry {
        let rawVertices = try mesh.vertices.float32Values()
        guard rawVertices.count % 3 == 0, !rawVertices.isEmpty else {
            throw MeshExporterError.invalidVertexData
        }
        let vertexCount = rawVertices.count / 3

        let indices: [UInt32]
        if mesh.faces.dataType == .int32 {
            indices = try validatedFaceIndices(try mesh.faces.int32Values(), vertexCount: vertexCount)
        } else if mesh.faces.dataType == .int64 {
            indices = try validatedFaceIndices(try mesh.faces.int64Values(), vertexCount: vertexCount)
        } else {
            throw MeshExporterError.invalidFaceData
        }

        var colors: [Float]? = nil
        if let rgba = mesh.vertexChannels?["RGBA"] {
            let vals = try rgba.float32Values()
            if vals.count == vertexCount * 4 {
                colors = vals
            }
        }

        return Geometry(
            positions: rawVertices,
            indices: indices,
            colors: colors,
            vertexCount: vertexCount,
            faceCount: indices.count / 3
        )
    }

    /// Converts signed face indices to `UInt32` without trapping. Rejects
    /// negatives, values that don't fit in 32 bits, non-triangle lists, and
    /// indices at or past `vertexCount`.
    nonisolated static func validatedFaceIndices<T: BinaryInteger>(
        _ raw: [T],
        vertexCount: Int
    ) throws -> [UInt32] {
        guard vertexCount >= 0,
              vertexCount <= Int(UInt32.max),
              raw.count % 3 == 0
        else {
            throw MeshExporterError.invalidFaceData
        }
        let vertexLimit = UInt32(vertexCount)
        var indices = [UInt32]()
        indices.reserveCapacity(raw.count)
        for v in raw {
            guard let index = UInt32(exactly: v), index < vertexLimit else {
                throw MeshExporterError.invalidFaceData
            }
            indices.append(index)
        }
        return indices
    }

    // MARK: - Model I/O

    nonisolated private static func makeMDLAsset(geometry: Geometry) throws -> MDLAsset {
        let allocator = MDLMeshBufferDataAllocator()

        let positionData = geometry.positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let positionBuffer = allocator.newBuffer(with: positionData, type: .vertex)

        let descriptor = MDLVertexDescriptor()
        let positionAttr = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        descriptor.attributes[0] = positionAttr
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 3)

        var vertexBuffers: [MDLMeshBuffer] = [positionBuffer]

        if let colors = geometry.colors {
            // Pack RGB only for MDL (float3).
            var rgb = [Float]()
            rgb.reserveCapacity(geometry.vertexCount * 3)
            for i in 0..<geometry.vertexCount {
                let base = i * 4
                rgb.append(colors[base])
                rgb.append(colors[base + 1])
                rgb.append(colors[base + 2])
            }
            let colorData = rgb.withUnsafeBufferPointer { Data(buffer: $0) }
            let colorBuffer = allocator.newBuffer(with: colorData, type: .vertex)
            let colorAttr = MDLVertexAttribute(
                name: MDLVertexAttributeColor,
                format: .float3,
                offset: 0,
                bufferIndex: 1
            )
            descriptor.attributes[1] = colorAttr
            descriptor.layouts[1] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 3)
            vertexBuffers.append(colorBuffer)
        }

        let indexData = geometry.indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)
        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: geometry.indices.count,
            indexType: .uInt32,
            geometryType: .triangles,
            material: nil
        )

        let mdlMesh = MDLMesh(
            vertexBuffers: vertexBuffers,
            vertexCount: geometry.vertexCount,
            descriptor: descriptor,
            submeshes: [submesh]
        )

        let asset = MDLAsset(bufferAllocator: allocator)
        asset.add(mdlMesh)
        return asset
    }

    // MARK: - Helpers

    nonisolated private static func averageColor(_ colors: [Float]?, vertexCount: Int) -> (Float, Float, Float) {
        guard let colors, vertexCount > 0, colors.count >= vertexCount * 4 else {
            return (0.75, 0.75, 0.75)
        }
        var r: Float = 0, g: Float = 0, b: Float = 0
        for i in 0..<vertexCount {
            let base = i * 4
            r += colors[base]
            g += colors[base + 1]
            b += colors[base + 2]
        }
        let n = Float(vertexCount)
        return (r / n, g / n, b / n)
    }

    nonisolated private static func sanitize(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: " ", with: "_")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return String(cleaned.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}

// MARK: - UTType helpers

extension UTType {
    /// Wavefront OBJ — not a built-in UTType on all SDKs.
    /// FileDocument.readableContentTypes is nonisolated; this must match.
    nonisolated static var wavefrontOBJ: UTType {
        UTType(filenameExtension: "obj") ?? .data
    }
}

// MARK: - ZIP (store-only)

/// Minimal ZIP writer (no compression) so OBJ + MTL travel as one file.
nonisolated enum ZipStore {
    nonisolated static func write(entries: [(String, Data)], to url: URL) throws {
        guard !entries.isEmpty else {
            throw MeshExporterError.exportFailed("ZIP has no entries.")
        }
        var local = Data()
        var central = Data()
        for (name, payload) in entries {
            let filename = Data(name.utf8)
            guard !filename.isEmpty, !name.contains("/") else {
                throw MeshExporterError.exportFailed("Invalid ZIP entry name.")
            }
            let crc = crc32(payload)
            let offset = UInt32(local.count)
            let size = UInt32(payload.count)
            appendLocalFileHeader(to: &local, filename: filename, crc: crc, size: size)
            local.append(payload)
            appendCentralDirectoryHeader(
                to: &central,
                filename: filename,
                crc: crc,
                size: size,
                localHeaderOffset: offset
            )
        }
        let centralOffset = UInt32(local.count)
        let centralSize = UInt32(central.count)
        local.append(central)
        appendEndOfCentralDirectory(
            to: &local,
            entryCount: UInt16(entries.count),
            centralSize: centralSize,
            centralOffset: centralOffset
        )
        try local.write(to: url, options: .atomic)
    }

    private static func appendLocalFileHeader(to data: inout Data, filename: Data, crc: UInt32, size: UInt32) {
        appendUInt32(&data, 0x04034b50)
        appendUInt16(&data, 20) // version needed
        appendUInt16(&data, 1 << 11) // UTF-8 names
        appendUInt16(&data, 0) // stored
        appendUInt16(&data, 0)
        appendUInt16(&data, 0)
        appendUInt32(&data, crc)
        appendUInt32(&data, size)
        appendUInt32(&data, size)
        appendUInt16(&data, UInt16(filename.count))
        appendUInt16(&data, 0)
        data.append(filename)
    }

    private static func appendCentralDirectoryHeader(
        to data: inout Data,
        filename: Data,
        crc: UInt32,
        size: UInt32,
        localHeaderOffset: UInt32
    ) {
        appendUInt32(&data, 0x02014b50)
        appendUInt16(&data, 20)
        appendUInt16(&data, 20)
        appendUInt16(&data, 1 << 11)
        appendUInt16(&data, 0)
        appendUInt16(&data, 0)
        appendUInt16(&data, 0)
        appendUInt32(&data, crc)
        appendUInt32(&data, size)
        appendUInt32(&data, size)
        appendUInt16(&data, UInt16(filename.count))
        appendUInt16(&data, 0)
        appendUInt16(&data, 0)
        appendUInt16(&data, 0)
        appendUInt16(&data, 0)
        appendUInt32(&data, 0)
        appendUInt32(&data, localHeaderOffset)
        data.append(filename)
    }

    private static func appendEndOfCentralDirectory(
        to data: inout Data,
        entryCount: UInt16,
        centralSize: UInt32,
        centralOffset: UInt32
    ) {
        appendUInt32(&data, 0x06054b50)
        appendUInt16(&data, 0)
        appendUInt16(&data, 0)
        appendUInt16(&data, entryCount)
        appendUInt16(&data, entryCount)
        appendUInt32(&data, centralSize)
        appendUInt32(&data, centralOffset)
        appendUInt16(&data, 0)
    }

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crc32Table[idx] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    private static let crc32Table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) == 1 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }
}
