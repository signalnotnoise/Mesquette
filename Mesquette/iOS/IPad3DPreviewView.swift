// iPadOS/IPad3DPreviewView.swift
// Mesquette — iOS / iPadOS only

#if os(iOS)
import SwiftUI
import UIKit
import SceneKit
import ShapERuntime

// MARK: - NodeTransform snapshot

private struct NodeTransform {
    let position:    SCNVector3
    let eulerAngles: SCNVector3
}

private struct PreviewMeshStamp: Equatable {
    var vertexCount: Int
    var faceCount: Int
    var minCorner: [Float]
    var maxCorner: [Float]

    init(_ mesh: MeshResult) {
        vertexCount = mesh.vertices.elementCount
        faceCount = mesh.faces.elementCount
        minCorner = mesh.bbox.minCorner
        maxCorner = mesh.bbox.maxCorner
    }
}

private struct AppliedTablePose: Equatable {
    var x: Float
    var y: Float
    var z: Float
    var scale: Float
    var yaw: Float
}

// MARK: - View

struct IPad3DPreviewView: UIViewRepresentable {

    let records:      [GenerationRecord]
    let isLocked:     Bool
    let dragVertical: Bool   // true = Y axis, false = XZ plane
    let resetTrigger: Int
    var shadingMode:  AppModel.ShadingMode = .smooth

    @Environment(\.colorScheme) private var colorScheme

    private var bgColor: UIColor {
        colorScheme == .dark
            ? UIColor(white: 0.08, alpha: 1)
            : UIColor(white: 0.92, alpha: 1)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene               = makeBaseScene()
        view.pointOfView = view.scene?.rootNode.childNode(withName: "studio-camera", recursively: true)
        view.allowsCameraControl = !isLocked
        view.defaultCameraController.minimumVerticalAngle = -8
        view.defaultCameraController.maximumVerticalAngle = 89
        view.defaultCameraController.target = SCNVector3(0, 0.12, 0)
        view.autoenablesDefaultLighting = false
        view.antialiasingMode    = .multisampling4X
        view.rendersContinuously = false
        view.backgroundColor     = bgColor
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        view.backgroundColor     = bgColor
        view.allowsCameraControl = !isLocked
        context.coordinator.isLocked = isLocked

        if context.coordinator.lastResetTrigger != resetTrigger {
            context.coordinator.lastResetTrigger = resetTrigger
            animateResetCamera(view)
        }

        if context.coordinator.lastShadingMode != shadingMode {
            context.coordinator.lastShadingMode = shadingMode
            for node in context.coordinator.addedNodes.values {
                SceneKitStudio.applyShadingMode(shadingMode, to: node)
            }
        }

        guard let scene = view.scene else { return }

        // ── Only add NEW nodes; never remove existing ones ──────────────
        let recordsWithMesh = records.filter { $0.latestMesh != nil }
        var addedNew = false

        for (i, record) in recordsWithMesh.enumerated() {
            guard let mesh = record.latestMesh,
                  let geometry = buildGeometry(from: mesh) else { continue }

            let x = record.offsetX ?? Float(i) * 0.7
            let y = record.offsetY ?? 0
            let z = record.offsetZ ?? 0
            let scale = record.placementScale ?? 1
            let stamp = PreviewMeshStamp(mesh)
            let pose = AppliedTablePose(x: x, y: y, z: z, scale: scale, yaw: 0)
            if let existingNode = context.coordinator.addedNodes[record.id] {
                let meshChanged = context.coordinator.lastMeshStamp[record.id] != stamp
                if meshChanged {
                    SceneKitStudio.replaceGeometry(existingNode, with: geometry)
                    context.coordinator.lastMeshStamp[record.id] = stamp
                }
                if record.setID != nil, meshChanged || context.coordinator.lastTablePose[record.id] != pose {
                    SceneKitStudio.applyTablePose(
                        existingNode,
                        x: x,
                        y: y,
                        z: z,
                        scale: scale
                    )
                    context.coordinator.lastTablePose[record.id] = pose
                }
            } else {
                let node = SCNNode(geometry: geometry)
                node.name = "gen"
                SceneKitStudio.plant(
                    node,
                    x: x,
                    y: y,
                    z: z,
                    scale: scale
                )
                scene.rootNode.addChildNode(node)
                context.coordinator.addedNodes[record.id] = node
                context.coordinator.lastMeshStamp[record.id] = stamp
                if record.setID != nil {
                    context.coordinator.lastTablePose[record.id] = pose
                }
                addedNew = true
            }
        }

        if addedNew {
            SceneKitStudio.frame(view, nodes: Array(context.coordinator.addedNodes.values))
        }
    }

    // MARK: Camera reset

    private func animateResetCamera(_ view: SCNView) {
        SceneKitStudio.apply(.home, to: view, duration: 0.65)
    }

    // MARK: Base scene

    private func makeBaseScene() -> SCNScene {
        let scene = SCNScene()
        SceneKitStudio.install(in: scene)
        return scene
    }

    // MARK: Geometry builder

    private func buildGeometry(from mesh: MeshResult) -> SCNGeometry? {
        guard mesh.vertices.elementCount % 3 == 0 else { return nil }
        let vertexCount = mesh.vertices.elementCount / 3

        let posSource = SCNGeometrySource(
            data: mesh.vertices.data, semantic: .vertex,
            vectorCount: vertexCount, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: 4,
            dataOffset: 0, dataStride: 12)

        let idxData: Data
        let indexCount: Int
        if mesh.faces.dataType == .int32 {
            idxData = mesh.faces.data
            indexCount = mesh.faces.elementCount
        } else if mesh.faces.dataType == .int64, let raw = try? mesh.faces.int64Values() {
            let idx32 = raw.map { Int32($0) }
            idxData = idx32.withUnsafeBytes { Data($0) }
            indexCount = idx32.count
        } else {
            return nil
        }
        
        guard indexCount > 0 else { return nil }
        
        let element = SCNGeometryElement(data: idxData, primitiveType: .triangles,
                                         primitiveCount: indexCount / 3, bytesPerIndex: 4)

        var sources: [SCNGeometrySource] = [posSource]
        var hasColors = false
        if let ch = mesh.vertexChannels,
           let rgbaTensor = ch["RGBA"],
           rgbaTensor.elementCount == vertexCount * 4 {
            let colSource = SCNGeometrySource(data: rgbaTensor.data, semantic: .color,
                                              vectorCount: vertexCount, usesFloatComponents: true,
                                              componentsPerVector: 4, bytesPerComponent: 4,
                                              dataOffset: 0, dataStride: 16)
            sources.append(colSource)
            hasColors = true
        }

        let geometry  = SCNGeometry(sources: sources, elements: [element])
        let mat       = SCNMaterial()
        mat.isDoubleSided = true
        mat.lightingModel = .phong
        mat.locksAmbientWithDiffuse = true
        if shadingMode == .flat {
            mat.shaderModifiers = [.surface: SceneKitStudio.flatShaderModifier]
        }
        mat.fillMode = (shadingMode == .wireframe ? .lines : .fill)
        if !hasColors { mat.diffuse.contents = UIColor(white: 0.78, alpha: 1) }
        geometry.materials = [mat]
        return geometry
    }
}

// MARK: - Coordinator

extension IPad3DPreviewView {

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        weak var scnView: SCNView?
        var isLocked:         Bool = false
        var lastResetTrigger: Int  = 0
        var lastShadingMode:  AppModel.ShadingMode = .smooth

        var addedNodes: [UUID: SCNNode] = [:]
        var lastMeshStamp: [UUID: PreviewMeshStamp] = [:]
        var lastTablePose: [UUID: AppliedTablePose] = [:]

        private var undoStacks: [ObjectIdentifier: [NodeTransform]] = [:]
        private let undoManager = UndoManager()

        // MARK: Drag state
        private var draggedNode:      SCNNode?
        private var nodeDepth:        CGFloat = 0
        private var beforeDrag:       NodeTransform?

        // MARK: Rotate state
        private var rotatingNode:      SCNNode?
        private var rotateStartAngleY: CGFloat = 0
        private var rotateStartAngleX: CGFloat = 0
        private var rotateStartX:      CGFloat = 0
        private var rotateStartY:      CGFloat = 0
        private var beforeRotate:      NodeTransform?

        // MARK: Setup

        func attach(to view: SCNView) {
            scnView = view

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(didEnterBackground),
                name: UIApplication.didEnterBackgroundNotification,
                object: nil
            )

            // 1-finger pan to translate
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            view.addGestureRecognizer(pan)

            // 2-finger pan to rotate
            let rot = UIPanGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
            rot.minimumNumberOfTouches = 2
            rot.maximumNumberOfTouches = 2
            rot.delegate = self
            view.addGestureRecognizer(rot)
            
            // Double tap to delete
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            view.addGestureRecognizer(doubleTap)
        }

        @objc private func didEnterBackground() {
            scnView?.isPlaying = false
        }

        // MARK: - UIGestureRecognizerDelegate

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Let the pan and rotate work cleanly together if needed, but they are mutually exclusive on touches counts
            return true
        }

        // MARK: - Hit helper

        private func findGenNode(at pt: CGPoint, in view: SCNView) -> SCNNode? {
            let hits = view.hitTest(pt, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue
            ])
            guard let hit = hits.first else { return nil }
            var node: SCNNode? = hit.node
            while node != nil && node?.name != "gen" { node = node?.parent }
            return node
        }

        // MARK: - Undo helpers

        private func snapshot(_ node: SCNNode) -> NodeTransform {
            NodeTransform(position: node.position, eulerAngles: node.eulerAngles)
        }

        private func registerUndo(node: SCNNode, before: NodeTransform, actionName: String) {
            let key = ObjectIdentifier(node)
            undoStacks[key, default: []].append(before)

            undoManager.registerUndo(withTarget: self) { [weak node] _ in
                guard let node else { return }
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.2
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
                node.position    = before.position
                node.eulerAngles = before.eulerAngles
                SCNTransaction.commit()
            }
            undoManager.setActionName(actionName)
        }

        // MARK: - Left-drag: Move freely

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard isLocked, let view = scnView else { return }
            let pt = gesture.location(in: view)

            switch gesture.state {
            case .began:
                draggedNode = findGenNode(at: pt, in: view)
                guard let n = draggedNode else { return }
                beforeDrag = snapshot(n)

                let proj         = view.projectPoint(n.worldPosition)
                nodeDepth        = CGFloat(proj.z)

            case .changed:
                guard let node = draggedNode else { return }
                let wp = view.unprojectPoint(SCNVector3(Float(pt.x), Float(pt.y), Float(nodeDepth)))
                node.position = wp

            case .ended:
                if let node = draggedNode, let before = beforeDrag {
                    registerUndo(node: node, before: before, actionName: "Move Model")
                }
                draggedNode = nil; beforeDrag = nil

            case .cancelled, .failed:
                if let node = draggedNode, let before = beforeDrag {
                    node.position    = before.position
                    node.eulerAngles = before.eulerAngles
                }
                draggedNode = nil; beforeDrag = nil

            default: break
            }
        }

        // MARK: - Double-tap: Delete

        @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard isLocked, let view = scnView else { return }
            let pt = gesture.location(in: view)
            if let node = findGenNode(at: pt, in: view) {
                let parent = node.parent
                let transform = snapshot(node)
                
                undoManager.registerUndo(withTarget: self) { _ in
                    parent?.addChildNode(node)
                    node.position = transform.position
                    node.eulerAngles = transform.eulerAngles
                }
                undoManager.setActionName("Delete Model")
                
                node.removeFromParentNode()
            }
        }

        // MARK: - Two-finger drag: rotate X + Y

        @objc private func handleRotate(_ gesture: UIPanGestureRecognizer) {
            guard isLocked, let view = scnView else { return }
            let pt = gesture.location(in: view)

            switch gesture.state {
            case .began:
                rotatingNode      = findGenNode(at: pt, in: view)
                guard let n = rotatingNode else { return }
                beforeRotate      = snapshot(n)

                rotateStartAngleY = CGFloat(n.eulerAngles.y)
                rotateStartAngleX = CGFloat(n.eulerAngles.x)
                rotateStartX      = pt.x
                rotateStartY      = pt.y

            case .changed:
                guard let node = rotatingNode else { return }
                let s: CGFloat = .pi / 540   // 540 screen-px = 180°
                node.eulerAngles.y = Float(rotateStartAngleY + (pt.x - rotateStartX) * s)
                node.eulerAngles.x = Float(rotateStartAngleX + (pt.y - rotateStartY) * s)

            case .ended:
                if let node = rotatingNode, let before = beforeRotate {
                    registerUndo(node: node, before: before, actionName: "Rotate Model")
                }
                rotatingNode = nil; beforeRotate = nil

            case .cancelled, .failed:
                if let node = rotatingNode, let before = beforeRotate {
                    node.position    = before.position
                    node.eulerAngles = before.eulerAngles
                }
                rotatingNode = nil; beforeRotate = nil

            default: break
            }
        }
    }
}
#endif
