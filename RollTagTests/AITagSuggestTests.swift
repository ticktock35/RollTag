import XCTest
@testable import RollTag

final class AITagSuggestTests: XCTestCase {
    func testParseJSONObject() {
        let tags = AITagSuggest.parseTags(
            #"{"tags":[{"category":"nature","value":"ocean"},{"category":"mood","value":"calm"}]}"#
        )
        XCTAssertEqual(
            tags,
            [
                AITagRef(category: "nature", value: "ocean"),
                AITagRef(category: "mood", value: "calm"),
            ]
        )
    }

    func testParseFencedAndDedupe() {
        let tags = AITagSuggest.parseTags(
            """
            ```json
            {"tags":[
              {"category":"nature","value":"ocean"},
              {"category":"nature","value":"ocean"},
              {"category":"","value":"skip"}
            ]}
            ```
            """
        )
        XCTAssertEqual(tags, [AITagRef(category: "nature", value: "ocean")])
    }

    func testParseGarbage() {
        XCTAssertEqual(AITagSuggest.parseTags("not json"), [])
    }

    func testPromptOmitsContextBlockWhenMissing() {
        let prompt = AITagSuggest.buildPrompt(catalog: ["categories": []])
        XCTAssertTrue(prompt.contains("CATALOG:"))
        XCTAssertFalse(prompt.contains("CONTEXT:"))
        XCTAssertFalse(prompt.contains("EXAMPLES:"))
    }

    func testPromptIncludesExamples() {
        let prompt = AITagSuggest.buildPrompt(
            catalog: ["categories": []],
            examples: [
                [
                    "ai": [["category": "nature", "value": "ocean"]],
                    "kept": [["category": "nature", "value": "lake"]],
                ],
            ]
        )
        XCTAssertTrue(prompt.contains("EXAMPLES:"))
        XCTAssertTrue(prompt.contains("ocean"))
        XCTAssertTrue(prompt.contains("lake"))
    }

    func testPromptIncludesContextWhenPresent() {
        let prompt = AITagSuggest.buildPrompt(
            catalog: ["categories": []],
            context: [
                "filename": "DJI_0029.MP4",
                "relative_path": "malaysia/DJI_0029.MP4",
                "warehouse_name": "Travel",
                "gps": ["latitude": 1.3, "longitude": 103.8],
                "place": "Johor Bahru, Johor, Malaysia",
            ]
        )
        XCTAssertTrue(prompt.contains("CATALOG:"))
        XCTAssertTrue(prompt.contains("CONTEXT:"))
        XCTAssertTrue(prompt.contains("DJI_0029.MP4"))
        XCTAssertTrue(prompt.contains("103.8"))
        XCTAssertTrue(prompt.contains("Johor Bahru"))
        XCTAssertTrue(prompt.contains("place field"))
        XCTAssertTrue(prompt.contains("Folder and path names are hints only"))
    }

    func testPromptIncludesGettyKeywords() {
        let prompt = AITagSuggest.buildPrompt(catalog: ["categories": []])
        XCTAssertTrue(prompt.contains("keywords"))
        XCTAssertTrue(prompt.contains("Getty/Pond5"))
    }

    func testPromptDoesNotApplyPersonalNamesFromContext() {
        let prompt = AITagSuggest.buildPrompt(catalog: ["categories": []])
        XCTAssertTrue(prompt.contains("Do not invent personal names"))
        XCTAssertTrue(prompt.contains("Seeing a person is not enough"))
    }

    func testPromptRequiresExactPeopleCount() {
        let prompt = AITagSuggest.buildPrompt(catalog: ["categories": []])
        XCTAssertTrue(prompt.contains("people/none"))
        XCTAssertTrue(prompt.contains("people/one"))
        XCTAssertTrue(prompt.contains("people/two"))
        XCTAssertTrue(prompt.contains("exactly one"))
    }

    func testPromptIgnoresToysAndCalendarFromDate() {
        let prompt = AITagSuggest.buildPrompt(catalog: ["categories": []])
        XCTAssertTrue(prompt.contains("Plush toys"))
        XCTAssertTrue(prompt.contains("month or weekday"))
        XCTAssertTrue(prompt.contains("not live animals"))
        XCTAssertTrue(prompt.contains("those detections are live animals"))
    }

    func testPromptFollowsOnDeviceVisionFacts() {
        let prompt = AITagSuggest.buildPrompt(
            catalog: ["categories": []],
            context: [
                "vision": [
                    "people": "none",
                    "people_count": 0,
                    "hands": false,
                    "face": "none",
                ] as [String: Any],
            ]
        )
        XCTAssertTrue(prompt.contains("CONTEXT.vision"))
        XCTAssertTrue(prompt.contains("on-device Vision"))
        XCTAssertTrue(prompt.contains("\"people\": \"none\""))
    }

    func testParseKeywords() {
        let keywords = AITagSuggest.parseKeywords(
            #"{"tags":[{"category":"nature","value":"ocean"}],"keywords":["Icebreaker","arctic ocean","ab","nope!!!"]}"#
        )
        XCTAssertEqual(keywords, ["icebreaker", "arctic ocean"])
    }

    func testHTTPErrorUsesGeminiMessage() {
        let body =
            #"{"error":{"code":404,"message":"This model models/gemini-2.5-flash-lite is no longer available to new users.","status":"NOT_FOUND"}}"#
        XCTAssertTrue(AITagSuggest.httpErrorMessage(status: 404, body: body).contains("no longer available"))
        XCTAssertFalse(AITagSuggest.httpErrorMessage(status: 404, body: body).contains("http_404"))
    }

    func testShouldRetryRateLimitsNotNotFound() {
        XCTAssertTrue(AITagSuggest.shouldRetry(status: 429, body: ""))
        XCTAssertTrue(AITagSuggest.shouldRetry(status: 503, body: ""))
        XCTAssertTrue(AITagSuggest.shouldRetry(status: 400, body: #"{"error":{"status":"RESOURCE_EXHAUSTED"}}"#))
        XCTAssertFalse(AITagSuggest.shouldRetry(status: 404, body: #"{"error":{"status":"NOT_FOUND"}}"#))
        XCTAssertFalse(AITagSuggest.shouldRetry(status: 401, body: ""))
    }

    func testParsedRetryDelayReadsGeminiDetails() {
        let body = #"{"error":{"details":[{"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"8s"}]}}"#
        XCTAssertEqual(AITagSuggest.parsedRetryDelay(body), 8.0)
        XCTAssertNil(AITagSuggest.parsedRetryDelay("not json"))
    }

    func testGeminiPayloadOmitsDeprecatedSamplingAndThinkingBudget() {
        let payload = AITagSuggest.geminiPayload(prompt: "tag this", frames: ["aaa"])
        let config = payload["generationConfig"] as? [String: Any]
        XCTAssertEqual(config?["responseMimeType"] as? String, "application/json")
        let forbidden = [
            "temperature", "topP", "topK", "top_p", "top_k",
            "thinkingBudget", "thinking_budget", "thinkingConfig",
            "thinking_level", "thinkingLevel",
        ]
        for key in forbidden {
            XCTAssertNil(config?[key], key)
            XCTAssertNil(payload[key], key)
        }
        let contents = payload["contents"] as? [[String: Any]]
        let parts = contents?.first?["parts"] as? [[String: Any]]
        let inline = parts?.dropFirst().first?["inlineData"] as? [String: Any]
        XCTAssertEqual(inline?["data"] as? String, "aaa")
    }

    func testPickFramesKeepsStartMidEnd() {
        let frames = ["a", "b", "c", "d", "e", "f"]
        XCTAssertEqual(AITagSuggest.pickFrames(frames, limit: 3), ["a", "c", "f"])
        XCTAssertEqual(AITagSuggest.pickFrames(frames, limit: 6), frames)
        XCTAssertEqual(AITagSuggest.pickFrames(["only"], limit: 3), ["only"])
    }

    func testPythonRoundHalfToEven() {
        XCTAssertEqual(AITagSuggest.pythonRound(2.5), 2)
        XCTAssertEqual(AITagSuggest.pythonRound(3.5), 4)
        XCTAssertEqual(AITagSuggest.pythonRound(5), 5)
    }
}
