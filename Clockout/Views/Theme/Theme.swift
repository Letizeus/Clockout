import AppKit
import SwiftUI

/// All colors of one appearance (light or dark) of a theme.
nonisolated struct ThemePalette {
    let canvas: NSColor
    let sidebar: NSColor
    let surface: NSColor
    let surfaceRaised: NSColor
    let hairline: NSColor
    let text: NSColor
    let brand: NSColor
    let positive: NSColor
    let negative: NSColor
    let amber: NSColor

    init(
        canvas: UInt32, sidebar: UInt32, surface: UInt32, raised: UInt32, hairline: UInt32,
        text: UInt32, brand: UInt32, positive: UInt32? = nil, negative: UInt32? = nil, amber: UInt32? = nil,
        isDark: Bool
    ) {
        self.canvas = NSColor(hex: canvas)
        self.sidebar = NSColor(hex: sidebar)
        self.surface = NSColor(hex: surface)
        self.surfaceRaised = NSColor(hex: raised)
        self.hairline = NSColor(hex: hairline)
        self.text = NSColor(hex: text)
        self.brand = NSColor(hex: brand)
        self.positive = NSColor(hex: positive ?? (isDark ? 0x5CC98A : 0x15924B))
        self.negative = NSColor(hex: negative ?? (isDark ? 0xF07272 : 0xD93B3B))
        self.amber = NSColor(hex: amber ?? (isDark ? 0xE9AE48 : 0xC77A0A))
    }
}

/// A named color scheme inspired by a well known app or editor theme.
nonisolated struct AppTheme: Identifiable {
    let id: String
    let name: String
    let light: ThemePalette?
    let dark: ThemePalette?

    /// Themes that only exist in one appearance force it.
    var fixedScheme: ColorScheme? {
        if light == nil { return .dark }
        if dark == nil { return .light }
        return nil
    }

    func palette(dark isDark: Bool) -> ThemePalette {
        if isDark { return dark ?? light! }
        return light ?? dark!
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: Runtime lookup

/// What the dynamic colors below resolve against. Written by `AppSettings` on the main thread;
/// read by AppKit while drawing.
nonisolated enum ThemeRuntime {
    nonisolated(unsafe) static var theme: AppTheme = AppTheme.standard
    nonisolated(unsafe) static var customAccent: NSColor?

    static func palette(for appearance: NSAppearance) -> ThemePalette {
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return theme.palette(dark: isDark)
    }

    static func brand(for appearance: NSAppearance) -> NSColor {
        customAccent ?? palette(for: appearance).brand
    }
}

extension Color {
    static let canvas = dynamic { $0.canvas }
    static let sidebar = dynamic { $0.sidebar }
    static let surface = dynamic { $0.surface }
    static let surfaceRaised = dynamic { $0.surfaceRaised }
    static let hairline = dynamic { $0.hairline }
    static let text = dynamic { $0.text }
    static let positive = dynamic { $0.positive }
    static let negative = dynamic { $0.negative }
    static let amber = dynamic { $0.amber }

    static let brand = Color(nsColor: NSColor(name: nil) { ThemeRuntime.brand(for: $0) })

    /// Black or white, whichever reads better on the brand color.
    static let onBrand = Color(nsColor: NSColor(name: nil) { appearance in
        ThemeRuntime.brand(for: appearance).isLight ? NSColor(hex: 0x121214) : .white
    })

    private static func dynamic(_ pick: @escaping @Sendable (ThemePalette) -> NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { pick(ThemeRuntime.palette(for: $0)) })
    }
}

extension ShapeStyle where Self == Color {
    static var canvas: Color { .canvas }
    static var sidebar: Color { .sidebar }
    static var surface: Color { .surface }
    static var surfaceRaised: Color { .surfaceRaised }
    static var hairline: Color { .hairline }
    static var positive: Color { .positive }
    static var negative: Color { .negative }
    static var amber: Color { .amber }
    static var brand: Color { .brand }
    static var onBrand: Color { .onBrand }
}

nonisolated extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// "#RRGGBB", for storing a custom accent.
    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        let r = Int((color.redComponent * 255).rounded())
        let g = Int((color.greenComponent * 255).rounded())
        let b = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    convenience init?(hexString: String) {
        let digits = hexString.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(hex: value)
    }

    var isLight: Bool {
        let color = usingColorSpace(.sRGB) ?? self
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
        return luminance > 0.4
    }
}

// MARK: Applying

/// Theme, appearance and accent for a whole scene. Rebuilds the content when the theme changes,
/// so every dynamic color is resolved again.
struct ThemedScene: ViewModifier {
    /// The settings window keeps its views while the accent changes, so the color panel stays connected.
    var rebuildsOnAccentChange = true

    @Environment(AppSettings.self) private var settings

    func body(content: Content) -> some View {
        content
            .id(rebuildsOnAccentChange ? settings.themeKey : settings.themeID)
            .preferredColorScheme(settings.theme.fixedScheme ?? settings.appearanceMode.colorScheme)
            .tint(settings.customAccentHex.flatMap { NSColor(hexString: $0) }.map { Color(nsColor: $0) } ?? Color.brand)
            .foregroundStyle(Color.text)
    }
}

extension View {
    func themedScene(rebuildsOnAccentChange: Bool = true) -> some View {
        modifier(ThemedScene(rebuildsOnAccentChange: rebuildsOnAccentChange))
    }
}

// MARK: Catalog

nonisolated extension AppTheme {
    static let standard = AppTheme(
        id: "standard", name: "Clockout",
        light: ThemePalette(canvas: 0xFAFAFA, sidebar: 0xF3F3F5, surface: 0xFFFFFF, raised: 0xF2F2F4, hairline: 0xE5E5E8, text: 0x1D1D1F, brand: 0x0F9384, isDark: false),
        dark: ThemePalette(canvas: 0x111113, sidebar: 0x0C0C0E, surface: 0x18181B, raised: 0x222226, hairline: 0x2A2A2F, text: 0xEDEDEF, brand: 0x3CC4AE, isDark: true)
    )

    static let all: [AppTheme] = [
        standard,
        AppTheme(
            id: "linear", name: "Linear",
            light: ThemePalette(canvas: 0xFCFCFD, sidebar: 0xF4F4F6, surface: 0xFFFFFF, raised: 0xF1F1F4, hairline: 0xE4E4E8, text: 0x1B1B1F, brand: 0x5E6AD2, isDark: false),
            dark: ThemePalette(canvas: 0x101113, sidebar: 0x0B0C0D, surface: 0x17181B, raised: 0x202125, hairline: 0x26282C, text: 0xE6E6E9, brand: 0x6E79D6, isDark: true)
        ),
        AppTheme(
            id: "notion", name: "Notion",
            light: ThemePalette(canvas: 0xFFFFFF, sidebar: 0xF7F7F5, surface: 0xFFFFFF, raised: 0xF1F1EF, hairline: 0xE9E9E7, text: 0x37352F, brand: 0x2383E2, isDark: false),
            dark: ThemePalette(canvas: 0x191919, sidebar: 0x202020, surface: 0x202020, raised: 0x2C2C2C, hairline: 0x2F2F2F, text: 0xD4D4D4, brand: 0x2383E2, isDark: true)
        ),
        AppTheme(
            id: "raycast", name: "Raycast",
            light: ThemePalette(canvas: 0xF5F5F6, sidebar: 0xEDEDEF, surface: 0xFFFFFF, raised: 0xEFEFF1, hairline: 0xE3E3E6, text: 0x1A1A1D, brand: 0xFF6363, isDark: false),
            dark: ThemePalette(canvas: 0x0E0E10, sidebar: 0x141416, surface: 0x1B1B1E, raised: 0x242428, hairline: 0x2B2B30, text: 0xEDEDEF, brand: 0xFF6363, isDark: true)
        ),
        AppTheme(
            id: "github", name: "GitHub",
            light: ThemePalette(canvas: 0xF6F8FA, sidebar: 0xFFFFFF, surface: 0xFFFFFF, raised: 0xEFF2F5, hairline: 0xD0D7DE, text: 0x1F2328, brand: 0x1F883D, positive: 0x1A7F37, negative: 0xCF222E, amber: 0x9A6700, isDark: false),
            dark: ThemePalette(canvas: 0x0D1117, sidebar: 0x010409, surface: 0x161B22, raised: 0x21262D, hairline: 0x30363D, text: 0xE6EDF3, brand: 0x2EA043, positive: 0x3FB950, negative: 0xF85149, amber: 0xD29922, isDark: true)
        ),
        AppTheme(
            id: "xcode", name: "Xcode",
            light: ThemePalette(canvas: 0xF7F7F7, sidebar: 0xEFEFEF, surface: 0xFFFFFF, raised: 0xEFEFEF, hairline: 0xE0E0E0, text: 0x262626, brand: 0xAD3DA4, isDark: false),
            dark: ThemePalette(canvas: 0x1F1F24, sidebar: 0x26262B, surface: 0x292A30, raised: 0x323339, hairline: 0x3A3B42, text: 0xDFDFE0, brand: 0xFC5FA3, isDark: true)
        ),
        AppTheme(
            id: "vscode", name: "VS Code",
            light: ThemePalette(canvas: 0xF8F8F8, sidebar: 0xF3F3F3, surface: 0xFFFFFF, raised: 0xEFEFEF, hairline: 0xE5E5E5, text: 0x3B3B3B, brand: 0x005FB8, isDark: false),
            dark: ThemePalette(canvas: 0x1F1F1F, sidebar: 0x181818, surface: 0x252526, raised: 0x2D2D2D, hairline: 0x2B2B2B, text: 0xCCCCCC, brand: 0x0078D4, isDark: true)
        ),
        AppTheme(
            id: "cursor", name: "Cursor",
            light: ThemePalette(canvas: 0xF7F7F7, sidebar: 0xF0F0F0, surface: 0xFFFFFF, raised: 0xEEEEEE, hairline: 0xE2E2E2, text: 0x1E1E1E, brand: 0x2F7FE6, isDark: false),
            dark: ThemePalette(canvas: 0x141414, sidebar: 0x0F0F0F, surface: 0x1C1C1C, raised: 0x262626, hairline: 0x2A2A2A, text: 0xE4E4E4, brand: 0x4C9DF8, isDark: true)
        ),
        AppTheme(
            id: "sentry", name: "Sentry",
            light: ThemePalette(canvas: 0xFAF9FB, sidebar: 0xEDE9F2, surface: 0xFFFFFF, raised: 0xF2EFF5, hairline: 0xE0DCE5, text: 0x2B2233, brand: 0x6C5FC7, isDark: false),
            dark: ThemePalette(canvas: 0x1A141F, sidebar: 0x150F19, surface: 0x241D2A, raised: 0x2F2936, hairline: 0x3E3446, text: 0xEBE6EF, brand: 0x8C7BF7, isDark: true)
        ),
        AppTheme(
            id: "dracula", name: "Dracula",
            light: nil,
            dark: ThemePalette(canvas: 0x21222C, sidebar: 0x191A21, surface: 0x282A36, raised: 0x343746, hairline: 0x44475A, text: 0xF8F8F2, brand: 0xBD93F9, positive: 0x50FA7B, negative: 0xFF5555, amber: 0xFFB86C, isDark: true)
        ),
        AppTheme(
            id: "nord", name: "Nord",
            light: ThemePalette(canvas: 0xECEFF4, sidebar: 0xE5E9F0, surface: 0xF8F9FB, raised: 0xE5E9F0, hairline: 0xD8DEE9, text: 0x2E3440, brand: 0x5E81AC, positive: 0x6A8F4E, negative: 0xBF616A, amber: 0xC79A2A, isDark: false),
            dark: ThemePalette(canvas: 0x2E3440, sidebar: 0x292E39, surface: 0x3B4252, raised: 0x434C5E, hairline: 0x4C566A, text: 0xECEFF4, brand: 0x88C0D0, positive: 0xA3BE8C, negative: 0xBF616A, amber: 0xEBCB8B, isDark: true)
        ),
        AppTheme(
            id: "solarized", name: "Solarized",
            light: ThemePalette(canvas: 0xFDF6E3, sidebar: 0xEEE8D5, surface: 0xFFFBF0, raised: 0xEEE8D5, hairline: 0xE1DBC6, text: 0x586E75, brand: 0x268BD2, positive: 0x859900, negative: 0xDC322F, amber: 0xB58900, isDark: false),
            dark: ThemePalette(canvas: 0x002B36, sidebar: 0x00222B, surface: 0x073642, raised: 0x0B404D, hairline: 0x154956, text: 0x93A1A1, brand: 0x268BD2, positive: 0x859900, negative: 0xDC322F, amber: 0xB58900, isDark: true)
        ),
        AppTheme(
            id: "catppuccin", name: "Catppuccin",
            light: ThemePalette(canvas: 0xEFF1F5, sidebar: 0xE6E9EF, surface: 0xF9FAFC, raised: 0xE6E9EF, hairline: 0xCCD0DA, text: 0x4C4F69, brand: 0x8839EF, positive: 0x40A02B, negative: 0xD20F39, amber: 0xDF8E1D, isDark: false),
            dark: ThemePalette(canvas: 0x1E1E2E, sidebar: 0x181825, surface: 0x252536, raised: 0x313244, hairline: 0x3B3D52, text: 0xCDD6F4, brand: 0xCBA6F7, positive: 0xA6E3A1, negative: 0xF38BA8, amber: 0xFAB387, isDark: true)
        ),
        AppTheme(
            id: "tokyonight", name: "Tokyo Night",
            light: nil,
            dark: ThemePalette(canvas: 0x1A1B26, sidebar: 0x16161E, surface: 0x1F2335, raised: 0x292E42, hairline: 0x2F3549, text: 0xC0CAF5, brand: 0x7AA2F7, positive: 0x9ECE6A, negative: 0xF7768E, amber: 0xE0AF68, isDark: true)
        ),
        AppTheme(
            id: "onedark", name: "One Dark",
            light: nil,
            dark: ThemePalette(canvas: 0x282C34, sidebar: 0x21252B, surface: 0x2C313A, raised: 0x333842, hairline: 0x3E4451, text: 0xABB2BF, brand: 0x61AFEF, positive: 0x98C379, negative: 0xE06C75, amber: 0xE5C07B, isDark: true)
        ),
        AppTheme(
            id: "gruvbox", name: "Gruvbox",
            light: ThemePalette(canvas: 0xFBF1C7, sidebar: 0xF2E5BC, surface: 0xF9F5D7, raised: 0xEBDBB2, hairline: 0xD5C4A1, text: 0x3C3836, brand: 0xAF3A03, positive: 0x79740E, negative: 0x9D0006, amber: 0xB57614, isDark: false),
            dark: ThemePalette(canvas: 0x282828, sidebar: 0x1D2021, surface: 0x32302F, raised: 0x3C3836, hairline: 0x504945, text: 0xEBDBB2, brand: 0xFE8019, positive: 0xB8BB26, negative: 0xFB4934, amber: 0xFABD2F, isDark: true)
        ),
    ]

    static func named(_ id: String?) -> AppTheme {
        all.first { $0.id == id } ?? standard
    }
}
