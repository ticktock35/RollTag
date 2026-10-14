import Foundation
import OnnxRuntimeBindings

final class JoyTagEngine: @unchecked Sendable {
    static let shared = JoyTagEngine()

    private let lock = NSLock()
    private var env: ORTEnv?
    private var session: ORTSession?
    private var tags: [String] = []
    private var inputName = "image"
    private var outputName = "tags"

    private init() {}

    func unload() {
        lock.lock()
        defer { lock.unlock() }
        session = nil
        env = nil
        tags = []
    }

    func suggest(frames: [Data]) throws -> [String: Any] {
        let picked = AITagSuggest.pickFrames(frames, limit: JoyTagStore.frameLimit)
        guard !picked.isEmpty else { throw AITagError.missingFrames }
        var merged: [String: Float] = [:]
        var names: [String] = []
        for jpeg in picked {
            let scored = try infer(jpeg)
            names = scored.names
            for (tag, score) in zip(scored.names, scored.scores) {
                merged[tag] = max(merged[tag] ?? 0, score)
            }
        }
        let scores = names.map { merged[$0] ?? 0 }
        return [
            "tags": [] as [[String: String]],
            "keywords": JoyTagTags.keywords(tags: names, scores: scores),
            "provider": AIProvider.joytag.rawValue,
            "model": "joytag",
        ]
    }

    private struct Scored {
        var names: [String]
        var scores: [Float]
    }

    private func infer(_ jpeg: Data) throws -> Scored {
        try loadIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        guard let session else { throw AITagError.requestFailed("joytag_session") }
        let tensor = try JoyTagImage.nchwTensor(from: jpeg)
        let size = JoyTagStore.imageSize
        let input = try ORTValue(
            tensorData: NSMutableData(data: tensor),
            elementType: .float,
            shape: [1, 3, size, size] as [NSNumber]
        )
        let outputs = try session.run(
            withInputs: [inputName: input],
            outputNames: Set([outputName]),
            runOptions: nil
        )
        guard let output = outputs[outputName] else {
            throw AITagError.requestFailed("joytag_output")
        }
        let data = try output.tensorData() as Data
        let count = data.count / MemoryLayout<Float>.size
        let scores = data.withUnsafeBytes { raw -> [Float] in
            let buffer = raw.bindMemory(to: Float.self)
            return Array(buffer.prefix(count))
        }
        let probabilities = Self.probabilities(scores)
        let n = min(tags.count, probabilities.count)
        return Scored(names: Array(tags.prefix(n)), scores: Array(probabilities.prefix(n)))
    }

    private func loadIfNeeded() throws {
        lock.lock()
        defer { lock.unlock() }
        if session != nil, !tags.isEmpty { return }
        guard JoyTagStore.isInstalled else { throw AITagError.requestFailed("joytag_missing_model") }
        tags = try JoyTagStore.loadTags()
        let env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try? options.setIntraOpNumThreads(2)
        let session = try ORTSession(env: env, modelPath: JoyTagStore.modelURL.path, sessionOptions: options)
        if let name = try session.inputNames().first {
            inputName = name
        }
        if let name = try session.outputNames().first {
            outputName = name
        }
        self.env = env
        self.session = session
    }

    static func probabilities(_ scores: [Float]) -> [Float] {
        let outsideUnit = scores.contains { $0 < 0 || $0 > 1 }
        guard outsideUnit else { return scores }
        return scores.map { 1 / (1 + exp(-$0)) }
    }
}
