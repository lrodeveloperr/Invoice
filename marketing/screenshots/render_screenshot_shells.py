#!/usr/bin/env python3
"""Render the locked Japanese App Store screenshot shells.

The blank shell leaves only the authentic-UI aperture empty. With --with-sources,
01.png, 02.png, and 03.png are proportionally scaled and centre-cropped into that
same aperture; source pixels are otherwise left untouched.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
FONT = HERE / "fonts" / "NotoSansJP-caption-subset.ttf"
OUTPUT = HERE / "ja-JP" / "iphone-6.9"
SHELLS = OUTPUT / "shells"
FINAL = OUTPUT / "final"
SOURCE = HERE / "source" / "ja-JP"

CANVAS = (1320, 2868)
PANEL = (66, 520, 1254, 2478)
RADIUS = 64
CAPTION_SIZE = 116
CAPTION_LINE_HEIGHT = 152
CAPTION_CENTRE_Y = 250

FRAMES = [
    {
        "order": 1,
        "caption_ja": "月末の請求書を、\n数分で",
        "caption_en": "Create Month-End Invoices in Minutes",
        "filename": "01-month-end-invoices-ja-shell.png",
        "final_filename": "01-month-end-invoices-ja.png",
        "background": "#EAF8FB",
        "accent": "#10A9B7",
    },
    {
        "order": 2,
        "caption_ja": "作業日と現場が、\nそのまま明細に",
        "caption_en": "Dates and Job Sites Become Invoice Lines",
        "filename": "02-dates-and-sites-ja-shell.png",
        "final_filename": "02-dates-and-sites-ja.png",
        "background": "#EEF8F4",
        "accent": "#168A78",
    },
    {
        "order": 3,
        "caption_ja": "送る前に、PDFを\n正確に確認",
        "caption_en": "Check the Exact PDF Before Sending",
        "filename": "03-pdf-preview-ja-shell.png",
        "final_filename": "03-pdf-preview-ja.png",
        "background": "#F0F2FD",
        "accent": "#3454D1",
    },
]


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def cover(source: Image.Image, size: tuple[int, int]) -> Image.Image:
    source = source.convert("RGB")
    scale = max(size[0] / source.width, size[1] / source.height)
    resized = source.resize((round(source.width * scale), round(source.height * scale)), Image.Resampling.LANCZOS)
    left = max(0, (resized.width - size[0]) // 2)
    top = max(0, (resized.height - size[1]) // 2)
    return resized.crop((left, top, left + size[0], top + size[1]))


def draw_caption(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont) -> None:
    lines = text.split("\n")
    total_height = CAPTION_LINE_HEIGHT * len(lines)
    top = CAPTION_CENTRE_Y - total_height // 2
    for index, line in enumerate(lines):
        bounds = draw.textbbox((0, 0), line, font=font, stroke_width=0)
        width = bounds[2] - bounds[0]
        x = (CANVAS[0] - width) // 2
        y = top + index * CAPTION_LINE_HEIGHT
        draw.text((x, y), line, font=font, fill="#0B1F3A")


def render(frame: dict[str, object], source: Image.Image | None) -> Image.Image:
    canvas = Image.new("RGB", CANVAS, frame["background"])
    draw = ImageDraw.Draw(canvas)
    accent = str(frame["accent"])

    # Sparse campaign accents remain outside the authentic-UI aperture.
    draw.ellipse((-170, -175, 145, 140), fill=accent)
    draw.ellipse((1160, 350, 1410, 600), fill=accent)
    draw.rounded_rectangle((102, 438, 430, 452), radius=7, fill=accent)

    panel_width = PANEL[2] - PANEL[0]
    panel_height = PANEL[3] - PANEL[1]

    shadow = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (PANEL[0], PANEL[1] + 20, PANEL[2], PANEL[3] + 20),
        radius=RADIUS,
        fill=(11, 31, 58, 42),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB")

    mask = rounded_mask((panel_width, panel_height), RADIUS)
    if source is None:
        content = Image.new("RGB", (panel_width, panel_height), "#FFFFFF")
    else:
        content = cover(source, (panel_width, panel_height))
    canvas.paste(content, (PANEL[0], PANEL[1]), mask)

    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(PANEL, radius=RADIUS, outline="#C7D7E4", width=3)
    font = ImageFont.truetype(str(FONT), CAPTION_SIZE)
    draw_caption(draw, str(frame["caption_ja"]), font)
    return canvas


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def contact_sheet(paths: list[Path], target: Path) -> None:
    thumb_width = 330
    thumb_height = round(CANVAS[1] * thumb_width / CANVAS[0])
    gap = 30
    sheet = Image.new("RGB", (gap * 4 + thumb_width * 3, thumb_height + gap * 2), "#E8EDF3")
    for index, path in enumerate(paths):
        image = Image.open(path).convert("RGB")
        image.thumbnail((thumb_width, thumb_height), Image.Resampling.LANCZOS)
        sheet.paste(image, (gap + index * (thumb_width + gap), gap))
    sheet.save(target, format="PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--with-sources", action="store_true", help="Insert authentic 01.png–03.png UI captures.")
    args = parser.parse_args()

    if not FONT.exists():
        raise SystemExit(f"Missing caption font: {FONT}")

    destination = FINAL if args.with_sources else SHELLS
    destination.mkdir(parents=True, exist_ok=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)

    rendered: list[Path] = []
    manifest_frames: list[dict[str, object]] = []
    for frame in FRAMES:
        source = None
        filename = str(frame["filename"])
        if args.with_sources:
            source_path = SOURCE / f"{int(frame['order']):02d}.png"
            if not source_path.exists():
                raise SystemExit(f"Missing authentic source screenshot: {source_path}")
            source = Image.open(source_path)
            filename = str(frame["final_filename"])
        output_path = destination / filename
        render(frame, source).save(output_path, format="PNG", optimize=True)
        rendered.append(output_path)
        manifest_frames.append(
            {
                "order": frame["order"],
                "caption_ja": str(frame["caption_ja"]).replace("\n", ""),
                "caption_en": frame["caption_en"],
                "file": str(output_path.relative_to(ROOT)),
                "sha256": sha256(output_path),
            }
        )

    sheet_path = OUTPUT / ("contact-sheet-final.png" if args.with_sources else "contact-sheet.png")
    contact_sheet(rendered, sheet_path)
    manifest = {
        "locale": "ja-JP",
        "device": "iPhone 6.9-inch",
        "dimensions": {"width": CANVAS[0], "height": CANVAS[1]},
        "mode": "RGB",
        "opaque": True,
        "panel": {"x": PANEL[0], "y": PANEL[1], "width": PANEL[2] - PANEL[0], "height": PANEL[3] - PANEL[1], "radius": RADIUS},
        "top_clear_space": PANEL[1],
        "bottom_clear_space": CANVAS[1] - PANEL[3],
        "frames": manifest_frames,
        "contact_sheet": str(sheet_path.relative_to(ROOT)),
    }
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
