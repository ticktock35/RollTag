import SwiftUI

enum AppFontSize {
    static let minStep = -2
    static let maxStep = 3
    static let defaultStep = 0
    static let defaultPoints: CGFloat = 13

    static func clamped(_ step: Int) -> Int {
        min(maxStep, max(minStep, step))
    }

    static func points(_ step: Int) -> CGFloat {
        defaultPoints + CGFloat(clamped(step)) * 2
    }

    static func localizationKey(_ step: Int) -> String {
        switch clamped(step) {
        case -2: return "settings.fontSize.small"
        case -1: return "settings.fontSize.medium"
        case 0: return "settings.fontSize.default"
        case 1: return "settings.fontSize.large"
        case 2: return "settings.fontSize.larger"
        default: return "settings.fontSize.largest"
        }
    }
}

struct RollTagFonts: Equatable {
    var size: CGFloat

    var body: Font { .system(size: size) }
    var callout: Font { .system(size: size, weight: .medium) }
    var caption: Font { .system(size: max(10, size - 2)) }
    var caption2: Font { .system(size: max(9, size - 3), weight: .semibold) }
    var headline: Font { .system(size: size + 1, weight: .semibold) }
    var title3: Font { .system(size: size + 5, weight: .semibold) }
    var title2: Font { .system(size: size + 7, weight: .semibold) }
}

private struct RollTagFontsKey: EnvironmentKey {
    static let defaultValue = RollTagFonts(size: AppFontSize.defaultPoints)
}

extension EnvironmentValues {
    var rollTagFonts: RollTagFonts {
        get { self[RollTagFontsKey.self] }
        set { self[RollTagFontsKey.self] = newValue }
    }
}

extension View {
    func rollTagFontSize(_ step: Int) -> some View {
        let fonts = RollTagFonts(size: AppFontSize.points(step))
        return self
            .environment(\.rollTagFonts, fonts)
            .environment(\.font, fonts.body)
    }
}
