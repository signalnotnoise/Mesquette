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

/// Owns mouse/scroll/WASD. SceneKit `allowsCameraControl` stays off so we
/// don't fight kSCNFreeViewCameraName or layout recursion.
private final class StudioSCNView: SCNView {
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

private struct AppliedTablePose: Equatable {
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
    fileprivate func applyScene(to view: SCNView, coordinator: Coordinator) {
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

// MARK: - Coordinator

extension Mac3DPreviewView {

    final class Coordinator: NSObject, NSGestureRecognizerDelegate {

        weak var scnView: SCNView?
        var isLocked:         Bool = false
        var isPinning:        Bool = false
        var onDropPin: ((Float, Float, Float) -> Void)?
        var onRemovePin: ((UUID) -> Void)?
        var onMovePin: ((UUID, Float, Float, Float) -> Void)?
        var onRetryPin: ((UUID) -> Void)?
        var filledPinIDs: Set<UUID> = []
        var occupiedPinIDs: Set<UUID> = []
        var lastResetTrigger: Int  = 0
        var lastShadingMode:  AppModel.ShadingMode = .smooth
        var lastCameraView: StudioCameraRig.View = .orbit
        var rig = StudioCameraRig.home
        var pending: Mac3DPreviewView?
        private var applyScheduled = false
        fileprivate var cameraDidDrag = false
        private var cameraTracking: CameraTracking = .none
        private var lastMouse: NSPoint = .zero
        private var walkKeys = Set<UInt16>()
        private var walkTimer: Timer?
        private var walkSprinting = false

        private var draggedPinNode: SCNNode?
        fileprivate var draggedPinID: UUID?
        private var didDragPin: Bool = false
        private var liftingPin: Bool = false
        private var scrollMonitor: Any?
        private weak var panGesture: NSPanGestureRecognizer?

        /// Tracks which GenerationRecord IDs have been added to the scene.
        /// Prevents updateNSView from re-adding (and thus resetting) existing nodes.
        var addedNodes: [UUID: SCNNode] = [:]
        fileprivate var lastMeshStamp: [UUID: PreviewMeshStamp] = [:]
        fileprivate var lastTablePose: [UUID: AppliedTablePose] = [:]
        fileprivate var lastSceneSignature: Int?

        private let undoManager = UndoManager()
        private var keyMonitor: Any?

        // MARK: Drag state

        private var draggedNode:      SCNNode?
        private var nodeDepth:        CGFloat = 0
        private var beforeDrag:       NodeTransform?

        // MARK: Rotate state

        private var rotatingNode:      SCNNode?
        // Stored as CGFloat; cast to Float only when writing to SCNVector3
        private var rotateStartAngleY: CGFloat = 0
        private var rotateStartAngleX: CGFloat = 0
        private var rotateStartX:      CGFloat = 0
        private var rotateStartY:      CGFloat = 0
        private var beforeRotate:      NodeTransform?

        // MARK: Setup

        func scheduleApply() {
            guard !applyScheduled else { return }
            applyScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.applyScheduled = false
                guard let view = self.scnView, let owner = self.pending else {
                    PlacementDebug.log("apply skipped — view=\(self.scnView != nil) pending=\(self.pending != nil)")
                    return
                }
                owner.applyScene(to: view, coordinator: self)
            }
        }

        private enum CameraTracking {
            case none
            case tumble
            case pan
            case look
        }

        func attach(to view: SCNView) {
            scnView = view
            (view as? StudioSCNView)?.cameraInput = self

            let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.buttonMask = 0x1
            pan.delegate = self
            view.addGestureRecognizer(pan)
            panGesture = pan

            let rot = NSPanGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
            rot.buttonMask = 0x2
            view.addGestureRecognizer(rot)
            
            let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
            doubleClick.numberOfClicksRequired = 2
            view.addGestureRecognizer(doubleClick)

            let pinClick = NSClickGestureRecognizer(target: self, action: #selector(handlePinClick(_:)))
            pinClick.numberOfClicksRequired = 1
            view.addGestureRecognizer(pinClick)

            // ⌘Z  — undo last modification
            // ⌘⇧Z — redo
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.modifierFlags.contains(.command) else { return event }
                if event.characters == "z" && !event.modifierFlags.contains(.shift) {
                    self.undoManager.undo(); return nil
                }
                if event.characters == "z" && event.modifierFlags.contains(.shift) {
                    self.undoManager.redo(); return nil
                }
                return event
            }

            // Option-scroll over a pin lifts it. Plain scroll stays camera zoom.
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let view = self.scnView, event.window === view.window else { return event }
                guard event.modifierFlags.contains(.option) else { return event }
                let pt = view.convert(event.locationInWindow, from: nil)
                let hits = view.hitTest(pt, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
                guard let hit = hits.first, let pinNode = self.findPinRoot(from: hit.node),
                      let id = self.pinID(from: pinNode) else { return event }
                let delta = Float(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 0.004 : 0.04)
                let y = min(PlacementPin.maxHeight, max(0, Float(pinNode.position.y) + delta))
                pinNode.position.y = CGFloat(y)
                self.onMovePin?(id, Float(pinNode.position.x), y, Float(pinNode.position.z))
                return nil
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
            guard gestureRecognizer === panGesture, let view = scnView else { return true }
            let pt = gestureRecognizer.location(in: view)
            let hits = view.hitTest(pt, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
            if let hit = hits.first, findPinRoot(from: hit.node) != nil { return true }
            if isLocked, findGenNode(at: pt, in: view) != nil { return true }
            return false
        }

        func syncCameraControl(locked: Bool) {
            (scnView as? StudioSCNView)?.blockCameraDrag = locked || draggedPinID != nil
        }

        isolated deinit {
            walkTimer?.invalidate()
            if let m = keyMonitor { NSEvent.removeMonitor(m) }
            if let m = scrollMonitor { NSEvent.removeMonitor(m) }
        }

        func applyRig(to view: SCNView, duration: TimeInterval) {
            SceneKitStudio.apply(rig, to: view, duration: duration)
        }

        func frameCamera(in view: SCNView, duration: TimeInterval) {
            if let bounds = SceneKitStudio.worldBounds(of: Array(addedNodes.values)) {
                rig.frame(center: bounds.center, radius: bounds.radius)
            } else {
                let previous = rig.view
                rig = .home
                rig.view = previous
                rig.frame(center: SIMD3(0, 0.12, 0), radius: 0.55)
            }
            SceneKitStudio.apply(rig, to: view, duration: duration)
            PlacementDebug.log(
                String(
                    format: "camera frame view=%@ pitch=%.1f° dist=%.2f",
                    rig.view.rawValue,
                    rig.pitch * 180 / .pi,
                    rig.distance
                )
            )
        }

        func handleCameraMouseDown(_ event: NSEvent) {
            cameraDidDrag = false
            cameraTracking = .none
            lastMouse = event.locationInWindow
            guard !isLocked, draggedPinID == nil, let view = scnView else { return }
            let pt = view.convert(event.locationInWindow, from: nil)
            let hits = view.hitTest(pt, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
            if let hit = hits.first, findPinRoot(from: hit.node) != nil { return }

            let panButtons = event.type == .rightMouseDown || event.type == .otherMouseDown
            let panMods = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option)
            if panButtons || panMods {
                cameraTracking = .pan
            } else if rig.view == .walk {
                cameraTracking = .look
            } else {
                cameraTracking = .tumble
            }
        }

        func handleCameraMouseDragged(_ event: NSEvent) {
            guard cameraTracking != .none, let view = scnView else { return }
            let loc = event.locationInWindow
            let dx = Float(loc.x - lastMouse.x)
            let dy = Float(loc.y - lastMouse.y)
            lastMouse = loc
            if hypot(dx, dy) > 3 { cameraDidDrag = true }
            switch cameraTracking {
            case .none:
                return
            case .tumble:
                rig.orbit(dx: dx, dy: dy)
            case .look:
                rig.look(dx: dx, dy: dy)
            case .pan:
                rig.pan(dx: dx, dy: dy)
            }
            applyRig(to: view, duration: 0)
        }

        func handleCameraMouseUp(_: NSEvent) {
            cameraTracking = .none
        }

        func handleCameraScroll(_ event: NSEvent) {
            guard !isLocked, let view = scnView else { return }
            let line = event.hasPreciseScrollingDeltas ? Float(event.scrollingDeltaY) * 0.04 : Float(event.scrollingDeltaY)
            guard abs(line) > 0.0001 else { return }
            rig.dolly(scroll: line)
            applyRig(to: view, duration: 0)
        }

        @discardableResult
        func handleCameraKeyDown(_ event: NSEvent) -> Bool {
            guard rig.view == .walk, !isLocked else { return false }
            let code = event.keyCode
            guard Self.walkKeyCodes.contains(code) else { return false }
            walkKeys.insert(code)
            walkSprinting = event.modifierFlags.contains(.shift)
            startWalkTimerIfNeeded()
            return true
        }

        @discardableResult
        func handleCameraKeyUp(_ event: NSEvent) -> Bool {
            let code = event.keyCode
            guard walkKeys.contains(code) else { return false }
            walkKeys.remove(code)
            if walkKeys.isEmpty {
                walkTimer?.invalidate()
                walkTimer = nil
            }
            return true
        }

        func cancelWalkInput() {
            walkKeys.removeAll()
            walkTimer?.invalidate()
            walkTimer = nil
        }

        func handleCameraFlagsChanged(_ event: NSEvent) {
            walkSprinting = event.modifierFlags.contains(.shift)
        }

        private static let walkKeyCodes: Set<UInt16> = [13, 0, 1, 2, 12, 14, 49, 8]

        private func startWalkTimerIfNeeded() {
            guard walkTimer == nil else { return }
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                DispatchQueue.main.async { self?.tickWalk() }
            }
            RunLoop.main.add(timer, forMode: .common)
            walkTimer = timer
        }

        private func tickWalk() {
            guard rig.view == .walk, !isLocked, let view = scnView, !walkKeys.isEmpty else { return }
            let speed: Float = walkSprinting ? 0.09 : 0.035
            var forward: Float = 0
            var right: Float = 0
            var up: Float = 0
            if walkKeys.contains(13) { forward += speed }
            if walkKeys.contains(1) { forward -= speed }
            if walkKeys.contains(2) { right += speed }
            if walkKeys.contains(0) { right -= speed }
            if walkKeys.contains(12) || walkKeys.contains(49) { up += speed }
            if walkKeys.contains(14) || walkKeys.contains(8) { up -= speed }
            guard forward != 0 || right != 0 || up != 0 else { return }
            rig.walk(forward: forward, right: right, up: up)
            applyRig(to: view, duration: 0)
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
            let after = snapshot(node)
            undoManager.registerUndo(withTarget: self) { target in
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.2
                node.position    = before.position
                node.eulerAngles = before.eulerAngles
                SCNTransaction.commit()
                target.registerRedo(node: node, after: after, before: before, actionName: actionName)
            }
            undoManager.setActionName(actionName)
        }

        private func registerRedo(node: SCNNode, after: NodeTransform, before: NodeTransform, actionName: String) {
            undoManager.registerUndo(withTarget: self) { target in
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.2
                node.position    = after.position
                node.eulerAngles = after.eulerAngles
                SCNTransaction.commit()
                target.registerUndo(node: node, before: before, actionName: actionName)
            }
            undoManager.setActionName(actionName)
        }

        // MARK: - Pin raycasting & roots

        private func findPinRoot(from node: SCNNode) -> SCNNode? {
            var n: SCNNode? = node
            while let cur = n {
                if cur.name == "placement-pin" { return cur }
                n = cur.parent
            }
            return nil
        }

        private func floorPoint(at pt: CGPoint, in view: SCNView) -> (x: Float, z: Float)? {
            let hits = view.hitTest(pt, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            if let floorHit = hits.first(where: { $0.node.name == "studio-floor" }) {
                return (Float(floorHit.worldCoordinates.x), Float(floorHit.worldCoordinates.z))
            }
            let near = view.unprojectPoint(SCNVector3(pt.x, pt.y, 0))
            let far = view.unprojectPoint(SCNVector3(pt.x, pt.y, 1))
            let dy = far.y - near.y
            guard abs(dy) > 1e-4 else { return nil }
            let t = -near.y / dy
            let x = near.x + t * (far.x - near.x)
            let z = near.z + t * (far.z - near.z)
            return (Float(x), Float(z))
        }

        // MARK: - Left-drag: Move freely or drag pin

        @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard let view = scnView else { return }
            let pt = gesture.location(in: view)

            switch gesture.state {
            case .began:
                didDragPin = false
                liftingPin = false
                // Check if user clicked on a placement pin to move it
                let hits = view.hitTest(pt, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
                if let hit = hits.first, let pinNode = findPinRoot(from: hit.node), let id = pinID(from: pinNode) {
                    draggedPinNode = pinNode
                    draggedPinID = id
                    liftingPin = NSEvent.modifierFlags.contains(.option)
                    let proj = view.projectPoint(pinNode.worldPosition)
                    nodeDepth = CGFloat(proj.z)
                    syncCameraControl(locked: isLocked)
                    return
                }

                // If not grabbing a pin, only proceed if scene is locked for model editing
                guard isLocked else { return }
                draggedNode = findGenNode(at: pt, in: view)
                guard let n = draggedNode else { return }
                beforeDrag = snapshot(n)

                let proj         = view.projectPoint(n.worldPosition)
                nodeDepth        = CGFloat(proj.z)

            case .changed:
                if let pinNode = draggedPinNode, let id = draggedPinID {
                    didDragPin = true
                    if liftingPin || NSEvent.modifierFlags.contains(.option) {
                        liftingPin = true
                        let wp = view.unprojectPoint(SCNVector3(pt.x, pt.y, nodeDepth))
                        let y = min(PlacementPin.maxHeight, max(0, Float(wp.y)))
                        pinNode.position.y = CGFloat(y)
                        onMovePin?(id, Float(pinNode.position.x), y, Float(pinNode.position.z))
                    } else if let floorPt = floorPoint(at: pt, in: view) {
                        pinNode.position.x = CGFloat(floorPt.x)
                        pinNode.position.z = CGFloat(floorPt.z)
                        onMovePin?(id, floorPt.x, Float(pinNode.position.y), floorPt.z)
                    }
                    return
                }

                guard let node = draggedNode else { return }
                let wp = view.unprojectPoint(SCNVector3(pt.x, pt.y, nodeDepth))
                node.position = wp

            case .ended:
                if let pinNode = draggedPinNode, let id = draggedPinID {
                    if liftingPin {
                        let y = min(PlacementPin.maxHeight, max(0, Float(pinNode.position.y)))
                        onMovePin?(id, Float(pinNode.position.x), y, Float(pinNode.position.z))
                    } else if let floorPt = floorPoint(at: pt, in: view) {
                        pinNode.position.x = CGFloat(floorPt.x)
                        pinNode.position.z = CGFloat(floorPt.z)
                        onMovePin?(id, floorPt.x, Float(pinNode.position.y), floorPt.z)
                    }
                }
                draggedPinNode = nil
                draggedPinID = nil
                liftingPin = false
                syncCameraControl(locked: isLocked)

                if let node = draggedNode, let before = beforeDrag {
                    registerUndo(node: node, before: before, actionName: "Move Model")
                }
                draggedNode = nil; beforeDrag = nil

            case .cancelled, .failed:
                draggedPinNode = nil
                draggedPinID = nil
                liftingPin = false
                syncCameraControl(locked: isLocked)
                if let node = draggedNode, let before = beforeDrag {
                    node.position    = before.position
                    node.eulerAngles = before.eulerAngles
                }
                draggedNode = nil; beforeDrag = nil

            default: break
            }
        }

        private func pinID(from node: SCNNode) -> UUID? {
            var n: SCNNode? = node
            while let cur = n {
                if cur.name == "placement-pin",
                   let raw = cur.value(forKey: "pinID") as? String,
                   let id = UUID(uuidString: raw) {
                    return id
                }
                n = cur.parent
            }
            return nil
        }

        @objc private func handlePinClick(_ gesture: NSClickGestureRecognizer) {
            guard isPinning, let view = scnView else { return }
            if didDragPin || cameraDidDrag {
                didDragPin = false
                cameraDidDrag = false
                return
            }
            let pt = gesture.location(in: view)
            let hits = view.hitTest(pt, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue
            ])
            if let closest = hits.first, let id = pinID(from: closest.node) {
                if occupiedPinIDs.contains(id) { return }
                onRemovePin?(id)
                return
            }
            if let closest = hits.first, closest.node.name == "studio-floor" {
                let p = closest.worldCoordinates
                onDropPin?(Float(p.x), 0, Float(p.z))
                return
            }
            if findGenNode(at: pt, in: view) != nil { return }
            if let air = airPoint(at: pt, in: view) {
                onDropPin?(air.x, air.y, air.z)
            }
        }

        /// Point along the camera ray ~1.4 m from the near plane — click empty sky to drop a lifted pin.
        private func airPoint(at pt: CGPoint, in view: SCNView) -> (x: Float, y: Float, z: Float)? {
            let near = view.unprojectPoint(SCNVector3(pt.x, pt.y, 0))
            let far = view.unprojectPoint(SCNVector3(pt.x, pt.y, 1))
            let dx = far.x - near.x
            let dy = far.y - near.y
            let dz = far.z - near.z
            let len = hypot(hypot(dx, dy), dz)
            guard len > 1e-4 else { return nil }
            let t = 1.4 / len
            let y = min(PlacementPin.maxHeight, max(0, Float(near.y + t * dy)))
            return (Float(near.x + t * dx), y, Float(near.z + t * dz))
        }

        // MARK: - Double-click: Delete

        @objc private func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
            guard let view = scnView else { return }
            if !isLocked {
                let pt = gesture.location(in: view)
                let hits = view.hitTest(pt, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
                if let hit = hits.first, let id = pinID(from: hit.node), filledPinIDs.contains(id) {
                    onRetryPin?(id)
                    return
                }
            }
            guard isLocked else { return }
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


        // MARK: - Right-drag: rotate X + Y

        @objc private func handleRotate(_ gesture: NSPanGestureRecognizer) {
            guard isLocked, let view = scnView else { return }
            let pt = gesture.location(in: view)

            switch gesture.state {
            case .began:
                rotatingNode      = findGenNode(at: pt, in: view)
                guard let n = rotatingNode else { return }
                beforeRotate      = snapshot(n)

                // Cast Float euler angles → CGFloat for uniform CGFloat arithmetic
                rotateStartAngleY = CGFloat(n.eulerAngles.y)
                rotateStartAngleX = CGFloat(n.eulerAngles.x)
                rotateStartX      = pt.x
                rotateStartY      = pt.y

            case .changed:
                guard let node = rotatingNode else { return }
                let s: CGFloat = .pi / 540   // 540 screen-px = 180°
                let yaw = rotateStartAngleY + (pt.x - rotateStartX) * s
                let pitch = rotateStartAngleX + (pt.y - rotateStartY) * s
                let e = node.eulerAngles
                node.eulerAngles = SCNVector3(pitch, yaw, e.z)

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
