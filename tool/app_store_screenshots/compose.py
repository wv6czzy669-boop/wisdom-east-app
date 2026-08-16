#!/usr/bin/env python3
"""Compose EAST.'s five authentic iPhone captures into App Store artwork."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageCms, ImageDraw, ImageFont


REPO_ROOT = Path(__file__).resolve().parents[2]
SCREENSHOT_ROOT = (
    REPO_ROOT / "artifacts/app_store/screenshots/en-US/iphone_6_9"
)
RAW_DIR = SCREENSHOT_ROOT / "raw"
FINAL_DIR = SCREENSHOT_ROOT / "final"
REVIEW_DIR = SCREENSHOT_ROOT / "review"
PREVIEW_DIR = REVIEW_DIR / "preview"
FONT_PATH = REPO_ROOT / "assets/fonts/CormorantGaramond-Light.ttf"
WISDOM_SOURCE = REPO_ROOT / "lib/data/wisdoms.dart"

CANVAS_SIZE = (1320, 2868)
BACKGROUND = (1, 1, 1)
APP_BACKGROUND = (4, 4, 4)
IVORY = (244, 240, 232)
MUTED_IVORY = (170, 165, 156)
BOUNDARY = (45, 42, 35)
HEADLINE_TOP = 132
HEADLINE_FONT_SIZE = 104
HEADLINE_SPACING = 2
CAPTURE_X = 90
CAPTURE_Y = 620
CAPTURE_WIDTH = 1140
CORNER_RADIUS = 44
BRAND_FONT_SIZE = 44
BRAND_TOP = 397

SCREENSHOTS = [
    {
        "filename": "01_one_quiet_moment.png",
        "raw": "01_wisdom_reveal_raw.png",
        "headline": "One quiet moment. One wisdom each day.",
        "display_headline": "One quiet moment.\nOne wisdom each day.",
        "source_screen": "Home",
        "source_state": "Existing locked wisdom reopened in the real reveal state; rolling-lock copy cropped out",
        "source_wisdom_text": "Some answers arrive only after silence.",
        "source_crop": (60, 100, 1260, 2050),
        "show_brand": True,
    },
    {
        "filename": "02_pause_feel_ask.png",
        "raw": "02_pause_raw.png",
        "headline": "Pause. Feel. Ask from your heart.",
        "display_headline": "Pause. Feel. Ask from\nyour heart.",
        "source_screen": "Home ritual",
        "source_state": "Authentic stable Pause. ritual frame",
        "source_wisdom_text": None,
        "source_crop": (60, 100, 1260, 2200),
        "show_brand": False,
    },
    {
        "filename": "03_keep_what_stays.png",
        "raw": "03_kept_collection_raw.png",
        "headline": "Keep what stays.",
        "display_headline": "Keep what stays.",
        "source_screen": "Kept",
        "source_state": "Three distinct revealId-based kept occurrences, newest first",
        "source_wisdom_text": [
            "Some answers arrive only after silence.",
            "Clarity often arrives after stillness.",
            "A quiet life can still be meaningful.",
        ],
        "source_crop": (60, 100, 1260, 1490),
        "show_brand": False,
    },
    {
        "filename": "04_write_what_remains.png",
        "raw": "04_reflection_raw.png",
        "headline": "Write what remains.",
        "display_headline": "Write what remains.",
        "source_screen": "Reflection",
        "source_state": "Existing saved Reflection attached to one kept wisdom; lower editing controls cropped out",
        "source_wisdom_text": "The path softens when resistance ends.",
        "source_crop": (35, 105, 1285, 1030),
        "show_brand": False,
    },
    {
        "filename": "05_presence_not_scrolling.png",
        "raw": "05_opening_raw.png",
        "headline": "Made for presence, not scrolling.",
        "display_headline": "Made for presence,\nnot scrolling.",
        "source_screen": "Home",
        "source_state": "Authentic EAST. opening ritual mark",
        "source_wisdom_text": None,
        "source_crop": (60, 140, 1260, 2380),
        "show_brand": False,
    },
]


def _srgb_profile() -> bytes:
    return ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()


def _ensure_source_wisdoms_are_authentic() -> None:
    source = WISDOM_SOURCE.read_text(encoding="utf-8")
    values: set[str] = set()
    for screenshot in SCREENSHOTS:
        wisdom = screenshot["source_wisdom_text"]
        if isinstance(wisdom, str):
            values.add(wisdom)
        elif isinstance(wisdom, list):
            values.update(wisdom)
    missing = [value for value in sorted(values) if f'"text": "{value}"' not in source]
    if missing:
        raise RuntimeError(f"Wisdom text not found in lib/data/wisdoms.dart: {missing}")


def _flatten_raw(path: Path) -> Image.Image:
    with Image.open(path) as source:
        rgba = source.convert("RGBA")
        base = Image.new("RGBA", rgba.size, APP_BACKGROUND + (255,))
        return Image.alpha_composite(base, rgba).convert("RGB")


def _headline_origin(
    draw: ImageDraw.ImageDraw,
    headline: str,
    font: ImageFont.FreeTypeFont,
) -> tuple[int, int]:
    bbox = draw.multiline_textbbox(
        (0, 0),
        headline,
        font=font,
        spacing=HEADLINE_SPACING,
        align="center",
    )
    width = bbox[2] - bbox[0]
    return ((CANVAS_SIZE[0] - width) // 2 - bbox[0], HEADLINE_TOP - bbox[1])


def _compose_one(
    spec: dict[str, object],
    font: ImageFont.FreeTypeFont,
    brand_font: ImageFont.FreeTypeFont,
    profile: bytes,
) -> Path:
    raw_path = RAW_DIR / str(spec["raw"])
    if not raw_path.exists():
        raise FileNotFoundError(raw_path)

    canvas = Image.new("RGB", CANVAS_SIZE, BACKGROUND)
    draw = ImageDraw.Draw(canvas)
    display_headline = str(spec["display_headline"])
    draw.multiline_text(
        _headline_origin(draw, display_headline, font),
        display_headline,
        fill=IVORY,
        font=font,
        spacing=HEADLINE_SPACING,
        align="center",
    )

    if bool(spec["show_brand"]):
        brand = "EAST."
        brand_bbox = draw.textbbox((0, 0), brand, font=brand_font)
        brand_width = brand_bbox[2] - brand_bbox[0]
        draw.text(
            (
                (CANVAS_SIZE[0] - brand_width) // 2 - brand_bbox[0],
                BRAND_TOP - brand_bbox[1],
            ),
            brand,
            fill=MUTED_IVORY,
            font=brand_font,
        )

    source_crop = tuple(int(value) for value in spec["source_crop"])
    capture = _flatten_raw(raw_path).crop(source_crop)
    capture_height = round(capture.height * CAPTURE_WIDTH / capture.width)
    capture = capture.resize(
        (CAPTURE_WIDTH, capture_height),
        Image.Resampling.LANCZOS,
    )
    mask = Image.new("L", capture.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, capture.width - 1, capture.height - 1),
        radius=CORNER_RADIUS,
        fill=255,
    )
    canvas.paste(capture, (CAPTURE_X, CAPTURE_Y), mask)
    draw.rounded_rectangle(
        (
            CAPTURE_X,
            CAPTURE_Y,
            CAPTURE_X + capture.width - 1,
            CAPTURE_Y + capture.height - 1,
        ),
        radius=CORNER_RADIUS,
        outline=BOUNDARY,
        width=2,
    )

    output_path = FINAL_DIR / str(spec["filename"])
    canvas.save(
        output_path,
        format="PNG",
        optimize=True,
        compress_level=9,
        icc_profile=profile,
    )
    return output_path


def _write_previews(final_paths: list[Path], profile: bytes) -> list[Path]:
    preview_paths: list[Path] = []
    for path in final_paths:
        with Image.open(path) as source:
            preview = source.convert("RGB").resize(
                (440, 956),
                Image.Resampling.LANCZOS,
            )
            preview_path = PREVIEW_DIR / path.name
            preview.save(
                preview_path,
                format="PNG",
                optimize=True,
                compress_level=9,
                icc_profile=profile,
            )
            preview_paths.append(preview_path)
    return preview_paths


def _write_contact_sheet(final_paths: list[Path], profile: bytes) -> Path:
    thumb_width = 360
    thumb_height = round(CANVAS_SIZE[1] * thumb_width / CANVAS_SIZE[0])
    gap = 24
    margin = 36
    sheet = Image.new(
        "RGB",
        (
            margin * 2 + thumb_width * len(final_paths) + gap * (len(final_paths) - 1),
            margin * 2 + thumb_height,
        ),
        (18, 18, 18),
    )
    for index, path in enumerate(final_paths):
        with Image.open(path) as source:
            thumb = source.convert("RGB").resize(
                (thumb_width, thumb_height),
                Image.Resampling.LANCZOS,
            )
        x = margin + index * (thumb_width + gap)
        sheet.paste(thumb, (x, margin))
    output = REVIEW_DIR / "contact_sheet.png"
    sheet.save(
        output,
        format="PNG",
        optimize=True,
        compress_level=9,
        icc_profile=profile,
    )
    return output


def _write_thumbnail_contact_sheet(final_paths: list[Path], profile: bytes) -> Path:
    """Write a 220 px-per-shot sheet approximating mobile App Store scale."""
    thumb_width = 220
    thumb_height = round(CANVAS_SIZE[1] * thumb_width / CANVAS_SIZE[0])
    gap = 14
    margin = 20
    sheet = Image.new(
        "RGB",
        (
            margin * 2 + thumb_width * len(final_paths) + gap * (len(final_paths) - 1),
            margin * 2 + thumb_height,
        ),
        (16, 16, 16),
    )
    for index, path in enumerate(final_paths):
        with Image.open(path) as source:
            thumb = source.convert("RGB").resize(
                (thumb_width, thumb_height),
                Image.Resampling.LANCZOS,
            )
        x = margin + index * (thumb_width + gap)
        sheet.paste(thumb, (x, margin))
    output = REVIEW_DIR / "contact_sheet_app_store_thumbnail.png"
    sheet.save(
        output,
        format="PNG",
        optimize=True,
        compress_level=9,
        icc_profile=profile,
    )
    return output


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _write_manifest(final_paths: list[Path]) -> Path:
    entries = []
    for spec, path in zip(SCREENSHOTS, final_paths, strict=True):
        with Image.open(path) as image:
            entries.append(
                {
                    "filename": path.name,
                    "width": image.width,
                    "height": image.height,
                    "color_mode": image.mode,
                    "alpha_channel": "A" in image.getbands(),
                    "transparency": image.info.get("transparency") is not None,
                    "color_profile": "sRGB",
                    "file_size_bytes": path.stat().st_size,
                    "sha256": _sha256(path),
                    "source_screen": spec["source_screen"],
                    "source_state": spec["source_state"],
                    "headline": spec["headline"],
                    "source_wisdom_text": spec["source_wisdom_text"],
                }
            )
    manifest = {
        "locale": "en-US",
        "device_field": "6.9-inch iPhone",
        "canvas": {"width": 1320, "height": 2868},
        "files": entries,
    }
    path = SCREENSHOT_ROOT / "manifest.json"
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return path


def main() -> None:
    FINAL_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    _ensure_source_wisdoms_are_authentic()
    font = ImageFont.truetype(str(FONT_PATH), HEADLINE_FONT_SIZE)
    brand_font = ImageFont.truetype(str(FONT_PATH), BRAND_FONT_SIZE)
    profile = _srgb_profile()
    final_paths = [
        _compose_one(spec, font, brand_font, profile) for spec in SCREENSHOTS
    ]
    _write_previews(final_paths, profile)
    _write_contact_sheet(final_paths, profile)
    _write_thumbnail_contact_sheet(final_paths, profile)
    manifest = _write_manifest(final_paths)
    print(f"Wrote {len(final_paths)} final screenshots and {manifest}")


if __name__ == "__main__":
    main()
