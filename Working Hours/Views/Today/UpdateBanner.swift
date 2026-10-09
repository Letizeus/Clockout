import SwiftUI

/// Offers a newer version found by `UpdateChecker`.
struct UpdateBanner: View {
    var isCompact = false

    @Environment(UpdateChecker.self) private var updates

    var body: some View {
        if let release = updates.offeredRelease {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.brand)
                Text("Version \(release.version) is available.")
                    .font(AppFont.body)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Download") { updates.openDownloadPage(for: release) }
                    .buttonStyle(.secondary(height: 26))
                if !isCompact {
                    Button("Skip This Version") { updates.skip(release) }
                        .buttonStyle(.ghost)
                }
            }
            .card(padding: isCompact ? 10 : 12)
        }
    }
}
