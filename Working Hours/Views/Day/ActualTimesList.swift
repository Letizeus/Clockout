import SwiftData
import SwiftUI

/// The real work blocks of a day, with the breaks between them.
struct ActualTimesList: View {
    let sessions: [WorkSession]
    let now: Date
    let onEdit: (WorkSession) -> Void

    @Environment(TimeTracker.self) private var tracker
    @State private var pendingDeletion: WorkSession?

    private enum Row: Identifiable {
        case session(WorkSession, number: Int)
        case gap(WorkInterval)

        var id: AnyHashable {
            switch self {
            case .session(let session, _): AnyHashable(session.persistentModelID)
            case .gap(let interval): AnyHashable(interval)
            }
        }
    }

    private var rows: [Row] {
        var result: [Row] = []
        var latestEnd: Date?
        for (index, session) in sessions.enumerated() {
            if let latestEnd, session.start > latestEnd {
                result.append(.gap(WorkInterval(start: latestEnd, end: session.start)))
            }
            result.append(.session(session, number: index + 1))
            let end = session.interval(now: now).end
            latestEnd = max(latestEnd ?? end, end)
        }
        return result
    }

    var body: some View {
        let rows = self.rows

        VStack(spacing: 0) {
            if rows.isEmpty {
                EmptyState(
                    systemImage: "clock",
                    title: "No work blocks",
                    message: "Start the timer or add a work block."
                )
            } else {
                ForEach(rows) { row in
                    switch row {
                    case .session(let session, let number):
                        SessionRow(
                            session: session,
                            number: number,
                            now: now,
                            onEdit: { onEdit(session) },
                            onDelete: { pendingDeletion = session }
                        )
                    case .gap(let interval):
                        BreakRow(interval: interval)
                    }
                    if row.id != rows.last?.id {
                        Rectangle()
                            .fill(Color.hairline)
                            .frame(height: 1)
                    }
                }
            }
        }
        .card(padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .confirmationDialog(
            "Delete Work Block?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { session in
            Button("Delete Work Block", role: .destructive) {
                tracker.delete(session)
            }
        } message: { session in
            Text("The work block from \(session.start.clockTime) can’t be restored.")
        }
    }
}

private struct SessionRow: View {
    let session: WorkSession
    let number: Int
    let now: Date
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        let duration = session.duration(now: now)

        HStack(spacing: 10) {
            Image(systemName: session.isRunning ? "circle.inset.filled" : "circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(session.isRunning ? Color.brand : Color.secondary.opacity(0.6))
                .frame(width: 16)
                .help(session.isRunning ? Text("Running") : Text("Block \(number)"))

            Text(rangeText)
                .font(AppFont.bodyMedium.monospacedDigit())

            if !session.note.isEmpty {
                Text(session.note)
                    .font(AppFont.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(session.isRunning ? duration.stopwatch : "\(duration.clock) h")
                .font(AppFont.body.monospacedDigit())
                .foregroundStyle(session.isRunning ? Color.brand : Color.secondary)
                .frame(width: RowLayout.durationWidth, alignment: .trailing)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.ghost)
            .frame(width: RowLayout.actionWidth)
            .opacity(isHovered ? 1 : 0)
            .help("Edit")
        }
        .padding(.leading, 14)
        .padding(.trailing, RowLayout.trailingPadding)
        .frame(minHeight: 40)
        .background(isHovered ? Color.primary.opacity(0.025) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button("Edit…", systemImage: "pencil", action: onEdit)
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var rangeText: String {
        guard let end = session.end else { return String(localized: "\(session.start.clockTime) until now") }
        let nextDay = Calendar.app.isDate(end, inSameDayAs: session.start) ? "" : " " + String(localized: "(+1 day)")
        return String(localized: "\(session.start.clockTime) to \(end.clockTime)\(nextDay)")
    }
}

private struct BreakRow: View {
    let interval: WorkInterval

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pause")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.amber)
                .frame(width: 16)
            Text("Break \(interval.start.clockTime) to \(interval.end.clockTime)")
                .font(AppFont.label.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(interval.duration.clock) h")
                .font(AppFont.label.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: RowLayout.durationWidth, alignment: .trailing)
            // Same slot as the edit button in block rows, so the durations line up.
            Color.clear
                .frame(width: RowLayout.actionWidth, height: 1)
        }
        .padding(.leading, 14)
        .padding(.trailing, RowLayout.trailingPadding)
        .frame(minHeight: 30)
        .background(Color.surfaceRaised.opacity(0.45))
    }
}

/// Shared trailing columns of block and break rows.
private enum RowLayout {
    static let durationWidth: CGFloat = 72
    static let actionWidth: CGFloat = 26
    static let trailingPadding: CGFloat = 8
}

/// Quiet placeholder for empty lists.
struct EmptyState: View {
    let systemImage: String
    let title: LocalizedStringResource
    let message: LocalizedStringResource

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)
            Text(title)
                .font(AppFont.bodyMedium)
            Text(message)
                .font(AppFont.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }
}
