import Foundation

struct ScanProgress: Equatable {
    enum Phase: String, Equatable {
        case scanning
        case identifying
        case analyzing
        case tagging
        case finishing
    }

    var warehouseName: String
    var warehouseID: UUID?
    var phase: Phase
    var currentFile: String
    var completed: Int
    var total: Int

    var phaseFraction: Double? {
        guard total > 0 else { return nil }
        return min(1, Double(completed) / Double(max(total, 1)))
    }

    var overallFraction: Double {
        let phaseShare: Double
        switch phase {
        case .scanning:
            return min(0.08, Double(completed) * 0.0004)
        case .identifying:
            phaseShare = 0.08 + 0.42 * (phaseFraction ?? 0)
        case .analyzing:
            phaseShare = 0.50 + 0.48 * (phaseFraction ?? 0)
        case .tagging:
            return phaseFraction ?? 0
        case .finishing:
            phaseShare = 0.99
        }
        return min(1, phaseShare)
    }

    var percentInt: Int {
        Int((overallFraction * 100).rounded())
    }
}
