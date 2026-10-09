import SwiftData
import SwiftUI

// MARK: Design tokens

/// Type scale. System font with tabular figures for every number.
enum AppFont {
    static let caption = Font.system(size: 11, weight: .medium)
    static let label = Font.system(size: 12, weight: .medium)
    static let body = Font.system(size: 13)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
    static let value = Font.system(size: 20, weight: .semibold).monospacedDigit()
    static let display = Font.system(size: 46, weight: .medium).monospacedDigit()
}

extension TimeTracker.Status {
    var title: String {
        switch self {
        case .idle: String(localized: "Ready")
        case .working: String(localized: "Running")
        case .onBreak: String(localized: "On break")
        }
    }

    /// The accent stands for "running"; breaks are amber; idle stays neutral.
    var tint: Color {
        switch self {
        case .idle: .secondary
        case .working: .brand
        case .onBreak: .amber
        }
    }

    var primarySymbol: String {
        self == .working ? "pause.fill" : "play.fill"
    }
}

// MARK: Surfaces

struct CardBackground: ViewModifier {
    var padding: CGFloat
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.hairline)
            }
    }
}

extension View {
    func card(padding: CGFloat = 16, cornerRadius: CGFloat = 10) -> some View {
        modifier(CardBackground(padding: padding, cornerRadius: cornerRadius))
    }

    /// Flat page background behind cards.
    func canvasBackground() -> some View {
        background(Color.canvas)
    }
}

struct SectionHeader<Accessory: View>: View {
    let title: LocalizedStringResource
    let accessory: Accessory

    init(_ title: LocalizedStringResource, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(AppFont.label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            accessory
        }
        .frame(minHeight: 22)
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(_ title: LocalizedStringResource) {
        self.init(title) { EmptyView() }
    }
}

struct StatTile: View {
    let title: LocalizedStringResource
    let value: String
    var caption: LocalizedStringResource?
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppFont.label)
                .foregroundStyle(.secondary)
            Text(value)
                .font(AppFont.value)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Group {
                if let caption { Text(caption) } else { Text(verbatim: " ") }
            }
                .font(AppFont.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 14)
    }
}

struct StatusBadge: View {
    let status: TimeTracker.Status

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status == .idle ? Color.secondary.opacity(0.6) : status.tint)
                .frame(width: 6, height: 6)
            Text(status.title)
                .font(AppFont.label)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Color.surfaceRaised, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.hairline))
    }
}

// MARK: Buttons

/// Filled button in the accent (or a status) color.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .brand
    var height: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration) { isEnabled in
            configuration.label
                .font(AppFont.bodyMedium)
                .foregroundStyle(Color.onBrand)
                .padding(.horizontal, 14)
                .frame(height: height)
                .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12))
                }
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
        }
    }
}

/// Quiet button on a surface with a hairline border.
struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration) { isEnabled in
            configuration.label
                .font(AppFont.bodyMedium)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(height: height)
                .background(
                    configuration.isPressed ? Color.surfaceRaised : Color.surface,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.hairline)
                }
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

/// Borderless icon or text button that shows a soft background on hover.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostButton(configuration: configuration)
    }

    private struct GhostButton: View {
        let configuration: Configuration
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(AppFont.bodyMedium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .frame(minWidth: 26, minHeight: 26)
                .background(
                    (isHovered || configuration.isPressed) ? Color.surfaceRaised : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}

/// Reads `isEnabled`, which a `ButtonStyle` cannot do directly.
private struct StyledButton<Label: View>: View {
    let configuration: ButtonStyleConfiguration
    @ViewBuilder let label: (Bool) -> Label
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label(isEnabled)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func primary(tint: Color, height: CGFloat = 30) -> PrimaryButtonStyle { PrimaryButtonStyle(tint: tint, height: height) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static func secondary(height: CGFloat) -> SecondaryButtonStyle { SecondaryButtonStyle(height: height) }
}

extension ButtonStyle where Self == GhostButtonStyle {
    static var ghost: GhostButtonStyle { GhostButtonStyle() }
}

/// Start, pause or resume. Only starting is filled with the brand color; pausing stays quiet.
struct TimerActionButton: View {
    let status: TimeTracker.Status
    let title: String
    var height: CGFloat = 32
    var fillsWidth = false
    let action: () -> Void

    var body: some View {
        if status == .working {
            Button(action: action) { label(iconColor: .amber) }
                .buttonStyle(.secondary(height: height))
        } else {
            Button(action: action) { label(iconColor: .onBrand) }
                .buttonStyle(.primary(tint: .brand, height: height))
        }
    }

    private func label(iconColor: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status.primarySymbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(iconColor)
            Text(title)
        }
        .frame(minWidth: fillsWidth ? nil : 92, maxWidth: fillsWidth ? .infinity : nil)
        .fixedSize(horizontal: !fillsWidth, vertical: false)
    }
}

// MARK: Tabs

/// Compact segmented control: the selected option sits on a raised surface.
struct PillTabs<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(AppFont.label)
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.surface)
                                    .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .strokeBorder(Color.hairline)
                                    }
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .fixedSize()
        .animation(.snappy(duration: 0.2), value: selection)
    }
}

// MARK: Misc

struct CopyButton: View {
    let value: String
    var help: LocalizedStringResource = "Copy"

    @State private var copied = false

    var body: some View {
        Button {
            Pasteboard.copy(value)
            withAnimation(.snappy) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.snappy) { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "square.on.square")
                .font(.system(size: 12, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(copied ? Color.brand : Color.secondary)
        }
        .buttonStyle(.ghost)
        .help(Text(copied ? "Copied" : help))
        .accessibilityLabel(Text(copied ? "Copied" : help))
    }
}

struct ProgressRing: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.hairline, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: progress)
        }
    }
}

/// Small rounded note with an icon, for hints and warnings inside pages.
struct Callout: View {
    let systemImage: String
    var tint: Color = .secondary
    let text: LocalizedStringResource

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(AppFont.body)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceRaised.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: Data

/// Loads the sessions of one job that started on `day`.
struct DaySessionsQuery<Content: View>: View {
    @Query private var sessions: [WorkSession]
    private let content: ([WorkSession]) -> Content

    init(day: Date, job: Job, @ViewBuilder content: @escaping ([WorkSession]) -> Content) {
        let jobID: UUID? = job.uuid
        let start = Calendar.app.startOfDay(for: day)
        let end = Calendar.app.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        _sessions = Query(
            filter: #Predicate<WorkSession> { $0.jobID == jobID && $0.start >= start && $0.start < end },
            sort: \.start
        )
        self.content = content
    }

    var body: some View {
        content(sessions)
    }
}

// MARK: Jobs

extension JobColor {
    /// Muted label colors that sit well on neutral surfaces.
    var color: Color {
        switch self {
        case .blue: Color(red: 0.32, green: 0.55, blue: 0.95)
        case .purple: Color(red: 0.55, green: 0.47, blue: 0.92)
        case .indigo: Color(red: 0.40, green: 0.45, blue: 0.85)
        case .red: Color(red: 0.89, green: 0.33, blue: 0.34)
        case .orange: Color(red: 0.93, green: 0.56, blue: 0.27)
        case .yellow: Color(red: 0.87, green: 0.71, blue: 0.22)
        case .green: Color(red: 0.32, green: 0.71, blue: 0.48)
        case .teal: Color(red: 0.20, green: 0.68, blue: 0.75)
        case .gray: Color(red: 0.55, green: 0.58, blue: 0.63)
        }
    }

    var title: String {
        switch self {
        case .blue: String(localized: "Blue")
        case .purple: String(localized: "Purple")
        case .indigo: String(localized: "Indigo")
        case .red: String(localized: "Red")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .teal: String(localized: "Teal")
        case .gray: String(localized: "Gray")
        }
    }
}

/// Icon (or colored dot) and name of a job.
struct JobBadge: View {
    let job: Job
    var font: Font = AppFont.body

    var body: some View {
        HStack(spacing: 7) {
            if job.iconData != nil {
                JobIcon(job: job, size: 16)
            } else {
                Circle()
                    .fill(job.color.color)
                    .frame(width: 8, height: 8)
            }
            Text(job.displayName)
                .lineLimit(1)
        }
        .font(font)
    }
}

/// Row of color swatches.
struct JobColorPicker: View {
    @Binding var selection: JobColor

    var body: some View {
        HStack(spacing: 6) {
            ForEach(JobColor.allCases) { color in
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 16, height: 16)
                        .padding(3)
                        .overlay {
                            if color == selection {
                                Circle().strokeBorder(Color.primary.opacity(0.7), lineWidth: 1.5)
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(color.title)
                .accessibilityLabel(color.title)
                .accessibilityAddTraits(color == selection ? .isSelected : [])
            }
        }
    }
}
