import AppKit
import SwiftUI

struct FootageCell: View {
    let item: ScoredFootage
    let isSelected: Bool
    let warehouseRoot: URL?
    var thumbRefreshToken: Int = 0
    @State private var hovering = false
    @State private var playing = false
    @State private var liveThumb: NSImage?
    @State private var previewFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color(nsColor: .controlBackgroundColor)
                .overlay {
                    previewContent
                }
                .aspectRatio(previewAspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.black.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if hovering, item.footage.status == .available, item.footage.mediaKind.canHoverPlay, !item.footage.isTooSmallToPreview {
                    Button {
                        playing.toggle()
                    } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .font(.caption.weight(.semibold))
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.footage.filename)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if item.footage.status == .missing {
                    Text(String(localized: "inspector.status.missing"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Text(item.warehouseName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(6)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { value in
            hovering = value
            if !value { playing = false }
        }
        .help(item.footage.relativePath)
        .task(id: "\(item.id.uuidString)-\(thumbRefreshToken)") {
            liveThumb = nil
            previewFailed = false
            if item.footage.status == .missing {
                previewFailed = true
                return
            }
            guard item.footage.mediaKind != .audio, let warehouseRoot else { return }
            if item.footage.isTooSmallToPreview {
                previewFailed = true
                return
            }
            let url = item.footage.absoluteURL(warehouseRoot: warehouseRoot)
            let thumbURL = ThumbnailService.thumbnailFileURL(warehouseRoot: warehouseRoot, footageID: item.id)
            let image: NSImage?
            if item.footage.mediaKind == .image {
                image = await ThumbnailService.ensureImageThumbnail(
                    source: url,
                    thumbnailURL: thumbURL,
                    maxEdge: ThumbnailService.gridMaxEdge,
                    allowCreate: !ThumbnailService.deferGeneration
                )
            } else {
                image = await ThumbnailService.ensureVideoThumbnail(
                    source: url,
                    thumbnailURL: thumbURL,
                    maxEdge: ThumbnailService.gridMaxEdge,
                    allowCreate: !ThumbnailService.deferGeneration
                )
            }
            if let image {
                liveThumb = image
            } else {
                previewFailed = true
            }
        }
        .onDisappear {
            liveThumb = nil
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if hovering, playing, item.footage.status == .available, item.footage.mediaKind.canHoverPlay, !item.footage.isTooSmallToPreview, let warehouseRoot {
            HoverPlayerView(
                url: item.footage.absoluteURL(warehouseRoot: warehouseRoot),
                isPlaying: true,
                isMuted: item.footage.mediaKind == .video
            )
        } else if let shown = liveThumb {
            Image(nsImage: shown)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
        } else if item.footage.mediaKind == .audio {
            Image(systemName: placeholderIcon)
                .font(.title2)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 6) {
                if previewFailed {
                    Image(systemName: placeholderIcon)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(previewFailureText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private var previewAspect: CGFloat {
        if item.footage.mediaKind != .audio {
            if let shown = liveThumb, shown.size.width > 0, shown.size.height > 0 {
                return PreviewLayout.aspect(size: shown.size)
            }
            if let width = item.footage.width, let height = item.footage.height {
                return PreviewLayout.aspect(width: width, height: height)
            }
        }
        return PreviewLayout.videoFallback
    }

    private var placeholderIcon: String {
        if item.footage.status == .missing { return "eye.slash" }
        switch item.footage.mediaKind {
        case .image: return "photo"
        case .audio: return "speaker.wave.2"
        case .video: return "film"
        }
    }

    private var previewFailureText: String {
        if item.footage.status == .missing {
            return String(localized: "inspector.status.missing")
        }
        if item.footage.mediaKind == .image {
            return String(localized: "preview.unavailable")
        }
        if item.footage.isTooSmallToPreview {
            return String(
                format: String(localized: "preview.unavailable.incomplete"),
                locale: .current,
                ByteCountFormatter.string(fromByteCount: item.footage.size, countStyle: .file)
            )
        }
        return String(localized: "preview.unavailable.codec")
    }
}
