import unittest

from rolltag_sidecar.suggest import (
    _http_error_message,
    build_prompt,
    parse_tags,
    parsed_retry_delay,
    pick_frames,
    should_retry,
)


class SuggestTests(unittest.TestCase):
    def test_parse_json_object(self):
        tags = parse_tags('{"tags":[{"category":"nature","value":"ocean"},{"category":"mood","value":"calm"}]}')
        self.assertEqual(
            tags,
            [
                {"category": "nature", "value": "ocean"},
                {"category": "mood", "value": "calm"},
            ],
        )

    def test_parse_fenced_and_dedupe(self):
        tags = parse_tags(
            """```json
            {"tags":[
              {"category":"nature","value":"ocean"},
              {"category":"nature","value":"ocean"},
              {"category":"","value":"skip"}
            ]}
            ```"""
        )
        self.assertEqual(tags, [{"category": "nature", "value": "ocean"}])

    def test_parse_garbage(self):
        self.assertEqual(parse_tags("not json"), [])

    def test_prompt_omits_context_block_when_missing(self):
        prompt = build_prompt({"categories": []})
        self.assertIn("CATALOG:", prompt)
        self.assertNotIn("CONTEXT:", prompt)
        self.assertNotIn("EXAMPLES:", prompt)

    def test_prompt_includes_examples(self):
        prompt = build_prompt(
            {"categories": []},
            None,
            [
                {
                    "ai": [{"category": "nature", "value": "ocean"}],
                    "kept": [{"category": "nature", "value": "lake"}],
                }
            ],
        )
        self.assertIn("EXAMPLES:", prompt)
        self.assertIn("ocean", prompt)
        self.assertIn("lake", prompt)

    def test_prompt_includes_context_when_present(self):
        prompt = build_prompt(
            {"categories": []},
            {
                "filename": "DJI_0029.MP4",
                "relative_path": "malaysia/DJI_0029.MP4",
                "warehouse_name": "Travel",
                "gps": {"latitude": 1.3, "longitude": 103.8},
                "place": "Johor Bahru, Johor, Malaysia",
            },
        )
        self.assertIn("CATALOG:", prompt)
        self.assertIn("CONTEXT:", prompt)
        self.assertIn("DJI_0029.MP4", prompt)
        self.assertIn("103.8", prompt)
        self.assertIn("Johor Bahru", prompt)
        self.assertIn("place field", prompt)
        self.assertIn("Folder and path names are hints only", prompt)

    def test_prompt_includes_getty_keywords(self):
        prompt = build_prompt({"categories": []})
        self.assertIn("keywords", prompt)
        self.assertIn("Getty/Pond5", prompt)

    def test_prompt_does_not_apply_personal_names_from_context(self):
        prompt = build_prompt({"categories": []})
        self.assertIn("Do not invent personal names", prompt)
        self.assertIn("Seeing a person is not enough", prompt)

    def test_prompt_requires_exact_people_count(self):
        prompt = build_prompt({"categories": []})
        self.assertIn("people/none", prompt)
        self.assertIn("people/one", prompt)
        self.assertIn("people/two", prompt)
        self.assertIn("exactly one", prompt)

    def test_prompt_ignores_toys_and_calendar_from_date(self):
        prompt = build_prompt({"categories": []})
        self.assertIn("Plush toys", prompt)
        self.assertIn("month or weekday", prompt)
        self.assertIn("not live animals", prompt)
        self.assertIn("those detections are live animals", prompt)

    def test_prompt_follows_on_device_vision_facts(self):
        prompt = build_prompt(
            {"categories": []},
            {"vision": {"people": "none", "people_count": 0, "hands": False, "face": "none"}},
        )
        self.assertIn("CONTEXT.vision", prompt)
        self.assertIn("on-device Vision", prompt)
        self.assertIn('"people": "none"', prompt)

    def test_parse_keywords(self):
        from rolltag_sidecar.suggest import parse_keywords

        keywords = parse_keywords(
            '{"tags":[{"category":"nature","value":"ocean"}],"keywords":["Icebreaker","arctic ocean","ab","nope!!!"]}'
        )
        self.assertEqual(keywords, ["icebreaker", "arctic ocean"])

    def test_http_error_uses_gemini_message(self):
        body = '{"error":{"code":404,"message":"This model models/gemini-2.5-flash-lite is no longer available to new users.","status":"NOT_FOUND"}}'
        self.assertIn("no longer available", _http_error_message(404, body))
        self.assertNotIn("http_404", _http_error_message(404, body))

    def test_should_retry_rate_limits_not_not_found(self):
        self.assertTrue(should_retry(429, ""))
        self.assertTrue(should_retry(503, ""))
        self.assertTrue(should_retry(400, '{"error":{"status":"RESOURCE_EXHAUSTED"}}'))
        self.assertFalse(should_retry(404, body='{"error":{"status":"NOT_FOUND"}}'))
        self.assertFalse(should_retry(401, ""))

    def test_parsed_retry_delay_reads_gemini_details(self):
        body = '{"error":{"details":[{"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"8s"}]}}'
        self.assertEqual(parsed_retry_delay(body), 8.0)
        self.assertIsNone(parsed_retry_delay("not json"))

    def test_pick_frames_keeps_start_mid_end(self):
        frames = ["a", "b", "c", "d", "e", "f"]
        self.assertEqual(pick_frames(frames, 3), ["a", "c", "f"])
        self.assertEqual(pick_frames(frames, 6), frames)
        self.assertEqual(pick_frames(["only"], 3), ["only"])


if __name__ == "__main__":
    unittest.main()
