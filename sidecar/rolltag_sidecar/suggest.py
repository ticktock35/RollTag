import json
import time
import urllib.error
import urllib.request
from typing import Optional

GEMINI_FRAME_LIMIT = 3
RETRYABLE_STATUS = {429, 500, 502, 503}

PROMPT = """You tag B-roll stills for a footage warehouse.
Choose 3 to 8 tags that clearly match the frames.
Use only category and value ids from the catalog JSON for "tags". Never invent catalog ids.
Custom tags (category "custom") may only name an object or sign that is clearly readable in THESE frames (a vessel, product, landmark text). Do not invent personal names. Do not apply a person's name from filename, folder, GPS, place, EXAMPLES, or other clips. Seeing a person is not enough. If unsure who it is, omit the name.
If CONTEXT is present, use filename, path, warehouse name, duration, file size, capture time, GPS, and place as hints for place and time tags. The place field is a reverse-geocoded locality from the file GPS. Folder and path names are hints only — never copy a folder name as a custom tag. The app writes CONTEXT.place parts (locality, region, country) as custom tags. Still add catalog place types that match (city, nature, rural, forest, ocean) when the location or frames support them. Frames remain primary. Do not turn a place hint into a person's name. Do not tag month or weekday names from captured_at (no march, friday).
If CONTEXT.vision is present, it is on-device Vision from this Mac (faces, bodies, hands, scene labels, animals, readable text). Treat people, people_count, hands, and face as facts:
- Set the people count tag to match vision.people. Do not override it from filename, folder, or guesses.
- If vision.people is none: use people/none only. Do not add portrait, distant, age, hands, or people keywords other than "no people".
- people/portrait only if vision.face is portrait. people/distant only if vision.face is distant.
- If vision.hands is true and people is not none, people/hands may apply.
- scenes and animals are hints, not catalog ids. Confirm them in the frames before tagging.
- If vision.animals is present and vision.people is none, those detections are live animals (dogs, cats), not humans. Do not add people tags or personal names.
- text is OCR of signs; a short readable token may become a custom tag. Do not treat OCR as a person's name.

People count is mandatory and must be exact:
- Look at every frame. Count only distinct living humans you can see (body or hands). Ignore statues, posters, mannequins, reflections, drawings, and maybe-shapes.
- Plush toys, stuffed animals, figurines, and dolls are not living humans and not live animals. Do not tag people/*, animals/pet, or an animal species for a toy.
- Always include exactly one of people/none, people/one, people/two, people/group, or people/crowd.
- people/none: no human in any frame. Default when unsure. Do not add portrait, crowd, distant, age tags, or keywords such as people, person, man, woman, crowd.
- people/one: exactly one person. Not group. Not crowd.
- people/two: exactly two people. Not one. Not group.
- people/group: about 3 to 10 people, not a dense crowd.
- people/crowd: many people filling the scene.
- people/portrait only if a face is the main subject. people/distant only if humans are small in the frame.
- Filename must not invent people.

Also return Getty/Pond5 English keywords in "keywords":
- lowercase, words separated by single spaces, no hashtags, no camelCase, no sentences
- 6 to 20 phrases, 1 to 5 words each
- include English for every non-English subject you name (icebreaker, not pinyin)
- use the catalog "en" names when they match what you see
- include no people, one person, or two people when that is what you see
- visible nouns, place, weather, people, shot; suitable for stock-footage search

If EXAMPLES are present, they are recent human outcomes: "ai" is what the model tagged, "kept" is what the user left after editing. Follow kept wording only when the current frames show the same subject. Do not copy personal names or custom labels onto unrelated scenes. Frames remain primary.

Return JSON: {"tags":[{"category":"...","value":"..."}],"keywords":["icebreaker","arctic ocean"]}

CATALOG:
"""


def build_prompt(catalog: dict, context: Optional[dict] = None, examples: Optional[list] = None) -> str:
    prompt = PROMPT + json.dumps(catalog, ensure_ascii=False)
    cleaned = _normalize_examples(examples)
    if cleaned:
        prompt += "\n\nEXAMPLES:\n" + json.dumps(cleaned, ensure_ascii=False)
    if context:
        prompt += "\n\nCONTEXT:\n" + json.dumps(context, ensure_ascii=False)
    return prompt


def _normalize_examples(examples) -> list:
    if not isinstance(examples, list):
        return []
    cleaned = []
    for item in examples[:8]:
        if not isinstance(item, dict):
            continue
        ai = _example_tags(item.get("ai"))
        kept = _example_tags(item.get("kept"))
        if not ai or not kept:
            continue
        cleaned.append({"ai": ai, "kept": kept})
    return cleaned


def _example_tags(items) -> list:
    if not isinstance(items, list):
        return []
    tags = []
    seen = set()
    for item in items:
        if not isinstance(item, dict):
            continue
        category = str(item.get("category") or "").strip()
        value = str(item.get("value") or "").strip()
        key = (category, value)
        if not category or not value or key in seen:
            continue
        seen.add(key)
        tags.append({"category": category, "value": value})
        if len(tags) >= 12:
            break
    return tags


def parse_tags(text: str) -> list:
    data = _parse_json(text)
    if data is None:
        return []
    items = data.get("tags") if isinstance(data, dict) else data
    if not isinstance(items, list):
        return []
    tags = []
    seen = set()
    for item in items:
        if not isinstance(item, dict):
            continue
        category = str(item.get("category") or "").strip()
        value = str(item.get("value") or "").strip()
        key = (category, value)
        if not category or not value or key in seen:
            continue
        seen.add(key)
        tags.append({"category": category, "value": value})
    return tags


def parse_keywords(text: str) -> list:
    data = _parse_json(text)
    if not isinstance(data, dict):
        return []
    items = data.get("keywords")
    if not isinstance(items, list):
        return []
    keywords = []
    seen = set()
    for item in items:
        if isinstance(item, str):
            raw = item
        elif isinstance(item, dict):
            raw = str(item.get("value") or item.get("keyword") or "")
        else:
            continue
        formatted = _stock_keyword(raw)
        if not formatted or formatted in seen or not _is_getty_keyword(formatted):
            continue
        seen.add(formatted)
        keywords.append(formatted)
        if len(keywords) >= 20:
            break
    return keywords


def _parse_json(text: str):
    if not text:
        return None
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.strip("`")
        if cleaned.lower().startswith("json"):
            cleaned = cleaned[4:].strip()
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        start = cleaned.find("{")
        end = cleaned.rfind("}")
        if start < 0 or end <= start:
            return None
        try:
            return json.loads(cleaned[start : end + 1])
        except json.JSONDecodeError:
            return None


def _stock_keyword(raw: str) -> str:
    trimmed = raw.replace("#", "").strip().lower()
    return " ".join(trimmed.split())


def _is_getty_keyword(text: str) -> bool:
    if not text or len(text) < 3 or len(text) > 40:
        return False
    words = text.split(" ")
    if not 1 <= len(words) <= 5:
        return False
    return all(part.isascii() and part.replace("-", "").isalnum() for part in words)


def suggest_tags(
    provider: str,
    api_key: str,
    model: str,
    frames: list,
    catalog: dict,
    context: Optional[dict] = None,
    examples: Optional[list] = None,
) -> dict:
    if not api_key:
        raise ValueError("missing_api_key")
    if not frames:
        raise ValueError("missing_frames")
    prompt = build_prompt(
        catalog,
        context if isinstance(context, dict) else None,
        examples if isinstance(examples, list) else None,
    )
    if provider == "gemini":
        text = _gemini(api_key, model or "gemini-3.5-flash-lite", prompt, pick_frames(frames, GEMINI_FRAME_LIMIT))
    elif provider == "openai":
        text = _openai(api_key, model or "gpt-4.1-mini", prompt, frames)
    else:
        raise ValueError("unsupported_provider")
    return {"tags": parse_tags(text), "keywords": parse_keywords(text), "provider": provider, "model": model}


def pick_frames(frames: list, limit: int) -> list:
    if limit <= 0 or len(frames) <= limit:
        return list(frames)
    if limit == 1:
        return [frames[len(frames) // 2]]
    step = (len(frames) - 1) / (limit - 1)
    return [frames[round(index * step)] for index in range(limit)]


def _gemini(api_key: str, model: str, prompt: str, frames: list) -> str:
    parts = [{"text": prompt}]
    for frame in frames:
        parts.append({"inlineData": {"mimeType": "image/jpeg", "data": frame}})
    payload = {
        "contents": [{"parts": parts}],
        "generationConfig": {
            "temperature": 0.2,
            "responseMimeType": "application/json",
        },
    }
    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model}:generateContent?key={api_key}"
    )
    data = _post_json(url, payload, {"Content-Type": "application/json"}, retries=1)
    blocked = ((data.get("promptFeedback") or {}).get("blockReason"))
    if blocked:
        raise RuntimeError(f"gemini_blocked:{blocked}")
    candidates = data.get("candidates") or []
    if not candidates:
        raise RuntimeError(_gemini_error(data))
    parts = ((candidates[0].get("content") or {}).get("parts") or [])
    texts = [part.get("text") for part in parts if part.get("text")]
    if not texts:
        raise RuntimeError("empty_gemini_response")
    return texts[0]


def _openai(api_key: str, model: str, prompt: str, frames: list) -> str:
    content = [{"type": "text", "text": prompt}]
    for frame in frames:
        content.append(
            {
                "type": "image_url",
                "image_url": {
                    "url": f"data:image/jpeg;base64,{frame}",
                    "detail": "low",
                },
            }
        )
    payload = {
        "model": model,
        "temperature": 0.2,
        "response_format": {"type": "json_object"},
        "messages": [{"role": "user", "content": content}],
    }
    data = _post_json(
        "https://api.openai.com/v1/chat/completions",
        payload,
        {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        retries=2,
    )
    choices = data.get("choices") or []
    if not choices:
        raise RuntimeError("empty_openai_response")
    return ((choices[0].get("message") or {}).get("content")) or ""


def _post_json(url: str, payload: dict, headers: dict, retries: int = 3) -> dict:
    body = json.dumps(payload).encode("utf-8")
    last_error = RuntimeError("request_failed")
    for attempt in range(retries):
        request = urllib.request.Request(url, data=body, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            raw = exc.read().decode("utf-8", errors="replace")
            last_error = RuntimeError(_http_error_message(exc.code, raw))
            if attempt + 1 < retries and should_retry(exc.code, raw):
                time.sleep(retry_seconds(exc.code, raw, attempt))
                continue
            raise last_error from None
        except urllib.error.URLError as exc:
            last_error = RuntimeError(str(exc.reason)[:200] or "network_error")
            if attempt + 1 < retries:
                time.sleep(retry_seconds(503, "", attempt))
                continue
            raise last_error from None
    raise last_error


def should_retry(code: int, body: str) -> bool:
    if code in RETRYABLE_STATUS:
        return True
    upper = body.upper()
    return "RESOURCE_EXHAUSTED" in upper or "UNAVAILABLE" in upper


def retry_seconds(code: int, body: str, attempt: int) -> float:
    delay = parsed_retry_delay(body)
    if delay is None:
        delay = 1.0 + attempt
    return min(max(delay, 0.4), 2.0)


def parsed_retry_delay(body: str) -> Optional[float]:
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        return None
    error = data.get("error") if isinstance(data, dict) else None
    if not isinstance(error, dict):
        return None
    for item in error.get("details") or []:
        if not isinstance(item, dict):
            continue
        raw = item.get("retryDelay")
        if isinstance(raw, str) and raw.endswith("s"):
            try:
                return float(raw[:-1])
            except ValueError:
                continue
        if isinstance(raw, (int, float)):
            return float(raw)
    return None


def _http_error_message(code: int, body: str) -> str:
    try:
        data = json.loads(body)
        message = ((data.get("error") or {}).get("message")) or data.get("message")
        if message:
            return str(message)[:300]
    except json.JSONDecodeError:
        pass
    return f"http_{code}"


def _gemini_error(data: dict) -> str:
    error = data.get("error") or {}
    message = error.get("message")
    if message:
        return str(message)[:200]
    return "empty_gemini_response"
