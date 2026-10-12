import SwiftUI

enum AppTheme {
    static let contentMaxWidth: CGFloat = 760
    static let minimumTouchTarget: CGFloat = 44
    static let standardAnimation: Animation = .easeInOut(duration: 0.22)
    static let springAnimation: Animation = .spring(response: 0.35, dampingFraction: 0.85)

    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : standardAnimation
    }
}
