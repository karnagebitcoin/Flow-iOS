import SwiftUI

struct CompactMediaAttachmentPreview: View {
    private enum Kind {
        case image
        case video
        case audio
        case file

        var iconName: String {
            switch self {
            case .image:
                return "photo"
            case .video:
                return "video"
            case .audio:
                return "waveform"
            case .file:
                return "paperclip"
            }
        }

        var badgeTitle: String? {
            switch self {
            case .image:
                return nil
            case .video:
                return "Video"
            case .audio:
                return "Audio"
            case .file:
                return "File"
            }
        }
    }

    static let thumbnailWidth: CGFloat = 108
    static let thumbnailHeight: CGFloat = 88

    let url: URL
    let mimeType: String
    let colorScheme: ColorScheme

    private var kind: Kind {
        let normalizedMIMEType = mimeType.lowercased()
        let path = url.path.lowercased()

        if normalizedMIMEType.hasPrefix("image/") || [".jpg", ".jpeg", ".png", ".webp", ".gif", ".heic", ".bmp", ".svg"].contains(where: path.hasSuffix) {
            return .image
        }
        if normalizedMIMEType.hasPrefix("video/") || [".mp4", ".mov", ".m4v", ".webm", ".mkv"].contains(where: path.hasSuffix) {
            return .video
        }
        if normalizedMIMEType.hasPrefix("audio/") || [".mp3", ".m4a", ".aac", ".wav", ".ogg"].contains(where: path.hasSuffix) {
            return .audio
        }
        return .file
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            previewContent

            if let badgeTitle = kind.badgeTitle {
                HStack(spacing: 4) {
                    Image(systemName: kind.iconName)
                        .font(.system(size: 10, weight: .semibold))
                    Text(badgeTitle)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(8)
            }
        }
        .frame(width: Self.thumbnailWidth, height: Self.thumbnailHeight)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.2), lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch kind {
        case .image:
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    progressPlaceholder
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholder(iconName: kind.iconName)
                @unknown default:
                    placeholder(iconName: kind.iconName)
                }
            }
        case .video, .audio, .file:
            placeholder(iconName: kind.iconName)
        }
    }

    private var progressPlaceholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
            ProgressView()
                .controlSize(.small)
        }
    }

    private func placeholder(iconName: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.secondarySystemFill),
                    Color(.tertiarySystemFill)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: iconName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
