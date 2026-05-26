import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Cross-platform semantic colors used by `FeedbackSheet`. SwiftUI's built-in
/// colors are inconsistent across platforms (e.g. `Color(.windowBackground)`
/// only exists on macOS), so we resolve them via the platform's native palette.
enum PlatformColor {
    static var windowBackground: Color {
        #if canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor)
        #elseif canImport(UIKit)
        return Color(uiColor: .systemBackground)
        #else
        return Color.gray.opacity(0.1)
        #endif
    }

    static var controlBackground: Color {
        #if canImport(AppKit)
        return Color(nsColor: .controlBackgroundColor)
        #elseif canImport(UIKit)
        return Color(uiColor: .secondarySystemBackground)
        #else
        return Color.gray.opacity(0.2)
        #endif
    }

    static var textBackground: Color {
        #if canImport(AppKit)
        return Color(nsColor: .textBackgroundColor)
        #elseif canImport(UIKit)
        return Color(uiColor: .systemBackground)
        #else
        return Color.white
        #endif
    }

    static var separator: Color {
        #if canImport(AppKit)
        return Color(nsColor: .separatorColor)
        #elseif canImport(UIKit)
        return Color(uiColor: .separator)
        #else
        return Color.gray.opacity(0.3)
        #endif
    }
}
