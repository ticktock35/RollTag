#!/usr/bin/env python3
"""Build RollTag/Resources/CCCEDICTKeywords.json from CC-CEDICT.

The app loads this file as data. Do not copy Chinese–English pairs into Swift.
CC-CEDICT is CC BY-SA 4.0: https://www.mdbg.net/chinese/dictionary?page=cc-cedict
"""

from __future__ import annotations

import argparse
import gzip
import json
import re
import unicodedata
import urllib.request
from pathlib import Path

CEDICT_URL = "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz"
LINE_RE = re.compile(r"^(\S+) (\S+) \[([^\]]+)\] /(.*)/$")
GETTY_WORD_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SKIP_PREFIXES = (
    "variant of",
    "old variant of",
    "japanese variant of",
    "see ",
    "surname ",
    "kangxi",
    "abbr.",
    "also pr.",
    "also written",
    "erhua variant",
    "classifier",
    "archaic variant",
    "used in",
    "see also",
)


def stock_keyword(raw: str) -> str:
    trimmed = raw.replace("#", "").strip().lower()
    return " ".join(trimmed.split())


def has_cjk(text: str) -> bool:
    return any("CJK" in unicodedata.name(ch, "") for ch in text)


def is_getty(text: str) -> bool:
    if not 3 <= len(text) <= 40:
        return False
    words = text.split(" ")
    if not 1 <= len(words) <= 5:
        return False
    return all(GETTY_WORD_RE.match(word) for word in words)


def clean_def(raw: str) -> str | None:
    text = re.sub(r"\([^)]*\)", " ", raw).replace("|", " ")
    text = " ".join(text.split()).strip(" ,;.")
    if not text:
        return None
    low = text.lower()
    if any(low.startswith(prefix) for prefix in SKIP_PREFIXES) or low.startswith("cl:"):
        return None
    text = re.split(r"[;/,]", text)[0].strip()
    low = text.lower()
    if low.startswith("to "):
        text = text[3:].strip()
        low = text.lower()
    if low.startswith("the "):
        text = text[4:].strip()
    formatted = stock_keyword(text)
    if not is_getty(formatted):
        return None
    return formatted


def gloss_score(original: str) -> int:
    stripped = re.sub(r"\([^)]*\)", " ", original)
    stripped = " ".join(stripped.split())
    proper = bool(re.match(r"^[A-Z][a-z]+(?: [A-Z][a-z]+)*$", stripped))
    return 0 if proper else 1


def consider(entries: dict[str, tuple], key: str, english: str, original: str) -> None:
    if not 2 <= len(key) <= 8 or not has_cjk(key):
        return
    scored = (gloss_score(original), english)
    previous = entries.get(key)
    if previous is None or scored[0] > previous[0]:
        entries[key] = scored


def parse_cedict(text: str) -> dict[str, str]:
    entries: dict[str, tuple] = {}
    for raw_line in text.splitlines():
        if raw_line.startswith("#"):
            continue
        match = LINE_RE.match(raw_line.strip())
        if not match:
            continue
        traditional, simplified, _pinyin, defs = match.groups()
        for item in (part for part in defs.split("/") if part):
            cleaned = clean_def(item)
            if not cleaned:
                continue
            consider(entries, traditional, cleaned, item)
            if simplified != traditional:
                consider(entries, simplified, cleaned, item)
    return {key: value[1] for key, value in entries.items()}


def load_cedict(path: Path | None) -> str:
    if path:
        data = path.read_bytes()
        if path.suffix == ".gz" or data[:2] == b"\x1f\x8b":
            return gzip.decompress(data).decode("utf-8")
        return data.decode("utf-8")
    with urllib.request.urlopen(CEDICT_URL) as response:
        return gzip.decompress(response.read()).decode("utf-8")


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path)
    parser.add_argument(
        "--output",
        type=Path,
        default=root / "RollTag" / "Resources" / "CCCEDICTKeywords.json",
    )
    args = parser.parse_args()
    mapping = parse_cedict(load_cedict(args.input))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(mapping, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    print(f"wrote {args.output} keys={len(mapping)} unique_en={len(set(mapping.values()))}")


if __name__ == "__main__":
    main()
