import AppKit
import Foundation
import SwiftData
import Testing
@testable import Working_Hours

@MainActor
struct JobIconTests {
    /// A wide JPEG: red on the left third, green in the middle, blue on the right.
    private func makeWideJPEG() throws -> Data {
        let width = 600, height = 300
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        for (index, color) in [CGColor(red: 1, green: 0, blue: 0, alpha: 1), CGColor(red: 0, green: 1, blue: 0, alpha: 1), CGColor(red: 0, green: 0, blue: 1, alpha: 1)].enumerated() {
            context.setFillColor(color)
            context.fill(CGRect(x: index * 200, y: 0, width: 200, height: height))
        }
        let image = try #require(context.makeImage())
        return try #require(NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [:]))
    }

    @Test func cropsTheCenterSquareAndScalesDown() throws {
        let icon = try #require(JobIconImage.makeIconData(from: makeWideJPEG()))
        let rep = try #require(NSBitmapImageRep(data: icon))

        #expect(rep.pixelsWide == JobIconImage.pixelSize)
        #expect(rep.pixelsHigh == JobIconImage.pixelSize)
        #expect(icon.starts(with: [0x89, 0x50, 0x4E, 0x47]))

        // The middle of the 600 x 300 picture is green; the crop keeps x 150 to 450.
        let center = try #require(rep.colorAt(x: 128, y: 128)?.usingColorSpace(.sRGB))
        #expect(center.greenComponent > 0.8 && center.redComponent < 0.2)
        let left = try #require(rep.colorAt(x: 10, y: 128)?.usingColorSpace(.sRGB))
        #expect(left.redComponent > 0.8)
    }

    @Test func rejectsDataThatIsNoImage() {
        #expect(JobIconImage.makeIconData(from: Data("kein Bild".utf8)) == nil)
    }

    @Test func readsPicturesFromFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        try makeWideJPEG().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let icon = try #require(JobIconImage.makeIconData(from: url))
        #expect(NSBitmapImageRep(data: icon)?.pixelsWide == JobIconImage.pixelSize)
    }

    @Test func iconIsStoredWithTheJob() throws {
        let container = try ModelContainer(for: WorkSession.self, Job.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let job = Job(name: "Café")
        container.mainContext.insert(job)
        job.iconData = JobIconImage.makeIconData(from: try makeWideJPEG())
        try container.mainContext.save()

        let fetched = try #require(try container.mainContext.fetch(FetchDescriptor<Job>()).first)
        #expect(fetched.iconData?.isEmpty == false)
    }
}
