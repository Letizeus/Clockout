import SwiftUI

/// Horizontal bar showing work blocks and breaks across the hours of a day.
struct DayTimelineView: View {
    let day: Date
    let report: DayReport
    let now: Date

    private struct Scale {
        let start: Date
        let end: Date

        func x(_ date: Date, width: CGFloat) -> CGFloat {
            let fraction = date.timeIntervalSince(start) / end.timeIntervalSince(start)
            return CGFloat(min(max(fraction, 0), 1)) * width
        }
    }

    var body: some View {
        let calendar = Calendar.app
        let dayStart = calendar.startOfDay(for: day)
        let hours = hourRange(dayStart: dayStart)
        let scale = Scale(
            start: dayStart.addingTimeInterval(TimeInterval(hours.lowerBound) * 3600),
            end: dayStart.addingTimeInterval(TimeInterval(hours.upperBound) * 3600)
        )
        let labelStep = hours.count > 15 ? 2 : 1
        let showsNow = calendar.isDate(now, inSameDayAs: day) && now > scale.start && now < scale.end

        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.surfaceRaised)

                    ForEach(Array(stride(from: hours.lowerBound + 1, to: hours.upperBound, by: 1)), id: \.self) { hour in
                        Rectangle()
                            .fill(Color.hairline)
                            .frame(width: 1)
                            .offset(x: scale.x(dayStart.addingTimeInterval(TimeInterval(hour) * 3600), width: width))
                    }

                    ForEach(report.breakIntervals, id: \.self) { interval in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.amber.opacity(0.35))
                            .frame(width: max(2, scale.x(interval.end, width: width) - scale.x(interval.start, width: width)))
                            .padding(.vertical, 7)
                            .offset(x: scale.x(interval.start, width: width))
                            .help(Text("Break \(interval.start.clockTime) to \(interval.end.clockTime), \(interval.duration.clock) h"))
                    }

                    ForEach(report.workIntervals, id: \.self) { interval in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.brand)
                            .frame(width: max(3, scale.x(interval.end, width: width) - scale.x(interval.start, width: width)))
                            .padding(.vertical, 3)
                            .offset(x: scale.x(interval.start, width: width))
                            .help(Text("Work \(interval.start.clockTime) to \(interval.end.clockTime), \(interval.duration.clock) h"))
                    }

                    if showsNow {
                        Capsule()
                            .fill(Color.primary.opacity(0.7))
                            .frame(width: 1.5)
                            .offset(x: scale.x(now, width: width) - 0.75)
                    }
                }
            }
            .frame(height: 26)

            GeometryReader { proxy in
                ForEach(Array(stride(from: hours.lowerBound, through: hours.upperBound, by: labelStep)), id: \.self) { hour in
                    Text(String(format: "%02d", hour % 24))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .position(
                            x: CGFloat(hour - hours.lowerBound) / CGFloat(hours.upperBound - hours.lowerBound) * proxy.size.width,
                            y: 6
                        )
                }
            }
            .frame(height: 12)
            .padding(.horizontal, 2)

            HStack(spacing: 14) {
                legend(color: .brand, title: "Work")
                legend(color: .amber.opacity(0.5), title: "Break")
                if showsNow {
                    legend(color: .primary.opacity(0.7), title: "Now")
                }
            }
            .font(AppFont.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func legend(color: Color, title: LocalizedStringResource) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
        }
    }

    /// At least 07:00 to 19:00, extended to include every block.
    private func hourRange(dayStart: Date) -> ClosedRange<Int> {
        var lower = 7
        var upper = 19
        if let first = report.firstStart {
            lower = min(lower, Int(first.timeIntervalSince(dayStart) / 3600))
        }
        if let last = report.lastEnd {
            upper = max(upper, Int((last.timeIntervalSince(dayStart) / 3600).rounded(.up)))
        }
        return max(0, lower)...min(max(upper, lower + 1), 48)
    }
}
