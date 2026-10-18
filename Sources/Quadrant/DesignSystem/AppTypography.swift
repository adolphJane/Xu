import SwiftUI

enum AppTypography {
    static let largeTitle: Font = .largeTitle.weight(.bold)
    static let title: Font = .title2.weight(.semibold)
    static let headline: Font = .headline
    static let body: Font = .body
    static let callout: Font = .callout
    static let caption: Font = .caption
}

#if os(macOS)
extension AppTypography {
    /// System text roles with the desktop user's font and size preferences applied.
    static func desktop(_ style: NSFont.TextStyle, scale: Double = 1,
                        weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let size = NSFont.preferredFont(forTextStyle: style).pointSize
        return .system(size: size * scale, weight: weight, design: design)
    }
}
#endif
