#!/usr/bin/env python3
"""Render a high-contrast RollTag Mac app icon (stacked stills + tag)."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "RollTag" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"

SIZES = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def mix(c1: tuple[int, int, int], c2: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return (
        int(lerp(c1[0], c2[0], t)),
        int(lerp(c1[1], c2[1], t)),
        int(lerp(c1[2], c2[2], t)),
    )


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def plate(size: int) -> Image.Image:
    top = (255, 122, 24)
    bottom = (232, 56, 12)
    img = Image.new("RGB", (size, size), top)
    px = img.load()
    for y in range(size):
        color = mix(top, bottom, y / max(size - 1, 1))
        for x in range(size):
            px[x, y] = color
    return img


def card(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], fill: tuple[int, int, int], radius: int) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def paint_scene(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = box
    w = x1 - x0
    h = y1 - y0
    sky_bottom = y0 + int(h * 0.62)
    draw.rectangle((x0, y0, x1, sky_bottom), fill=(255, 176, 72))
    draw.rectangle((x0, sky_bottom, x1, y1), fill=(255, 226, 150))
    sun_r = max(5, int(min(w, h) * 0.16))
    cx = x0 + int(w * 0.28)
    cy = sky_bottom
    draw.ellipse((cx - sun_r, cy - sun_r, cx + sun_r, cy + sun_r), fill=(255, 244, 196))


def tag(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], hole: int) -> None:
    x0, y0, x1, y1 = box
    mid_y = (y0 + y1) // 2
    draw.polygon(
        [(x0, y0), (x1 - hole, y0), (x1, mid_y), (x1 - hole, y1), (x0, y1)],
        fill=(12, 42, 56),
    )
    draw.ellipse(
        (x0 + hole, mid_y - hole, x0 + hole * 3, mid_y + hole),
        fill=(255, 226, 150),
    )


def render(size: int) -> Image.Image:
    radius = max(4, int(size * 0.22))
    base = plate(size)
    mask = rounded_mask(size, radius)
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    icon.paste(base, mask=mask)

    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    simple = size <= 32

    if simple:
        inset = max(2, int(size * 0.16))
        card_box = (inset, inset + 1, size - inset - 1, size - inset)
        card(draw, card_box, (255, 236, 176), max(2, size // 8))
        tw = max(6, int(size * 0.42))
        th = max(4, int(size * 0.28))
        tag(
            draw,
            (size - inset - 2, inset - 1, size - inset - 2 + tw, inset - 1 + th),
            max(1, th // 4),
        )
    else:
        stack = [
            (0.20, 0.34, 0.86, 0.88, (64, 24, 10)),
            (0.15, 0.26, 0.84, 0.80, (110, 42, 16)),
            (0.10, 0.16, 0.82, 0.70, (255, 248, 236)),
        ]
        for left, top, right, bottom, fill in stack:
            box = (
                int(size * left),
                int(size * top),
                int(size * right),
                int(size * bottom),
            )
            card(draw, box, fill, max(6, int(size * 0.055)))
        photo = (
            int(size * 0.13),
            int(size * 0.20),
            int(size * 0.79),
            int(size * 0.66),
        )
        paint_scene(draw, photo)
        tw = int(size * 0.22)
        th = int(size * 0.13)
        tag(
            draw,
            (int(size * 0.62), int(size * 0.11), int(size * 0.62) + tw, int(size * 0.11) + th),
            max(3, th // 5),
        )

    icon.alpha_composite(overlay)
    if size >= 128:
        shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        sdraw = ImageDraw.Draw(shadow)
        sdraw.rounded_rectangle(
            (int(size * 0.08), int(size * 0.10), int(size * 0.92), int(size * 0.90)),
            radius=radius,
            fill=(0, 0, 0, 40),
        )
        shadow = shadow.filter(ImageFilter.GaussianBlur(radius=max(1, size // 40)))
        composed = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        composed.alpha_composite(shadow)
        composed.alpha_composite(icon)
        icon = composed
        icon.putalpha(mask)
    return icon


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for edge, name in SIZES:
        render(edge).save(OUT / name, format="PNG")
        print(f"wrote {name} ({edge}px)")


if __name__ == "__main__":
    main()
