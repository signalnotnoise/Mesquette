// macOS/Mac3DPreviewCoordinator.swift
// Mesquette — macOS only. Gesture/camera/pin-drag coordinator for
// Mac3DPreviewView; split out verbatim (behavior unchanged).

#if os(macOS)
import SwiftUI
import SceneKit
import simd
import ShapERuntime

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
        var cameraDidDrag = false
        private var cameraTracking: CameraTracking = .none
        private var lastMouse: NSPoint = .zero
        private var walkKeys = Set<UInt16>()
        private var walkTimer: Timer?
        private var walkSprinting = false

        private var draggedPinNode: SCNNode?
        var draggedPinID: UUID?
        private var didDragPin: Bool = false
        private var liftingPin: Bool = false
        private var scrollMonitor: Any?
        private weak var panGesture: NSPanGestureRecognizer?

        /// Tracks which GenerationRecord IDs have been added to the scene.
        /// Prevents updateNSView from re-adding (and thus resetting) existing nodes.
        var addedNodes: [UUID: SCNNode] = [:]
        var lastMeshStamp: [UUID: PreviewMeshStamp] = [:]
        var lastTablePose: [UUID: AppliedTablePose] = [:]
        var lastSceneSignature: Int?

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
