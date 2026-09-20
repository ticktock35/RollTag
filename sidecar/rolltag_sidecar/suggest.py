import json
import urllib.error
import urllib.request
from typing import Optional

PROMPT = """You tag B-roll stills for a footage warehouse.
Choose 3 to 8 tags that clearly match the frames.
Use only category and value ids from the catalog JSON. Never invent ids.
Custom tags (category "custom") may be used only if that named subject is clearly visible.
If CONTEXT is present, use filename, path, warehouse name, duration, file size, capture time, and GPS as hints for place and time tags. Frames remain primary. Still choose only catalog ids.
Return JSON: {"tags":[{"category":"...","value":"..."}]}

CATALOG:
"""


def build_prompt(catalog: dict, context: Optional[dict] = None) -> str:
    prompt = PROMPT + json.dumps(catalog, ensure_ascii=False)
    if context:
        prompt += "\n\nCONTEXT:\n" + json.dumps(context, ensure_ascii=False)
    return prompt


def parse_tags(text: str) -> list:
    if not text:
        return []
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.strip("`")
        if cleaned.lower().startswith("json"):
            cleaned = cleaned[4:].strip()
    try:
        data = json.loads(cleaned)
    except json.JSONDecodeError:
        start = cleaned.find("{")
        end = cleaned.rfind("}")
        if start < 0 or end <= start:
            return []
        try:
            data = json.loads(cleaned[start : end + 1])
        except json.JSONDecodeError:
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


def suggest_tags(
    provider: str,
    api_key: str,
    model: str,
    frames: list,
    catalog: dict,
    context: Optional[dict] = None,
) -> dict:
    if not api_key:
        raise ValueError("missing_api_key")
    if not frames:
        raise ValueError("missing_frames")
    prompt = build_prompt(catalog, context if isinstance(context, dict) else None)
    if provider == "gemini":
        text = _gemini(api_key, model or "gemini-3.5-flash-lite", prompt, frames)
    elif provider == "openai":
        text = _openai(api_key, model or "gpt-4.1-mini", prompt, frames)
    else:
        raise ValueError("unsupported_provider")
    return {"tags": parse_tags(text), "provider": provider, "model": model}


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
    data = _post_json(url, payload, {"Content-Type": "application/json"})
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
    )
    choices = data.get("choices") or []
    if not choices:
        raise RuntimeError("empty_openai_response")
    return ((choices[0].get("message") or {}).get("content")) or ""


def _post_json(url: str, payload: dict, headers: dict) -> dict:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")[:800]
        raise RuntimeError(_http_error_message(exc.code, body)) from None


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
