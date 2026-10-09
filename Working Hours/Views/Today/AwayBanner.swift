import SwiftUI

/// Asks what to do with time nobody used the Mac while the timer was running.
struct AwayBanner: View {
    var isCompact = false

    @Environment(TimeTracker.self) private var tracker

    var body: some View {
        if let away = tracker.awayPeriod, tracker.runningSession != nil {
            let minutes = Int(away.duration / 60)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.amber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You were away for \(minutes) minutes")
                            .font(AppFont.bodyMedium)
                        Text("From \(away.start.clockTime) to \(away.end.clockTime), while the timer ran.")
                            .font(AppFont.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if isCompact {
                    // The menu bar window is narrow: one action per row.
                    VStack(spacing: 6) {
                        breakButton.frame(maxWidth: .infinity)
                        HStack(spacing: 6) {
                            stopButton(at: away.start).frame(maxWidth: .infinity)
                            continueButton
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        breakButton
                        stopButton(at: away.start)
                        Spacer()
                        continueButton
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 12)
        }
    }

    private var breakButton: some View {
        Button {
            tracker.takeAwayAsBreak()
        } label: {
            Text("Take Off as Break").frame(maxWidth: isCompact ? .infinity : nil)
        }
        .buttonStyle(.primary(tint: .brand, height: 28))
    }

    private func stopButton(at start: Date) -> some View {
        Button {
            tracker.stopAtAwayStart()
        } label: {
            Text("Finish day at \(start.clockTime)").frame(maxWidth: isCompact ? .infinity : nil)
        }
        .buttonStyle(.secondary(height: 28))
    }

    private var continueButton: some View {
        Button("Keep Counting") { tracker.dismissAway() }
            .buttonStyle(.ghost)
            .fixedSize()
    }
}
