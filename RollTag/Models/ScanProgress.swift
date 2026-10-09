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
    var currentProvider: String = ""
    var currentProviderID: String = ""
    var lastFileResult: String = ""

    var phaseFraction: Double? {
        guard total > 0 else { return nil }
        return min(1, Double(completed) / Double(max(total, 1)))
    }

    var overallFraction: Double {
        displayFraction ?? 0
    }

    var displayFraction: Double? {
        if phase == .scanning, total == 0 { return nil }
        guard let phaseFraction else { return nil }
        if phase == .scanning {
            return min(phaseFraction, 0.99)
        }
        return phaseFraction
    }

    var isScanningPastEstimate: Bool {
        phase == .scanning && total > 0 && completed >= total
    }

    var showsPercent: Bool { displayFraction != nil }

    var percentInt: Int {
        Int(((displayFraction ?? 0) * 100).rounded())
    }
}
