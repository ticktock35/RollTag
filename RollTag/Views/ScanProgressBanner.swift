import SwiftUI

struct ScanProgressBanner: View {
    let progress: ScanProgress
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(phaseTitle)
                    .font(.headline)
                Spacer()
                Text("\(progress.percentInt)%")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(countText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(progress.warehouseName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !progress.currentFile.isEmpty {
                Text(progress.currentFile)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(progress.currentFile)
            }

            ProgressView(value: progress.phaseFraction == nil && progress.phase == .scanning ? nil : progress.overallFraction)
                .progressViewStyle(.linear)

            if model.showsAIStopButton {
                Button(String(localized: "ai.stop")) {
                    model.stopAITagging()
                }
                .disabled(!model.canStopAITagging)
                .help(String(localized: "ai.stop.help"))
                .accessibilityIdentifier("ai.stop")
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(14)
        .frame(maxWidth: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .padding(16)
        .accessibilityElement(children: model.showsAIStopButton ? .contain : .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var phaseTitle: String {
        switch progress.phase {
        case .scanning: String(localized: "progress.scanning")
        case .identifying: String(localized: "progress.identifying")
        case .analyzing: String(localized: "progress.analyzing")
        case .tagging: String(localized: "progress.tagging")
        case .finishing: String(localized: "progress.finishing")
        }
    }

    private var countText: String {
        if progress.phase == .scanning, progress.total == 0 {
            return String(format: String(localized: "progress.found"), locale: .current, progress.completed)
        }
        return String(format: String(localized: "progress.count"), locale: .current, progress.completed, max(progress.total, 0))
    }

    private var accessibilityText: String {
        "\(phaseTitle) \(progress.percentInt)% \(progress.currentFile)"
    }
}
