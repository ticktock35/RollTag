import Foundation

final class AITagClient {
    private let session: URLSession
    private var suggestTask: Task<[String: Any], Error>?
    private var suggestGeneration = 0

    init(session: URLSession = AITagClient.makeSession()) {
        self.session = session
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 90
        return URLSession(configuration: configuration)
    }

    func suggestTags(
        provider: AIProvider,
        apiKey: String,
        model: String,
        frames: [Data],
        catalog: [String: Any],
        context: [String: Any] = [:],
        examples: [AITaggingExample] = []
    ) async throws -> [String: Any] {
        guard !apiKey.isEmpty else { throw AITagError.missingAPIKey }
        guard !frames.isEmpty else { throw AITagError.missingFrames }
        let encoded = frames.map { $0.base64EncodedString() }
        let prompt = AITagSuggest.buildPrompt(
            catalog: catalog,
            context: context.isEmpty ? nil : context,
            examples: AITaggingExample.payloadList(examples)
        )
        suggestGeneration += 1
        let token = suggestGeneration
        let task = Task { () -> [String: Any] in
            let text: String
            switch provider {
            case .gemini:
                text = try await gemini(
                    apiKey: apiKey,
                    model: model.isEmpty ? AITagSuggest.defaultGeminiModel : model,
                    prompt: prompt,
                    frames: AITagSuggest.pickFrames(encoded, limit: AITagSuggest.geminiFrameLimit)
                )
            case .openai:
                text = try await openai(
                    apiKey: apiKey,
                    model: model.isEmpty ? AITagSuggest.defaultOpenAIModel : model,
                    prompt: prompt,
                    frames: encoded
                )
            default:
                throw AITagError.unsupportedProvider
            }
            return [
                "tags": AITagSuggest.parseTags(text).map(\.payload),
                "keywords": AITagSuggest.parseKeywords(text),
                "provider": provider.rawValue,
                "model": model,
            ]
        }
        suggestTask = task
        defer {
            if suggestGeneration == token {
                suggestTask = nil
            }
        }
        do {
            return try await task.value
        } catch {
            if AITaggingStop.isCancellation(error) {
                throw CancellationError()
            }
            throw error
        }
    }

    func cancelInFlightSuggest() {
        suggestGeneration += 1
        suggestTask?.cancel()
        suggestTask = nil
    }

    private func gemini(apiKey: String, model: String, prompt: String, frames: [String]) async throws -> String {
        let payload = AITagSuggest.geminiPayload(prompt: prompt, frames: frames)
        let url = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        )!
        let data = try await postJSON(url: url, payload: payload, headers: ["Content-Type": "application/json"], retries: 1)
        return try AITagSuggest.geminiText(from: data)
    }

    private func openai(apiKey: String, model: String, prompt: String, frames: [String]) async throws -> String {
        let payload = AITagSuggest.openaiPayload(prompt: prompt, model: model, frames: frames)
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        let data = try await postJSON(
            url: url,
            payload: payload,
            headers: [
                "Content-Type": "application/json",
                "Authorization": "Bearer \(apiKey)",
            ],
            retries: 2
        )
        return try AITagSuggest.openaiText(from: data)
    }

    private func postJSON(
        url: URL,
        payload: [String: Any],
        headers: [String: String],
        retries: Int
    ) async throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: payload)
        var lastError: Error = AITagError.requestFailed("request_failed")
        for attempt in 0..<retries {
            try Task.checkCancellation()
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body
            request.timeoutInterval = 90
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(status) {
                    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw AITagError.requestFailed("cannot_parse_response")
                    }
                    return object
                }
                let raw = String(data: data, encoding: .utf8) ?? ""
                lastError = AITagError.requestFailed(AITagSuggest.httpErrorMessage(status: status, body: raw))
                if attempt + 1 < retries, AITagSuggest.shouldRetry(status: status, body: raw) {
                    let nanoseconds = UInt64(AITagSuggest.retrySeconds(status: status, body: raw, attempt: attempt) * 1_000_000_000)
                    try await Task.sleep(nanoseconds: nanoseconds)
                    continue
                }
                throw lastError
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as AITagError {
                throw error
            } catch {
                if AITaggingStop.isCancellation(error) {
                    throw CancellationError()
                }
                lastError = AITagError.requestFailed(String((error.localizedDescription).prefix(200)).ifEmpty("network_error"))
                if attempt + 1 < retries {
                    let nanoseconds = UInt64(AITagSuggest.retrySeconds(status: 503, body: "", attempt: attempt) * 1_000_000_000)
                    try await Task.sleep(nanoseconds: nanoseconds)
                    continue
                }
                throw lastError
            }
        }
        throw lastError
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
