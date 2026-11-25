// macOS/Mac3DPreviewView.swift
// Mesquette — macOS only

#if os(macOS)
import SwiftUI
import SceneKit
import simd
import ShapERuntime

// MARK: - NodeTransform snapshot

struct NodeTransform {
    let position:    SCNVector3
    let eulerAngles: SCNVector3
}

struct PreviewMeshStamp: Equatable {
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

/// Owns mouse/scroll/WASD. SceneKit `allowsCameraControl` stays off so we
/// don't fight kSCNFreeViewCameraName or layout recursion.
final class StudioSCNView: SCNView {
    weak var cameraInput: Mac3DPreviewView.Coordinator?
    var blockCameraDrag = false

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        allowsCameraControl = false
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        cameraInput?.handleCameraMouseDown(event)
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if !blockCameraDrag { cameraInput?.handleCameraMouseDragged(event) }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        cameraInput?.handleCameraMouseUp(event)
        super.mouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        cameraInput?.handleCameraMouseDown(event)
        super.rightMouseDown(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        if !blockCameraDrag { cameraInput?.handleCameraMouseDragged(event) }
        super.rightMouseDragged(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        cameraInput?.handleCameraMouseUp(event)
        super.rightMouseUp(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        cameraInput?.handleCameraMouseDown(event)
        super.otherMouseDown(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        if !blockCameraDrag { cameraInput?.handleCameraMouseDragged(event) }
        super.otherMouseDragged(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        cameraInput?.handleCameraMouseUp(event)
        super.otherMouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) { return }
        if blockCameraDrag { return }
        cameraInput?.handleCameraScroll(event)
    }

    override func keyDown(with event: NSEvent) {
        if cameraInput?.handleCameraKeyDown(event) == true { return }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if cameraInput?.handleCameraKeyUp(event) == true { return }
        super.keyUp(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        cameraInput?.handleCameraFlagsChanged(event)
        super.flagsChanged(with: event)
    }
}

struct AppliedTablePose: Equatable {
    var x: Float
    var y: Float
    var z: Float
    var scale: Float
    var yaw: Float
}

// MARK: - View

struct Mac3DPreviewView: NSViewRepresentable {

    let records:      [GenerationRecord]
    let isLocked:     Bool
    let dragVertical: Bool   // true = Y axis, false = XZ plane
    let resetTrigger: Int
    var cameraView: StudioCameraRig.View = .orbit
    var pins: [PlacementPin] = []
    var isPinning: Bool = false
    var onDropPin: ((Float, Float, Float) -> Void)?
    var onRemovePin: ((UUID) -> Void)?
    var onMovePin: ((UUID, Float, Float, Float) -> Void)?
    var onRetryPin: ((UUID) -> Void)?
    var shadingMode: AppModel.ShadingMode = .smooth

    @Environment(\.colorScheme) private var colorScheme

    private var bgColor: NSColor {
        colorScheme == .dark
            ? NSColor(calibratedWhite: 0.08, alpha: 1)
            : NSColor(calibratedWhite: 0.92, alpha: 1)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: NSViewRepresentable

    func makeNSView(context: Context) -> SCNView {
        let view = StudioSCNView()
        view.scene               = makeBaseScene()
        view.pointOfView = view.scene?.rootNode.childNode(withName: "studio-camera", recursively: true)
        view.allowsCameraControl = false
        context.coordinator.rig = .home
        view.autoenablesDefaultLighting = false
        view.antialiasingMode    = .multisampling4X
        view.backgroundColor     = bgColor
        context.coordinator.attach(to: view)
        PlacementDebug.log("makeNSView scene=\(view.scene != nil) pov=\(view.pointOfView?.name ?? "nil")")
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        let c = context.coordinator
        c.isLocked = isLocked
        c.isPinning = isPinning
        c.onDropPin = onDropPin
        c.onRemovePin = onRemovePin
        c.onMovePin = onMovePin
        c.onRetryPin = onRetryPin
        c.pending = self
        c.scheduleApply()
    }

    /// SceneKit / SCNText must not run inside SwiftUI's layout pass — AppKit
    /// logs layoutSubtreeIfNeeded recursion if they do.
    func applyScene(to view: SCNView, coordinator: Coordinator) {
        view.backgroundColor = bgColor
        if let studio = view as? StudioSCNView {
            studio.cameraInput = coordinator
            studio.blockCameraDrag = isLocked || coordinator.draggedPinID != nil
        }

        if coordinator.lastCameraView != cameraView {
            coordinator.lastCameraView = cameraView
            if cameraView != .walk { coordinator.cancelWalkInput() }
            coordinator.rig.adoptView(cameraView)
            coordinator.applyRig(to: view, duration: 0.35)
            PlacementDebug.log("camera view=\(cameraView.rawValue) pitch=\(coordinator.rig.pitch * 180 / .pi)")
        }

        if coordinator.lastResetTrigger != resetTrigger {
            coordinator.lastResetTrigger = resetTrigger
            coordinator.frameCamera(in: view, duration: 0.65)
        }

        if coordinator.lastShadingMode != shadingMode {
            coordinator.lastShadingMode = shadingMode
            for node in coordinator.addedNodes.values {
                SceneKitStudio.applyShadingMode(shadingMode, to: node)
            }
        }

        guard let scene = view.scene else {
            PlacementDebug.log("applyScene aborted — view.scene is nil")
            return
        }

        let recordsWithMesh = records.filter { $0.latestMesh != nil }
        let signature = sceneSignature(recordsWithMesh: recordsWithMesh, pins: pins)
        if signature == coordinator.lastSceneSignature {
            return
        }
        coordinator.lastSceneSignature = signature
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
            let directed = record.setID != nil || record.offsetX != nil
            if let existingNode = coordinator.addedNodes[record.id] {
                let meshChanged = coordinator.lastMeshStamp[record.id] != stamp
                if meshChanged {
                    SceneKitStudio.replaceGeometry(existingNode, with: geometry)
                    coordinator.lastMeshStamp[record.id] = stamp
                }
                let poseChanged = coordinator.lastTablePose[record.id] != pose
                let scaleDrift = abs(Float(existingNode.scale.x) - scale) > 0.001
                if directed, meshChanged || poseChanged || scaleDrift {
                    PlacementDebug.log(
                        "update \(record.prompt.prefix(32)) meshChanged=\(meshChanged) poseChanged=\(poseChanged) scaleDrift=\(scaleDrift) recScale=\(scale)"
                    )
                    SceneKitStudio.applyTablePose(
                        existingNode,
                        x: x,
                        y: y,
                        z: z,
                        scale: scale
                    )
                    coordinator.lastTablePose[record.id] = pose
                }
            } else {
                PlacementDebug.log(
                    "plant \(record.prompt.prefix(32)) scale=\(scale) xyz=(\(x),\(y),\(z)) set=\(record.setID != nil)"
                )
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
                coordinator.addedNodes[record.id] = node
                coordinator.lastMeshStamp[record.id] = stamp
                coordinator.lastTablePose[record.id] = pose
                addedNew = true
            }
        }

        if addedNew {
            coordinator.frameCamera(in: view, duration: 0.45)
        }

        coordinator.filledPinIDs = Set(pins.compactMap { pinFill($0) == .filled ? $0.id : nil })
        coordinator.occupiedPinIDs = Set(pins.compactMap { pinFill($0) != .empty ? $0.id : nil })
        syncPinMarkers(in: scene, pins: pins, dragging: coordinator.draggedPinID)
    }

    private func sceneSignature(recordsWithMesh: [GenerationRecord], pins: [PlacementPin]) -> Int {
        var hasher = Hasher()
        hasher.combine(resetTrigger)
        hasher.combine(shadingMode)
        hasher.combine(isLocked)
        hasher.combine(isPinning)
        for pin in pins {
            hasher.combine(pin.id)
            hasher.combine(pin.x)
            hasher.combine(pin.y)
            hasher.combine(pin.z)
            hasher.combine(pin.recordID)
            hasher.combine(pinFill(pin).rawValue)
        }
        for record in recordsWithMesh {
            hasher.combine(record.id)
            hasher.combine(record.placementScale)
            hasher.combine(record.rotationY)
            hasher.combine(record.offsetX)
            hasher.combine(record.offsetY)
            hasher.combine(record.offsetZ)
            if let mesh = record.latestMesh {
                hasher.combine(mesh.vertices.elementCount)
                hasher.combine(mesh.faces.elementCount)
            }
        }
        return hasher.finalize()
    }

    private func syncPinMarkers(in scene: SCNScene, pins: [PlacementPin], dragging: UUID?) {
        let groupName = "placement-pins"
        let group = scene.rootNode.childNode(withName: groupName, recursively: false)
            ?? {
                let node = SCNNode()
                node.name = groupName
                scene.rootNode.addChildNode(node)
                return node
            }()

        var existingByPinID: [UUID: SCNNode] = [:]
        for child in group.childNodes {
            if let raw = child.value(forKey: "pinID") as? String, let id = UUID(uuidString: raw) {
                existingByPinID[id] = child
            }
        }

        let pinIDs = Set(pins.map(\.id))
        for (id, node) in existingByPinID where !pinIDs.contains(id) {
            node.removeFromParentNode()
        }

        for (i, pin) in pins.enumerated() {
            if pin.id == dragging { continue }
            let fill = pinFill(pin)
            if let existing = existingByPinID[pin.id] {
                Self.applyPinPose(existing, pin: pin, index: i, fill: fill)
            } else {
                group.addChildNode(Self.makePinMarker(pin, index: i, fill: fill))
            }
        }
    }

    private func pinFill(_ pin: PlacementPin) -> PinFillState {
        guard let rid = pin.recordID,
              let rec = records.first(where: { $0.id == rid }) else { return .empty }
        switch rec.status {
        case .generating:
            return .busy
        case .completed where rec.latestMesh != nil:
            return .filled
        default:
            return .empty
        }
    }

    private static func pinColor(_ fill: PinFillState) -> NSColor {
        switch fill {
        case .empty: return .systemOrange
        case .busy: return .systemYellow
        case .filled: return .systemTeal
        }
    }

    private static func makePinMarker(_ pin: PlacementPin, index: Int, fill: PinFillState) -> SCNNode {
        let color = pinColor(fill)
        let stem = SCNCylinder(radius: 0.012, height: 0.08)
        stem.firstMaterial = {
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.lightingModel = .constant
            return m
        }()
        let stemNode = SCNNode(geometry: stem)
        stemNode.position = SCNVector3(0, 0.04, 0)

        let head = SCNSphere(radius: 0.035)
        head.firstMaterial = stem.firstMaterial
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 0.09, 0)

        let root = SCNNode()
        root.name = "placement-pin"
        root.setValue(pin.id.uuidString, forKey: "pinID")
        root.addChildNode(stemNode)
        root.addChildNode(headNode)
        let plumb = SCNNode()
        plumb.name = "pin-plumb"
        root.addChildNode(plumb)

        let label = SCNText(string: "\(index + 1)", extrusionDepth: 0)
        label.font = NSFont.systemFont(ofSize: 1.2, weight: .bold)
        label.flatness = 0.2
        label.firstMaterial = {
            let m = SCNMaterial()
            m.diffuse.contents = NSColor.white
            m.lightingModel = .constant
            return m
        }()
        let labelNode = SCNNode(geometry: label)
        labelNode.name = "placement-pin-label"
        // Fixed offset — SCNText.boundingBox uses AppKit text layout and will
        // call layoutSubtreeIfNeeded if we query it during a SwiftUI layout pass.
        labelNode.position = SCNVector3(-0.03, 0.13, 0)
        labelNode.scale = SCNVector3(0.08, 0.08, 0.08)
        root.addChildNode(labelNode)
        applyPinPose(root, pin: pin, index: index, fill: fill)
        return root
    }

    private static func applyPinPose(_ node: SCNNode, pin: PlacementPin, index: Int, fill: PinFillState) {
        node.position = SCNVector3(CGFloat(pin.x), CGFloat(pin.y), CGFloat(pin.z))
        if let labelNode = node.childNode(withName: "placement-pin-label", recursively: false),
           let textGeom = labelNode.geometry as? SCNText {
            let label = "\(index + 1)"
            if textGeom.string as? String != label {
                textGeom.string = label
            }
        }
        let lastFill = node.value(forKey: "pinFill") as? String
        if lastFill != fill.rawValue {
            node.setValue(fill.rawValue, forKey: "pinFill")
            let color = pinColor(fill)
            for child in node.childNodes where child.name != "pin-plumb" && child.name != "placement-pin-label" {
                child.geometry?.firstMaterial?.diffuse.contents = color
            }
        }
        guard let plumb = node.childNode(withName: "pin-plumb", recursively: false) else { return }
        let height = pin.y
        let last = plumb.value(forKey: "plumbHeight") as? CGFloat
        if last == CGFloat(height) { return }
        plumb.setValue(CGFloat(height), forKey: "plumbHeight")
        plumb.childNodes.forEach { $0.removeFromParentNode() }
        guard height > 0.04 else { return }
        let line = SCNCylinder(radius: 0.004, height: CGFloat(height))
        line.firstMaterial = {
            let m = SCNMaterial()
            m.diffuse.contents = NSColor.systemOrange.withAlphaComponent(0.45)
            m.lightingModel = .constant
            return m
        }()
        let lineNode = SCNNode(geometry: line)
        lineNode.position = SCNVector3(0, CGFloat(-height / 2), 0)
        plumb.addChildNode(lineNode)
    }

    // MARK: Base scene

    private func makeBaseScene() -> SCNScene {
        let scene = SCNScene()
        SceneKitStudio.install(in: scene)
        return scene
    }

    // MARK: Geometry builder

    private func buildGeometry(from mesh: MeshResult) -> SCNGeometry? {
        SceneKitStudio.makeGeometry(from: mesh, shadingMode: shadingMode)
    }
}

#endif
