import unittest

from rolltag_sidecar.suggest import _http_error_message, build_prompt, parse_tags


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

    def test_prompt_includes_context_when_present(self):
        prompt = build_prompt(
            {"categories": []},
            {
                "filename": "DJI_0029.MP4",
                "relative_path": "malaysia/DJI_0029.MP4",
                "warehouse_name": "Travel",
                "gps": {"latitude": 1.3, "longitude": 103.8},
            },
        )
        self.assertIn("CATALOG:", prompt)
        self.assertIn("CONTEXT:", prompt)
        self.assertIn("DJI_0029.MP4", prompt)
        self.assertIn("103.8", prompt)

    def test_prompt_omits_context_block_when_missing(self):
        prompt = build_prompt({"categories": []})
        self.assertIn("CATALOG:", prompt)
        self.assertNotIn("CONTEXT:", prompt)

    def test_http_error_uses_gemini_message(self):
        body = '{"error":{"code":404,"message":"This model models/gemini-2.5-flash-lite is no longer available to new users.","status":"NOT_FOUND"}}'
        self.assertIn("no longer available", _http_error_message(404, body))
        self.assertNotIn("http_404", _http_error_message(404, body))


if __name__ == "__main__":
    unittest.main()
