//
//  ShapEMeshAdapter.swift
//  Mesquette
//
//  visionOS mesh + colour path for Shap-E MeshResult → RealityKit.
//
//  Colour strategy (important):
//  macOS / iPad use SceneKit *true vertex colours* (SCNGeometrySource.color),
//  which the GPU interpolates correctly across each triangle.
//
//  RealityKit has no MeshDescriptor vertex-colour channel that standard
//  materials will shade. The previous approach stuffed every vertex colour into
//  a 2-D atlas at UV = f(vertexIndex). That is wrong: UV interpolation across a
//  face samples unrelated atlas texels → scrambled / “off” colours.
//
//  Fix: expand to a non-indexed mesh and give each triangle its own 2×2 block
//  whose corners hold the three vertex colours (fourth = c1+c2−c0 so bilinear
//  sampling matches barycentric interpolation). Sample with UnlitMaterial so
//  results match SceneKit’s constant lighting.
//

#if os(visionOS)
import Foundation
import os
import RealityKit
import SwiftUI
import ShapERuntime
import simd
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum ShapEMeshAdapterError: Error {
    case invalidVertexData
    case invalidFaceData
    case meshGenerationFailed
    case capacityExceeded
}

/// Converts a `MeshResult` into RealityKit geometry for visionOS, baking
/// vertex colors per-triangle into a texture (RealityKit has no vertex-color
/// channel standard materials will shade). See the file header for details.
public struct ShapEMeshAdapter {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.visionarydevops.Mesquette",
        category: "mesh-adapter"
    )

    // MARK: - Public API

    /// Converts a `ShapERuntime.MeshResult` into a RealityKit `ModelEntity`.
    @MainActor
    public static func createModelEntity(from result: MeshResult, isPartial: Bool = false) async throws -> ModelEntity {
        let (meshResource, textureResource) = try await createMeshAndTexture(from: result, isPartial: isPartial)
        let material = makeMaterial(texture: textureResource)
        let modelEntity = ModelEntity(mesh: meshResource, materials: [material])
        modelEntity.generateCollisionShapes(recursive: true)
        modelEntity.components.set(InputTargetComponent(allowedInputTypes: .indirect))
        return modelEntity
    }

    /// Builds a material that shows Shap-E colours faithfully (unlit, like SceneKit `.constant`).
    public static func makeMaterial(texture: TextureResource?) -> any RealityKit.Material {
        if let texture {
            // Prefer Unlit so environment lighting does not wash out baked colours.
            var material = UnlitMaterial()
            material.color = UnlitMaterial.BaseColor(texture: .init(texture))
            return material
        } else {
            var material = UnlitMaterial()
            material.color = UnlitMaterial.BaseColor(tint: UIColor(white: 0.75, alpha: 1.0))
            return material
        }
    }

    // MARK: - Mesh + Texture builder

    @MainActor
    public static func createMeshAndTexture(
        from result: MeshResult,
        isPartial: Bool = false
    ) async throws -> (MeshResource, TextureResource?) {

        let geometry = try extractGeometry(from: result)

        // Partials / missing colour channels → untextured mesh.
        guard !isPartial,
              let colors = geometry.colors,
              colors.count == geometry.vertexCount * 4
        else {
            if isPartial {
                logger.info("Partial mesh – skipping vertex colours.")
            } else {
                logger.info("No vertex colour channels – uniform material.")
            }
            let mesh = try buildMeshDescriptor(
                positions: geometry.positions,
                indices: geometry.indices,
                uvs: nil
            )
            return (mesh, nil)
        }

        let baked = try bakeVertexColorsPerTriangle(
            positions: geometry.positions,
            indices: geometry.indices,
            colorsRGBA: colors
        )

        var textureResource: TextureResource?
        if let cgImage = makeCGImage(
            pixels: baked.pixels,
            width: baked.texWidth,
            height: baked.texHeight
        ) {
            do {
                var options = TextureResource.CreateOptions(semantic: .color)
                options.mipmapsMode = .none
                textureResource = try await TextureResource(
                    image: cgImage,
                    withName: "ShapEVertexColours",
                    options: options
                )
                logger.debug("Per-triangle colour texture \(baked.texWidth)x\(baked.texHeight) for \(baked.triangleCount) tris (\(baked.positions.count) expanded verts)")
            } catch {
                logger.error("TextureResource creation failed: \(error.localizedDescription, privacy: .public). Falling back to uniform material.")
                let mesh = try buildMeshDescriptor(
                    positions: geometry.positions,
                    indices: geometry.indices,
                    uvs: nil
                )
                return (mesh, nil)
            }
        }

        let meshResource = try buildMeshDescriptor(
            positions: baked.positions,
            indices: baked.indices,
            uvs: baked.uvs
        )
        return (meshResource, textureResource)
    }

    // MARK: - MeshDescriptor builder

    private static func buildMeshDescriptor(
        positions: [SIMD3<Float>],
        indices: [UInt32],
        uvs: [SIMD2<Float>]?
    ) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: "ShapEGeneratedMesh")
        descriptor.positions = MeshBuffer(positions)
        descriptor.primitives = .triangles(indices)
        if let uvs {
            descriptor.textureCoordinates = MeshBuffer(uvs)
        }
        return try MeshResource.generate(from: [descriptor])
    }

    // MARK: - Geometry extraction

    private struct ExtractedGeometry {
        var positions: [SIMD3<Float>]
        var indices: [UInt32]
        var colors: [Float]? // rgba * vertexCount, optional
        var vertexCount: Int
    }

    private static func extractGeometry(from result: MeshResult) throws -> ExtractedGeometry {
        let rawVertices = try result.vertices.float32Values()
        guard rawVertices.count % 3 == 0 else {
            throw ShapEMeshAdapterError.invalidVertexData
        }
        let vertexCount = rawVertices.count / 3

        var positions = [SIMD3<Float>]()
        positions.reserveCapacity(vertexCount)
        for i in stride(from: 0, to: rawVertices.count, by: 3) {
            positions.append(SIMD3<Float>(rawVertices[i], rawVertices[i + 1], rawVertices[i + 2]))
        }

        let indices: [UInt32]
        if result.faces.dataType == .int32 {
            indices = try faceIndices(try result.faces.int32Values(), vertexCount: vertexCount)
        } else if result.faces.dataType == .int64 {
            indices = try faceIndices(try result.faces.int64Values(), vertexCount: vertexCount)
        } else {
            throw ShapEMeshAdapterError.invalidFaceData
        }

        var colors: [Float]?
        if let rgbaTensor = result.vertexChannels?["RGBA"] {
            let vals = try rgbaTensor.float32Values()
            if vals.count == vertexCount * 4 {
                colors = vals
            } else {
                logger.error("Colour channel count mismatch – RGBA \(vals.count) vs expected \(vertexCount * 4).")
            }
        }

        return ExtractedGeometry(
            positions: positions,
            indices: indices,
            colors: colors,
            vertexCount: vertexCount
        )
    }

    private static func faceIndices<T: BinaryInteger>(_ raw: [T], vertexCount: Int) throws -> [UInt32] {
        do {
            return try MeshExporter.validatedFaceIndices(raw, vertexCount: vertexCount)
        } catch {
            throw ShapEMeshAdapterError.invalidFaceData
        }
    }

    // MARK: - Per-triangle colour bake

    private struct BakedColourMesh {
        var positions: [SIMD3<Float>]
        var indices: [UInt32]
        var uvs: [SIMD2<Float>]
        var pixels: [UInt8]
        var texWidth: Int
        var texHeight: Int
        var triangleCount: Int
    }

    /// Expands the mesh and builds a texture where each triangle owns a 2×2
    /// block whose bilinear samples match barycentric vertex-colour mixes.
    private static func bakeVertexColorsPerTriangle(
        positions: [SIMD3<Float>],
        indices: [UInt32],
        colorsRGBA: [Float]
    ) throws -> BakedColourMesh {
        guard indices.count % 3 == 0 else {
            throw ShapEMeshAdapterError.invalidFaceData
        }
        let triangleCount = indices.count / 3
        guard triangleCount > 0 else {
            throw ShapEMeshAdapterError.invalidFaceData
        }

        // Pack 2×2 blocks in a roughly square atlas.
        let blocksPerRow = max(1, Int(ceil(sqrt(Double(triangleCount)))))
        let blockRows = Int(ceil(Double(triangleCount) / Double(blocksPerRow)))
        let texWidth = blocksPerRow * 2
        let texHeight = blockRows * 2

        var pixels = [UInt8](repeating: 128, count: texWidth * texHeight * 4)

        var outPositions = [SIMD3<Float>]()
        var outUVs = [SIMD2<Float>]()
        var outIndices = [UInt32]()
        outPositions.reserveCapacity(triangleCount * 3)
        outUVs.reserveCapacity(triangleCount * 3)
        outIndices.reserveCapacity(triangleCount * 3)

        let texW = Float(texWidth)
        let texH = Float(texHeight)

        for t in 0..<triangleCount {
            let i0 = Int(indices[t * 3])
            let i1 = Int(indices[t * 3 + 1])
            let i2 = Int(indices[t * 3 + 2])

            guard i0 < positions.count, i1 < positions.count, i2 < positions.count else {
                throw ShapEMeshAdapterError.invalidFaceData
            }

            let c0 = colorRGB(colorsRGBA, vertex: i0)
            let c1 = colorRGB(colorsRGBA, vertex: i1)
            let c2 = colorRGB(colorsRGBA, vertex: i2)
            // Fourth corner chosen so bilinear == barycentric for the lower-left triangle.
            let c3 = SIMD3<Float>(
                max(0, min(1, c1.x + c2.x - c0.x)),
                max(0, min(1, c1.y + c2.y - c0.y)),
                max(0, min(1, c1.z + c2.z - c0.z))
            )

            let bx = (t % blocksPerRow) * 2
            let by = (t / blocksPerRow) * 2

            writeTexel(&pixels, width: texWidth, x: bx,     y: by,     color: c0)
            writeTexel(&pixels, width: texWidth, x: bx + 1, y: by,     color: c1)
            writeTexel(&pixels, width: texWidth, x: bx,     y: by + 1, color: c2)
            writeTexel(&pixels, width: texWidth, x: bx + 1, y: by + 1, color: c3)

            // Map the unit square (0,0)-(1,1) onto this 2×2 block with a tiny
            // inset so bilinear samples don't bleed into neighbouring triangles.
            // V is flipped: CGImage y grows down, RealityKit V grows up.
            let inset: Float = 0.02
            let u0 = (Float(bx) + inset) / texW
            let u1 = (Float(bx + 2) - inset) / texW
            let vTop = 1.0 - (Float(by) + inset) / texH
            let vBot = 1.0 - (Float(by + 2) - inset) / texH

            let base = UInt32(outPositions.count)
            outPositions.append(positions[i0])
            outPositions.append(positions[i1])
            outPositions.append(positions[i2])
            // c0 @ (0,0), c1 @ (1,0), c2 @ (0,1) of the unit square
            outUVs.append(SIMD2<Float>(u0, vTop))
            outUVs.append(SIMD2<Float>(u1, vTop))
            outUVs.append(SIMD2<Float>(u0, vBot))
            outIndices.append(base)
            outIndices.append(base + 1)
            outIndices.append(base + 2)
        }

        return BakedColourMesh(
            positions: outPositions,
            indices: outIndices,
            uvs: outUVs,
            pixels: pixels,
            texWidth: texWidth,
            texHeight: texHeight,
            triangleCount: triangleCount
        )
    }

    private static func colorRGB(_ rgba: [Float], vertex: Int) -> SIMD3<Float> {
        let base = vertex * 4
        return SIMD3<Float>(
            max(0, min(1, rgba[base])),
            max(0, min(1, rgba[base + 1])),
            max(0, min(1, rgba[base + 2]))
        )
    }

    private static func writeTexel(
        _ pixels: inout [UInt8],
        width: Int,
        x: Int,
        y: Int,
        color: SIMD3<Float>
    ) {
        let idx = (y * width + x) * 4
        pixels[idx]     = UInt8(color.x * 255.0 + 0.5)
        pixels[idx + 1] = UInt8(color.y * 255.0 + 0.5)
        pixels[idx + 2] = UInt8(color.z * 255.0 + 0.5)
        pixels[idx + 3] = 255
    }

    // MARK: - CGImage helper

    /// Builds a CGImage from a flat RGBA8 byte array (sRGB, non-premultiplied).
    private static func makeCGImage(
        pixels: [UInt8],
        width: Int,
        height: Int
    ) -> CGImage? {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }

        // noneSkipLast = RGBA with ignored alpha slot; safer than premultiplied
        // for opaque colour atlases (avoids accidental darkening).
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true, // bilinear for barycentric colour mixes
            intent: .defaultIntent
        )
    }

    // MARK: - LowLevelMesh Support

    @MainActor
    public static func createLowLevelMesh(
        vertexCapacity: Int = 450_000,
        indexCapacity: Int = 450_000
    ) throws -> LowLevelMesh {
        // Expanded coloured meshes use 3 verts per triangle, so capacity is
        // sized for typical Standard/High Shap-E outputs with headroom.
        var desc = LowLevelMesh.Descriptor()
        desc.vertexAttributes = [
            LowLevelMesh.Attribute(semantic: .position, format: .float3, offset: 0),
            LowLevelMesh.Attribute(
                semantic: .uv0,
                format: .float2,
                offset: MemoryLayout<SIMD3<Float>>.stride
            )
        ]
        desc.vertexLayouts = [
            LowLevelMesh.Layout(bufferIndex: 0, bufferStride: MemoryLayout<ShapEVertex>.stride)
        ]
        desc.vertexCapacity = vertexCapacity
        desc.indexCapacity = indexCapacity
        desc.indexType = .uint32

        return try LowLevelMesh(descriptor: desc)
    }

    @MainActor
    public static func updateLowLevelMesh(
        _ lowLevelMesh: LowLevelMesh,
        from result: MeshResult,
        isPartial: Bool = false
    ) async throws -> TextureResource? {
        let geometry = try extractGeometry(from: result)

        let useColors = !isPartial
            && geometry.colors != nil
            && geometry.colors!.count == geometry.vertexCount * 4

        let positions: [SIMD3<Float>]
        let indices: [UInt32]
        let uvs: [SIMD2<Float>]?
        var textureResource: TextureResource?

        if useColors, let colors = geometry.colors {
            let baked = try bakeVertexColorsPerTriangle(
                positions: geometry.positions,
                indices: geometry.indices,
                colorsRGBA: colors
            )
            positions = baked.positions
            indices = baked.indices
            uvs = baked.uvs

            if let cgImage = makeCGImage(
                pixels: baked.pixels,
                width: baked.texWidth,
                height: baked.texHeight
            ) {
                do {
                    var options = TextureResource.CreateOptions(semantic: .color)
                    options.mipmapsMode = .none
                    textureResource = try await TextureResource(
                        image: cgImage,
                        withName: "ShapEVertexColours_\(UUID().uuidString)",
                        options: options
                    )
                } catch {
                    logger.error("TextureResource creation failed: \(error)")
                }
            }
        } else {
            positions = geometry.positions
            indices = geometry.indices
            uvs = nil
        }

        guard positions.count <= lowLevelMesh.descriptor.vertexCapacity else {
            logger.error("vertexCount \(positions.count) exceeds capacity \(lowLevelMesh.descriptor.vertexCapacity)")
            throw ShapEMeshAdapterError.capacityExceeded
        }
        guard indices.count <= lowLevelMesh.descriptor.indexCapacity else {
            logger.error("indexCount \(indices.count) exceeds capacity \(lowLevelMesh.descriptor.indexCapacity)")
            throw ShapEMeshAdapterError.capacityExceeded
        }

        // ── Write buffers ────────────────────────────────────────────────
        lowLevelMesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBuffer in
            let vertices = rawBuffer.bindMemory(to: ShapEVertex.self)
            for i in 0..<positions.count {
                let uv = uvs?[i] ?? SIMD2<Float>(0, 0)
                vertices[i] = ShapEVertex(position: positions[i], uv: uv)
            }
        }

        lowLevelMesh.withUnsafeMutableIndices { rawIndices in
            let indicesBound = rawIndices.bindMemory(to: UInt32.self)
            for i in 0..<indices.count {
                indicesBound[i] = indices[i]
            }
        }

        var minP = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxP = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        for p in positions {
            minP = simd_min(minP, p)
            maxP = simd_max(maxP, p)
        }

        let bounds = BoundingBox(min: minP, max: maxP)
        let part = LowLevelMesh.Part(
            indexOffset: 0,
            indexCount: indices.count,
            topology: .triangle,
            materialIndex: 0,
            bounds: bounds
        )
        lowLevelMesh.parts.replaceAll([part])

        return textureResource
    }
}

public struct ShapEVertex {
    public var position: SIMD3<Float>
    public var uv: SIMD2<Float>

    public init(position: SIMD3<Float>, uv: SIMD2<Float>) {
        self.position = position
        self.uv = uv
    }
}
#endif
