import SwiftUI

enum AppColors {
    #if os(iOS)
    static let brand = Color("BrandAccent")
    static let brandAction = Color("BrandAction")
    static let canvas = Color("Canvas")
    static let surface = Color("Surface")
    static let border = Color("Border")
    static let success = Color("StatusSuccess")
    static let warning = Color("StatusWarning")
    static let danger = Color("StatusDanger")
    #else
    static let brand = Color(nsColor: .controlAccentColor)
    static let brandAction = Color(nsColor: .controlAccentColor)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    #endif

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary

    /// Selects a readable foreground for a filled action, including custom macOS accents.
    static func foreground(on background: Color, colorScheme: ColorScheme? = nil) -> Color {
        #if os(macOS)
        guard let rgb = NSColor(background).usingColorSpace(.deviceRGB) else { return .white }
        let components = (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
        #else
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let rgb = UIColor(background).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return .white }
        let components = (red, green, blue)
        #endif

        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(components.0) + 0.7152 * linear(components.1) + 0.0722 * linear(components.2)
        return luminance > 0.179 ? .black : .white
    }
}
