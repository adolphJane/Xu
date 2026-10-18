import SwiftUI

enum AppTheme {
    static let contentMaxWidth: CGFloat = 760
    static let minimumTouchTarget: CGFloat = 44
    static let standardAnimation: Animation = .easeInOut(duration: 0.22)
    static let springAnimation: Animation = .spring(response: 0.35, dampingFraction: 0.85)
    static let dialogEnterDuration: TimeInterval = 0.28
    static let dialogExitDuration: TimeInterval = 0.20
    static let dialogEnterAnimation: Animation = .easeOut(duration: dialogEnterDuration)
    static let dialogExitAnimation: Animation = .easeIn(duration: dialogExitDuration)
    static let composerEnterAnimation: Animation = .spring(response: 0.34, dampingFraction: 0.9)
    static let composerExitDuration: TimeInterval = 0.18
    static let composerExitAnimation: Animation = .easeInOut(duration: composerExitDuration)
    static let composerInitialScale: CGFloat = 0.92
    static let composerDismissedScale: CGFloat = 0.96

    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : standardAnimation
    }
}
