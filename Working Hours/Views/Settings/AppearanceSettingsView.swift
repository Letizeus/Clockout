import AppKit
import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(AppSettings.self) private var settings

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        @Bindable var settings = settings
        let theme = settings.theme

        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "Theme") {
                SettingsBlock {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(AppTheme.all) { candidate in
                            ThemeCard(theme: candidate, isSelected: candidate.id == theme.id) {
                                settings.themeID = candidate.id
                            }
                        }
                    }
                }
            }

            SettingsSection(footer: theme.fixedScheme.map { scheme -> LocalizedStringResource in
                scheme == .dark ? "\(theme.name) is only available in dark." : "\(theme.name) is only available in light."
            }) {
                SettingsRow(title: "Appearance mode") {
                    PillTabs(options: AppearanceMode.allCases.map { ($0, $0.title) }, selection: $settings.appearanceMode)
                        .disabled(theme.fixedScheme != nil)
                        .opacity(theme.fixedScheme == nil ? 1 : 0.5)
                }
            }

            SettingsSection(
                title: "Accent Color",
                footer: "The accent color marks running time, progress and the main action. Without your own color, the theme's color is used."
            ) {
                AccentPicker()
            }
        }
    }
}

/// Small preview of a theme: light half on the left, dark half on the right.
private struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 0) {
                    if let light = theme.light {
                        PalettePreview(palette: light)
                    }
                    if let dark = theme.dark {
                        PalettePreview(palette: dark)
                    }
                }
                .frame(height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? Color.brand : Color.primary.opacity(isHovered ? 0.25 : 0.12), lineWidth: isSelected ? 2 : 1)
                }

                HStack(spacing: 4) {
                    Text(theme.name)
                        .font(AppFont.label)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.brand)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text("Theme \(theme.name)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A tiny window: sidebar strip, a card with text lines and an accent bar.
private struct PalettePreview: View {
    let palette: ThemePalette

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(Color(nsColor: palette.text).opacity(0.5)).frame(width: 14, height: 3)
                Capsule().fill(Color(nsColor: palette.text).opacity(0.25)).frame(width: 10, height: 3)
                Capsule().fill(Color(nsColor: palette.text).opacity(0.25)).frame(width: 12, height: 3)
                Spacer()
            }
            .padding(6)
            .frame(width: 24)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: palette.sidebar))

            VStack(alignment: .leading, spacing: 5) {
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(Color(nsColor: palette.text).opacity(0.8)).frame(width: 22, height: 4)
                    Capsule().fill(Color(nsColor: palette.text).opacity(0.3)).frame(width: 30, height: 3)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: palette.surface), in: RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(nsColor: palette.hairline)))

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: palette.brand))
                    .frame(width: 26, height: 8)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: palette.canvas))
        }
    }
}

private struct AccentPicker: View {
    @Environment(AppSettings.self) private var settings

    private let presets: [(name: String, hex: String)] = [
        (String(localized: "Teal"), "#14A38E"), (String(localized: "Blue"), "#2F7FE6"), (String(localized: "Indigo"), "#5E6AD2"),
        (String(localized: "Green"), "#2EA043"), (String(localized: "Yellow"), "#D9A21B"), (String(localized: "Orange"), "#F0883E"),
        (String(localized: "Red"), "#E5484D"), (String(localized: "Pink"), "#E54D8F"), (String(localized: "Graphite"), "#6E7681"),
    ]

    var body: some View {
        SettingsToggle(title: "Custom accent color", isOn: Binding(
            get: { settings.customAccentHex != nil },
            set: { settings.customAccentHex = $0 ? (settings.customAccentHex ?? NSColor(Color.brand).hexString) : nil }
        ))

        if let hex = settings.customAccentHex {
            SettingsRow(title: "Color") {
                HStack(spacing: 6) {
                    ForEach(presets, id: \.hex) { preset in
                        Button {
                            settings.customAccentHex = preset.hex
                        } label: {
                            Circle()
                                .fill(Color(nsColor: NSColor(hexString: preset.hex) ?? .gray))
                                .frame(width: 16, height: 16)
                                .padding(3)
                                .overlay {
                                    if preset.hex.caseInsensitiveCompare(hex) == .orderedSame {
                                        Circle().strokeBorder(Color.primary.opacity(0.7), lineWidth: 1.5)
                                    }
                                }
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                        .accessibilityLabel(preset.name)
                    }
                    ColorPicker("Custom Color", selection: Binding(
                        get: { Color(nsColor: NSColor(hexString: hex) ?? .gray) },
                        set: { settings.customAccentHex = NSColor($0).hexString }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .help("Choose any color")
                }
            }
        }
    }
}
