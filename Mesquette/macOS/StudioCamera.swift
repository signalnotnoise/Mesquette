// StudioCamera.swift
// Mesquette — Orbit / top / walk rig. SceneKit's allowsCameraControl is not used:
// its turntable target stays at the origin and pitch dies near the pole.

import Foundation
import simd

/// Pure camera math (orbit/top/walk) shared by all SceneKit hosts. No SceneKit
/// types, so the rig is unit-testable; `SceneKitStudio.apply` realizes it.
nonisolated struct StudioCameraRig: Equatable, Sendable {

    enum View: String, CaseIterable, Sendable {
        case orbit
        case top
        case walk
    }

    var view: View
    var pivot: SIMD3<Float>
    var distance: Float
    var yaw: Float
    var pitch: Float
    var eye: SIMD3<Float>

    static let minOrbitPitch: Float = -8 * .pi / 180
    static let maxOrbitPitch: Float = 88 * .pi / 180
    static let topPitch: Float = 86 * .pi / 180
    static let minWalkPitch: Float = -89 * .pi / 180
    static let maxWalkPitch: Float = 89 * .pi / 180
    static let minDistance: Float = 0.18
    static let maxDistance: Float = 48

    /// Matches `SceneKitStudio.install` — 3/4 view of the origin.
    static var home: StudioCameraRig {
        var rig = StudioCameraRig(
            view: .orbit,
            pivot: SIMD3(0, 0.12, 0),
            distance: 1,
            yaw: 0,
            pitch: 0,
            eye: SIMD3(1.05, 0.72, 1.55)
        )
        rig.aim(at: SIMD3(0, 0.12, 0), from: SIMD3(1.05, 0.72, 1.55))
        return rig
    }

    /// Direction the camera looks (SceneKit cameras face local -Z).
    var lookDirection: SIMD3<Float> {
        let cp = cos(pitch)
        let sp = sin(pitch)
        return simd_normalize(SIMD3(-sin(yaw) * cp, -sp, -cos(yaw) * cp))
    }

    var position: SIMD3<Float> {
        if view == .walk { return eye }
        return pivot - lookDirection * distance
    }

    var target: SIMD3<Float> {
        if view == .walk { return eye + lookDirection * max(distance, 1) }
        return pivot
    }

    mutating func clampPitch() {
        switch view {
        case .orbit, .top:
            pitch = min(Self.maxOrbitPitch, max(Self.minOrbitPitch, pitch))
        case .walk:
            pitch = min(Self.maxWalkPitch, max(Self.minWalkPitch, pitch))
        }
    }

    /// Set yaw/pitch/distance from an eye point looking at `world`.
    mutating func aim(at world: SIMD3<Float>, from eyePoint: SIMD3<Float>) {
        let d = world - eyePoint
        let horiz = hypot(d.x, d.z)
        yaw = atan2(-d.x, -d.z)
        pitch = atan2(-d.y, max(horiz, 1e-5))
        distance = min(Self.maxDistance, max(Self.minDistance, simd_length(d)))
        pivot = world
        eye = eyePoint
        clampPitch()
    }

    mutating func adoptView(_ new: View) {
        if new == view { return }
        switch new {
        case .walk:
            eye = position
            view = .walk
            clampPitch()
        case .top:
            if view == .walk {
                pivot = eye + lookDirection * max(distance, 1.2)
            }
            view = .top
            pitch = Self.topPitch
        case .orbit:
            if view == .walk {
                pivot = eye + lookDirection * max(distance, 1.2)
                distance = simd_length(pivot - eye)
            }
            view = .orbit
            clampPitch()
        }
    }

    mutating func frame(center: SIMD3<Float>, radius: Float) {
        pivot = center
        let dist = min(Self.maxDistance, max(1.35, radius * 2.6))
        distance = dist
        switch view {
        case .orbit:
            yaw = atan2(Float(0.55), Float(0.82))
            pitch = atan2(Float(0.42), hypot(Float(0.55), Float(0.82)))
            eye = position
        case .top:
            yaw = 0
            pitch = Self.topPitch
            distance = min(Self.maxDistance, max(dist, radius * 2.2))
            eye = position
        case .walk:
            let back = max(1.4, radius * 1.6)
            eye = SIMD3(center.x, max(Float(1.55), center.y + 0.55), center.z + back)
            aim(at: center, from: eye)
        }
        clampPitch()
    }

    /// Drag tumble. Mouse-up raises the camera so you look down at the table.
    mutating func orbit(dx: Float, dy: Float) {
        yaw += dx * 0.005
        pitch += dy * 0.005
        clampPitch()
        if view == .walk {
            pivot = eye + lookDirection * distance
        } else {
            eye = position
        }
    }

    /// First-person look. Pitch can go almost straight down at your feet.
    mutating func look(dx: Float, dy: Float) {
        yaw += dx * 0.005
        pitch += dy * 0.005
        clampPitch()
        pivot = eye + lookDirection * distance
    }

    mutating func pan(dx: Float, dy: Float) {
        let look = lookDirection
        let worldUp = SIMD3<Float>(0, 1, 0)
        var right = simd_cross(look, worldUp)
        let rightLen = simd_length(right)
        if rightLen < 1e-4 {
            right = SIMD3(1, 0, 0)
        } else {
            right /= rightLen
        }
        let up = simd_normalize(simd_cross(right, look))
        let scale = max(distance, 0.8) * 0.0025
        let delta = right * dx * scale + up * dy * scale
        pivot += delta
        eye += delta
    }

    mutating func dolly(scroll: Float) {
        if view == .walk {
            eye += lookDirection * scroll * 0.35
            eye.y = min(24, max(-0.5, eye.y))
            pivot = eye + lookDirection * distance
            return
        }
        let factor = exp(-scroll * 0.12)
        distance = min(Self.maxDistance, max(Self.minDistance, distance * factor))
        eye = position
    }

    /// Walk on the XZ plane (W/S/A/D). `up` is Q/E. Units are meters.
    mutating func walk(forward: Float, right: Float, up: Float) {
        let look = lookDirection
        var fwd = SIMD3(look.x, 0, look.z)
        let fl = simd_length(fwd)
        fwd = fl > 1e-4 ? fwd / fl : SIMD3(0, 0, -1)
        var rightV = simd_cross(fwd, SIMD3(0, 1, 0))
        let rl = simd_length(rightV)
        rightV = rl > 1e-4 ? rightV / rl : SIMD3(1, 0, 0)
        eye += fwd * forward + rightV * right + SIMD3(0, 1, 0) * up
        eye.y = min(24, max(-0.5, eye.y))
        pivot = eye + look * distance
    }
}
