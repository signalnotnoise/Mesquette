// SceneKitStudio.swift
// Mesquette — Shared preview lighting + camera framing (macOS + iOS).

#if os(macOS) || os(iOS)
import SceneKit
import simd
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum SceneKitStudio {

    static func install(in scene: SCNScene) {
        let floor = SCNPlane(width: 12, height: 12)
        let floorMat = SCNMaterial()
#if os(macOS)
        floorMat.diffuse.contents = NSColor(white: 0.28, alpha: 1)
#else
        floorMat.diffuse.contents = UIColor(white: 0.28, alpha: 1)
#endif
        floorMat.lightingModel = .phong
        floorMat.isDoubleSided = true
        floor.materials = [floorMat]
        let floorNode = SCNNode(geometry: floor)
        floorNode.name = "studio-floor"
        floorNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        floorNode.position = SCNVector3(0, -0.01, 0)
        scene.rootNode.addChildNode(floorNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 650
        let ambNode = SCNNode()
        ambNode.light = ambient
        scene.rootNode.addChildNode(ambNode)

        let key = SCNLight()
        key.type = .directional
        key.intensity = 1100
        key.castsShadow = true
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 420
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-Float.pi / 6, -Float.pi / 3, 0)
        scene.rootNode.addChildNode(fillNode)

        let cam = SCNCamera()
        cam.zNear = 0.04
        cam.zFar = 250
        cam.fieldOfView = 42
        let camNode = SCNNode()
        camNode.name = "studio-camera"
        camNode.camera = cam
        scene.rootNode.addChildNode(camNode)
        apply(StudioCameraRig.home, to: camNode, duration: 0)
    }

    /// Put the mesh at the pin. Floor pins snap the lowest vertex to y; lifted pins
    /// hover on the bbox center. Shap-E rotation is left alone — the user rotates.
    /// Geometry lives on a child named `sit-mesh` so later updates don't stomp
    /// the wrapper's pivot / user rotation.
    static func plant(
        _ node: SCNNode,
        x: Float,
        y: Float = 0,
        z: Float,
        scale: Float
    ) {
        if let geometry = node.geometry {
            let meshNode = SCNNode(geometry: geometry)
            meshNode.name = "sit-mesh"
            node.geometry = nil
            node.addChildNode(meshNode)
        }
        applyTablePose(node, x: x, y: y, z: z, scale: scale)
    }

    /// Scale and place on the table. Does not write euler — lock-drag rotation stays.
    static func applyTablePose(
        _ node: SCNNode,
        x: Float,
        y: Float = 0,
        z: Float,
        scale: Float
    ) {
        node.scale = SCNVector3(scale, scale, scale)
        node.setValue(y >= PlacementPin.airborneThreshold, forKey: attachCenterKey)
        applyPivot(to: node)
        node.position = SCNVector3(x, y, z)
        PlacementDebug.log(
            String(
                format: "plant scale=%.3f pos=(%.2f, %.2f, %.2f) nodeScale=%.3f",
                scale,
                x, y, z,
                Float(node.scale.x)
            )
        )
    }

    static let flatShaderModifier = """
    #pragma body
    _surface.normal = normalize(cross(dfdx(_surface.position), dfdy(_surface.position)));
    """

    /// Set flat vs smooth vs wireframe shading on all materials of this node and children.
    static func applyShadingMode(_ mode: AppModel.ShadingMode, to node: SCNNode) {
        let targets = [node] + node.childNodes
        for target in targets {
            if let geometry = target.geometry {
                for mat in geometry.materials {
                    if mode == .flat {
                        mat.shaderModifiers = [.surface: flatShaderModifier]
                    } else {
                        mat.shaderModifiers = nil
                    }
                    mat.fillMode = (mode == .wireframe ? .lines : .fill)
                }
            }
        }
    }

    /// Swap the mesh and refresh the gravity pivot. Wrapper position, rotation, and scale stay.
    static func replaceGeometry(_ wrapper: SCNNode, with geometry: SCNGeometry) {
        if let inner = wrapper.childNode(withName: "sit-mesh", recursively: false) {
            inner.geometry = geometry
            inner.eulerAngles = SCNVector3(0, 0, 0)
        } else {
            let inner = SCNNode(geometry: geometry)
            inner.name = "sit-mesh"
            wrapper.geometry = nil
            wrapper.addChildNode(inner)
        }
        applyPivot(to: wrapper)
    }

    private static let attachCenterKey = "mesquette.attachCenter"

    /// XZ center on the pin. Floor: lowest vertex. Airborne: bbox center.
    private static func applyPivot(to wrapper: SCNNode) {
        guard let meshNode = wrapper.childNode(withName: "sit-mesh", recursively: false) else {
            return
        }
        meshNode.eulerAngles = SCNVector3(0, 0, 0)
        let (minVec, maxVec) = wrapper.boundingBox
        let cx = (minVec.x + maxVec.x) * 0.5
        let cz = (minVec.z + maxVec.z) * 0.5
        let attachCenter = wrapper.value(forKey: attachCenterKey) as? Bool ?? false
        let py = attachCenter ? (minVec.y + maxVec.y) * 0.5 : minVec.y
        wrapper.pivot = SCNMatrix4MakeTranslation(cx, py, cz)
    }

    static func cameraInScene(_ view: SCNView) -> SCNNode? {
        if let pov = view.pointOfView, pov.parent != nil { return pov }
        return view.scene?.rootNode.childNode(withName: "studio-camera", recursively: true)
    }

    static func worldBounds(of nodes: [SCNNode]) -> (center: SIMD3<Float>, radius: Float)? {
        guard !nodes.isEmpty else { return nil }

        var minX = Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude

        for node in nodes {
            let (localMin, localMax) = node.boundingBox
            let corners = [
                SCNVector3(localMin.x, localMin.y, localMin.z),
                SCNVector3(localMin.x, localMin.y, localMax.z),
                SCNVector3(localMin.x, localMax.y, localMin.z),
                SCNVector3(localMin.x, localMax.y, localMax.z),
                SCNVector3(localMax.x, localMin.y, localMin.z),
                SCNVector3(localMax.x, localMin.y, localMax.z),
                SCNVector3(localMax.x, localMax.y, localMin.z),
                SCNVector3(localMax.x, localMax.y, localMax.z)
            ]
            for corner in corners {
                let world = node.convertPosition(corner, to: nil)
                minX = min(minX, Float(world.x))
                minY = min(minY, Float(world.y))
                minZ = min(minZ, Float(world.z))
                maxX = max(maxX, Float(world.x))
                maxY = max(maxY, Float(world.y))
                maxZ = max(maxZ, Float(world.z))
            }
        }

        let center = SIMD3((minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5)
        let radius = max(max(maxX - minX, maxY - minY), maxZ - minZ) * 0.5
        return (center, radius)
    }

    static func apply(_ rig: StudioCameraRig, to view: SCNView, duration: TimeInterval) {
        guard let pov = cameraInScene(view) else {
            PlacementDebug.log("camera apply skipped — not in scene (pov=\(view.pointOfView?.name ?? "nil"))")
            return
        }
        apply(rig, to: pov, duration: duration)
        if view.allowsCameraControl {
            let t = rig.target
            view.defaultCameraController.target = scn(t)
            view.defaultCameraController.clearRoll()
            view.defaultCameraController.minimumVerticalAngle = -8
            view.defaultCameraController.maximumVerticalAngle = 89
        }
    }

    static func apply(_ rig: StudioCameraRig, to node: SCNNode, duration: TimeInterval) {
        let p = rig.position
        let t = rig.target
        let pose = {
            node.position = scn(p)
            node.look(at: scn(t), up: scn(SIMD3(0, 1, 0)), localFront: scn(SIMD3(0, 0, -1)))
        }
        if duration > 0 {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration
            pose()
            SCNTransaction.commit()
        } else {
            pose()
        }
    }

    static func frame(_ view: SCNView, nodes: [SCNNode], cameraView: StudioCameraRig.View = .orbit) {
        guard let bounds = worldBounds(of: nodes) else { return }
        var rig = StudioCameraRig.home
        rig.view = cameraView
        rig.frame(center: bounds.center, radius: bounds.radius)
        apply(rig, to: view, duration: 0.45)
    }

    private static func scn(_ v: SIMD3<Float>) -> SCNVector3 {
#if os(macOS)
        SCNVector3(CGFloat(v.x), CGFloat(v.y), CGFloat(v.z))
#else
        SCNVector3(v.x, v.y, v.z)
#endif
    }
}
#endif
