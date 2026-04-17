import AppKit
import SwiftUI

/// An invisible NSViewRepresentable that intercepts the hosting window's close action.
/// When `shouldPreventClose()` returns true, the window close is blocked and
/// `onCloseAttempt` is called so the view can show a confirmation dialog.
struct WindowCloseGuard: NSViewRepresentable {
    let shouldPreventClose: () -> Bool
    let onCloseAttempt: () -> Void
    var onWindowClose: (() -> Void)?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { @MainActor in
            guard let window = view.window else { return }
            context.coordinator.install(on: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.shouldPreventClose = shouldPreventClose
        context.coordinator.onCloseAttempt = onCloseAttempt
        context.coordinator.onWindowClose = onWindowClose
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, NSWindowDelegate {
        weak var window: NSWindow?
        weak var originalDelegate: (any NSWindowDelegate)?
        var shouldPreventClose: () -> Bool = { false }
        var onCloseAttempt: () -> Void = {}
        var onWindowClose: (() -> Void)?

        @MainActor
        func install(on window: NSWindow) {
            guard self.window == nil else { return }
            self.window = window
            self.originalDelegate = window.delegate
            window.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            // windowShouldClose is called from AppKit's event loop.
            // Ensure main-thread access for @MainActor-isolated closures.
            let prevent: Bool
            if Thread.isMainThread {
                prevent = shouldPreventClose()
            } else {
                prevent = DispatchQueue.main.sync { shouldPreventClose() }
            }

            if prevent {
                DispatchQueue.main.async { [weak self] in
                    self?.onCloseAttempt()
                }
                return false
            }
            return originalDelegate?.windowShouldClose?(sender) ?? true
        }

        func windowWillClose(_ notification: Notification) {
            DispatchQueue.main.async { [weak self] in
                self?.onWindowClose?()
            }
            originalDelegate?.windowWillClose?(notification)
        }
    }
}
