import CoreGraphics
import Foundation

enum LAOWindowLayoutMode: String {
    case standard
    case compact

    static var current: LAOWindowLayoutMode {
        let arguments = ProcessInfo.processInfo.arguments.map { $0.lowercased() }
        if let flagIndex = arguments.firstIndex(of: "--window-layout"),
           arguments.indices.contains(flagIndex + 1),
           let mode = LAOWindowLayoutMode(rawValue: arguments[flagIndex + 1]) {
            return mode
        }

        if let envValue = ProcessInfo.processInfo.environment["LAO_WINDOW_LAYOUT"]?.lowercased(),
           let mode = LAOWindowLayoutMode(rawValue: envValue) {
            return mode
        }

        return .standard
    }

    var mainDefaultSize: CGSize {
        switch self {
        case .standard:
            return CGSize(width: 1440, height: 900)
        case .compact:
            return CGSize(width: 1260, height: 780)
        }
    }

    var mainMinimumSize: CGSize {
        switch self {
        case .standard, .compact:
            return CGSize(width: 1260, height: 760)
        }
    }

    var launcherDefaultSize: CGSize {
        CGSize(width: 380, height: 620)
    }

    var launcherMinimumSize: CGSize {
        CGSize(width: 320, height: 500)
    }

    // Workspace windows reuse main sizes since they host the same IdeaBoard content.
    var workspaceDefaultSize: CGSize { mainDefaultSize }
    var workspaceMinimumSize: CGSize { mainMinimumSize }

    var settingsDefaultSize: CGSize {
        switch self {
        case .standard:
            return CGSize(width: 900, height: 680)
        case .compact:
            return CGSize(width: 860, height: 640)
        }
    }

    var settingsMinimumSize: CGSize {
        switch self {
        case .standard, .compact:
            return CGSize(width: 820, height: 640)
        }
    }

}
