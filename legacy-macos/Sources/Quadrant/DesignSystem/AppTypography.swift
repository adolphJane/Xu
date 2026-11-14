import SwiftUI

enum AppTypography {
    #if os(macOS)
    static let largeTitle: Font = .system(size: 28, weight: .bold)
    static let title: Font = .system(size: 20, weight: .semibold)
    static let headline: Font = .system(size: 15, weight: .semibold)
    static let body: Font = .system(size: 14)
    static let callout: Font = .system(size: 13)
    static let caption: Font = .system(size: 12)
    #else
    static let largeTitle: Font = .largeTitle.weight(.bold)
    static let title: Font = .title2.weight(.semibold)
    static let headline: Font = .headline
    static let body: Font = .body
    static let callout: Font = .callout
    static let caption: Font = .caption
    #endif
}

#if os(macOS)
extension AppTypography {
    /// System text roles with the desktop user's font and size preferences applied.
    static func desktop(_ style: NSFont.TextStyle, scale: Double = 1,
                        weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let preferred = NSFont.preferredFont(forTextStyle: style).pointSize
        let minimum: CGFloat
        switch style {
        case .largeTitle: minimum = 28
        case .title1: minimum = 22
        case .title2: minimum = 20
        case .title3, .headline: minimum = 15
        case .body: minimum = 14
        case .callout, .subheadline: minimum = 13
        case .footnote, .caption1, .caption2: minimum = 12
        default: minimum = 13
        }
        let size = max(preferred, minimum)
        return .system(size: size * scale, weight: weight, design: design)
    }
}
#endif
