import SwiftData
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case today
    case history
    case statistics

    var id: Self { self }

    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .history: String(localized: "History")
        case .statistics: String(localized: "Statistics")
        }
    }

    var symbol: String {
        switch self {
        case .today: "timer"
        case .history: "calendar"
        case .statistics: "chart.bar.xaxis"
        }
    }
}

struct ContentView: View {
    @SceneStorage("sidebarSelection") private var selection: SidebarItem = .today
    @Environment(AppSettings.self) private var settings
    @Environment(JobStore.self) private var jobs
    @Environment(\.modelContext) private var context
    @State private var showsOnboarding = false

    private static let sidebarWidth: CGFloat = 230

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                JobSwitcher()
                    .padding(.horizontal, 10)
                    .padding(.bottom, 14)

                VStack(spacing: 1) {
                    ForEach(SidebarItem.allCases) { item in
                        SidebarRow(title: item.title, symbol: item.symbol, isSelected: selection == item) {
                            selection = item
                        }
                    }
                }
                .padding(.horizontal, 10)

                Spacer(minLength: 12)

                SidebarStatusView()
                    .padding(10)
            }
            // Laid out at a fixed width and pinned to the trailing edge, so the content slides
            // in and out with the column instead of being squeezed on every animation frame.
            .frame(width: Self.sidebarWidth)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .clipped()
            .background(Color.sidebar.ignoresSafeArea())
            .navigationSplitViewColumnWidth(Self.sidebarWidth)
        } detail: {
            Group {
                switch selection {
                case .today: TodayView()
                case .history: HistoryView()
                case .statistics: StatisticsView()
                }
            }
            .canvasBackground()
        }
        .task {
            if !settings.onboardingDone {
                // Existing users with entries skip the first-start setup.
                let hasEntries = ((try? context.fetchCount(FetchDescriptor<WorkSession>())) ?? 0) > 0
                if hasEntries { settings.onboardingDone = true } else { showsOnboarding = true }
            }
            await HolidaySetup.runInitialDetection(settings: settings, jobs: jobs)
        }
        .sheet(isPresented: $showsOnboarding) {
            OnboardingView(job: jobs.currentJob)
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(title)
                    .font(AppFont.bodyMedium)
                Spacer()
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                Color.primary.opacity(isSelected ? 0.08 : (isHovered ? 0.04 : 0)),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SidebarStatusView: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(JobStore.self) private var jobs

    var body: some View {
        let job = jobs.currentJob
        let status = tracker.status(for: job)
        let worked = tracker.report(forDayOf: tracker.now, job: job, now: tracker.now).workedDuration

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(status == .idle ? Color.secondary.opacity(0.5) : status.tint)
                        .frame(width: 6, height: 6)
                    Text("Today \u{00B7} \(status.title)")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
                Text(worked.stopwatch)
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            Spacer()
            Button {
                tracker.togglePrimary(for: job)
            } label: {
                Image(systemName: status.primarySymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(status == .working ? Color.amber : Color.onBrand)
                    .frame(width: 28, height: 28)
                    .background(status == .working ? Color.primary.opacity(0.1) : Color.brand, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("\(tracker.primaryActionTitle(for: job)) (⇧⌘S)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }
}
