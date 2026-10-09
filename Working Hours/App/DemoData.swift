#if DEBUG
import AppKit
import Foundation
import SwiftData

/// Launch with `-demo` to get an in-memory store with two weeks of sample data
/// (handy for screenshots and UI work without touching real entries).
enum DemoData {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static func makeContainer() throws -> ModelContainer {
        let container = try ModelContainer(
            for: WorkSession.self, Job.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        seed(container.mainContext)
        return container
    }

    /// A cup on a warm background, so the demo shows a job with a picture.
    private static func sampleIcon() -> Data? {
        let size = NSSize(width: 300, height: 300)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(starting: .systemOrange, ending: .systemRed)?.draw(in: rect, angle: -60)
            let configuration = NSImage.SymbolConfiguration(pointSize: 150, weight: .semibold)
                .applying(.init(paletteColors: [.white]))
            if let symbol = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) {
                let symbolRect = NSRect(
                    x: (rect.width - symbol.size.width) / 2,
                    y: (rect.height - symbol.size.height) / 2,
                    width: symbol.size.width,
                    height: symbol.size.height
                )
                symbol.draw(in: symbolRect)
            }
            return true
        }
        guard let tiff = image.tiffRepresentation else { return nil }
        return JobIconImage.makeIconData(from: tiff)
    }

    private static func seed(_ context: ModelContext) {
        let calendar = Calendar.app
        let today = calendar.startOfDay(for: .now)

        let agency = Job(name: "Agentur", color: .blue, sortIndex: 0)
        agency.targetMode = .weekly
        agency.weeklyTargetMinutes = 30 * 60
        agency.workdayList = [2, 3, 4, 5, 6]
        agency.holidayRegion = HolidayRegion(country: .germany, state: .bavaria)
        let cafe = Job(name: "Café", color: .orange, sortIndex: 1)
        cafe.dailyTargetMinutes = 5 * 60
        cafe.workdayList = [7]
        cafe.roundingMinutes = 15
        cafe.iconData = sampleIcon()
        context.insert(agency)
        context.insert(cafe)
        let patterns: [[(Double, Double)]] = [
            [(8.05, 12.0), (12.5, 16.9)],
            [(7.75, 10.25), (10.4, 12.6), (13.1, 17.2)],
            [(8.5, 12.25), (12.75, 15.5), (19.0, 20.5)],
            [(9.0, 13.0), (13.6, 17.75)],
            [(8.25, 12.5), (13.0, 16.0)],
        ]

        for offset in 1...14 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if agency.isWorkday(day) {
                for (start, end) in patterns[offset % patterns.count] {
                    context.insert(WorkSession(start: day.addingTimeInterval(start * 3600), end: day.addingTimeInterval(end * 3600), jobID: agency.uuid))
                }
            } else if cafe.isWorkday(day) {
                context.insert(WorkSession(start: day.addingTimeInterval(10 * 3600), end: day.addingTimeInterval(15.25 * 3600), jobID: cafe.uuid))
            }
        }

        let now = Date.now
        let firstStart = max(today.addingTimeInterval(7.9 * 3600), now.addingTimeInterval(-5 * 3600))
        context.insert(WorkSession(start: firstStart, end: firstStart.addingTimeInterval(2.4 * 3600), note: "Sprint Planning", jobID: agency.uuid))
        context.insert(WorkSession(start: firstStart.addingTimeInterval(2.9 * 3600), note: "Code Review", jobID: agency.uuid))
    }
}
#endif
