import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The job's picture, or its colored initial when it has none.
struct JobIcon: View {
    let job: Job
    var size: CGFloat = 28

    var body: some View {
        JobIconView(data: job.iconData, color: job.color, name: job.displayName, size: size)
    }
}

struct JobIconView: View {
    let data: Data?
    let color: JobColor
    let name: String
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let image = data.flatMap({ JobIconCache.image(for: $0) }) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(color.color)
                    .overlay {
                        Text(name.prefix(1).uppercased())
                            .font(.system(size: size * 0.48, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        }
    }
}

/// Decoding a PNG on every redraw (the sidebar updates each second) would be wasteful.
private enum JobIconCache {
    private static let cache = NSCache<NSData, NSImage>()

    static func image(for data: Data) -> NSImage? {
        let key = data as NSData
        if let image = cache.object(forKey: key) { return image }
        guard let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Preview with "choose" and "remove" buttons; a picture can also be dropped onto the preview.
struct JobIconPicker: View {
    @Binding var data: Data?
    let color: JobColor
    let name: String

    @State private var showsImporter = false
    @State private var isDropTargeted = false
    @State private var failed = false

    var body: some View {
        HStack(spacing: 14) {
            JobIconView(data: data, color: color, name: name, size: 48)
                .overlay {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: 12.5, style: .continuous)
                            .strokeBorder(Color.brand, lineWidth: 2)
                    }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    load(url)
                    return true
                } isTargeted: {
                    isDropTargeted = $0
                }
                .help("Drop a picture here")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Button(data == nil ? String(localized: "Choose Picture…") : String(localized: "Other Picture…")) {
                        showsImporter = true
                    }
                    if data != nil {
                        Button("Remove", role: .destructive) {
                            data = nil
                        }
                    }
                }
                Text(failed ? "This picture could not be read." : "PNG, JPEG or HEIC, cropped to a square.")
                    .font(.caption)
                    .foregroundStyle(failed ? Color.negative : Color.secondary)
            }
            Spacer(minLength: 0)
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { load(url) }
        }
    }

    private func load(_ url: URL) {
        if let icon = JobIconImage.makeIconData(from: url) {
            data = icon
            failed = false
        } else {
            failed = true
        }
    }
}
