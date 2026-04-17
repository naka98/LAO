import AppKit
import SwiftUI

/// Invisible NSViewRepresentable that sets the hosting NSWindow's title and identifier.
/// Even with `.hiddenTitleBar`, the title is shown in Mission Control, Cmd+`,
/// and the Dock's window list. The identifier enables reliable window lookup
/// independent of the display title.
struct WindowTitle: NSViewRepresentable {
    let title: String
    var identifier: String?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.title = title
            if let identifier {
                view.window?.identifier = NSUserInterfaceItemIdentifier(identifier)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.title = title
        if let identifier {
            nsView.window?.identifier = NSUserInterfaceItemIdentifier(identifier)
        }
    }
}
