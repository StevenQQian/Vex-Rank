#if canImport(SwiftUI)
import SwiftUI

/// The four palettes from the web build, carried over as values.
///
/// On the web these are CSS custom properties, which is what made a theme a
/// token swap rather than a component change. The same discipline applies here:
/// views reference roles (`surface`, `accent`), never literal colours.
///
/// All four are dark by design. The interface leans on translucent white
/// throughout, so a light palette needs those rewritten first and would ship
/// broken otherwise.
@available(iOS 17.0, macOS 14.0, *)
public struct VEXTheme: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let page: Color
    public let chrome: Color
    public let surface: Color
    public let surfaceRaised: Color
    public let accent: Color
    public let band: Color

    public static let midnight = VEXTheme(
        id: "midnight", name: "Midnight",
        page: Color(hex: 0x090b0f), chrome: Color(hex: 0x0d1015),
        surface: Color(hex: 0x101319), surfaceRaised: Color(hex: 0x151a22),
        // 4.57:1 on surface. The brand red #ed2b3a measured 4.43:1, just under
        // the small-text floor, so the shipped value is nudged up.
        accent: Color(hex: 0xee3240), band: Color(hex: 0x282c20)
    )

    public static let ember = VEXTheme(
        id: "ember", name: "Ember",
        page: Color(hex: 0x0d0b09), chrome: Color(hex: 0x12100d),
        surface: Color(hex: 0x17130f), surfaceRaised: Color(hex: 0x1e1914),
        accent: Color(hex: 0xf5a524), band: Color(hex: 0x2c2416)   // 9.05:1
    )

    public static let abyss = VEXTheme(
        id: "abyss", name: "Abyss",
        page: Color(hex: 0x070a12), chrome: Color(hex: 0x0a0f1a),
        surface: Color(hex: 0x0e1420), surfaceRaised: Color(hex: 0x141c2c),
        accent: Color(hex: 0x38bdf8), band: Color(hex: 0x16283a)   // 8.60:1
    )

    public static let moss = VEXTheme(
        id: "moss", name: "Moss",
        page: Color(hex: 0x0a0c09), chrome: Color(hex: 0x0e110c),
        surface: Color(hex: 0x121711), surfaceRaised: Color(hex: 0x1a2018),
        accent: Color(hex: 0xa3e635), band: Color(hex: 0x232d1c)   // 12.04:1
    )

    public static let all: [VEXTheme] = [.midnight, .ember, .abyss, .moss]

    public static func named(_ id: String?) -> VEXTheme {
        all.first { $0.id == id } ?? .midnight
    }
}

@available(iOS 17.0, macOS 14.0, *)
extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct VEXThemeKey: EnvironmentKey {
    static let defaultValue: VEXTheme = .midnight
}

@available(iOS 17.0, macOS 14.0, *)
public extension EnvironmentValues {
    var vexTheme: VEXTheme {
        get { self[VEXThemeKey.self] }
        set { self[VEXThemeKey.self] = newValue }
    }
}
#endif
