// MacWindowFullscreenSupport.swift
// Enables true fullscreen and title-bar double-click → toggle fullscreen.

#if os(macOS)
import AppKit
import SwiftUI

/// Attaches to the key window once: marks it full-screen capable and
/// toggles fullscreen when the user double-clicks the title bar / top chrome
/// (the standard drag region above `contentLayoutRect`).
struct MacWindowFullscreenSupport: NSViewRepresentable {

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(hostingView: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if nsView.window != nil {
            context.coordinator.configureWindow(from: nsView)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator {
        private var monitor: Any?
        private weak var configuredWindow: NSWindow?

        func install(hostingView: NSView) {
            // Defer until the view is in a window.
            DispatchQueue.main.async { [weak self, weak hostingView] in
                guard let self, let hostingView else { return }
                self.configureWindow(from: hostingView)
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self else { return event }
                return self.handleMouseDown(event) ?? event
            }
        }

        func configureWindow(from view: NSView) {
            guard let window = view.window else { return }
            // Mutating styleMask / collectionBehavior during a SwiftUI layout
            // pass triggers layoutSubtreeIfNeeded recursion. Configure once.
            if configuredWindow === window { return }
            configuredWindow = window
            window.collectionBehavior.insert([.fullScreenPrimary, .fullScreenAllowsTiling])
            if !window.styleMask.contains(.resizable) {
                window.styleMask.insert(.resizable)
            }
        }

        func handleMouseDown(_ event: NSEvent) -> NSEvent? {
            // Only double-clicks in *our* window's title-bar band.
            guard event.clickCount == 2,
                  let window = event.window,
                  window === configuredWindow || configuredWindow == nil
            else {
                return event
            }

            // Prefer the window we configured; fall back to event window.
            let target = configuredWindow ?? window
            guard window === target else { return event }

            // Title bar sits above the content layout rect (window coords, origin bottom-left).
            let loc = event.locationInWindow
            let content = target.contentLayoutRect
            let inTitleBarBand = loc.y >= content.maxY - 1

            // Also accept a thin strip under the traffic lights when content is full-size
            // (hidden title bar): top ~22pt of the window frame in content coords.
            let topStripHeight: CGFloat = 22
            let frameH = target.contentView?.bounds.height ?? target.frame.height
            let inTopStrip = loc.y >= frameH - topStripHeight

            guard inTitleBarBand || inTopStrip else {
                return event
            }

            // Don't steal double-clicks from text fields / controls that happen to sit high.
            if let hit = target.contentView?.hitTest(loc),
               hit is NSTextView || hit is NSTextField || hit is NSControl,
               !(hit is NSButton) {
                // Allow buttons (e.g. in toolbar); block text editing views.
                if hit is NSTextView || hit is NSTextField {
                    return event
                }
            }

            target.toggleFullScreen(nil)
            return nil // consume — avoid system zoom fighting fullscreen
        }

        func teardown() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            configuredWindow = nil
        }

        isolated deinit {
            teardown()
        }
    }
}
#endif
