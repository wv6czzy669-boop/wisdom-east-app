#!/usr/bin/env python3
"""Generate the five Build 30 EAST. App Store editorial plates.

The supplied black-theme plates remain local source references so their
approved composition, typography, and cropping are preserved. Only their
palette changes. Plates 2 and 4 embed the supplied Build 30 captures intact.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageCms


REPO_ROOT = Path(__file__).resolve().parents[2]
SCREENSHOT_ROOT = REPO_ROOT / "artifacts/app_store/screenshots/en-US/iphone_6_9"
FINAL_DIR = SCREENSHOT_ROOT / "final"
ADDITIONAL_DIR = SCREENSHOT_ROOT / "additional"
REVIEW_DIR = SCREENSHOT_ROOT / "review"
PREVIEW_DIR = REVIEW_DIR / "preview"
SOURCE_DIR = Path(__file__).resolve().parent / "sources/build_30"

CANVAS_SIZE = (1242, 2688)
SOURCE_SIZE = (1284, 2778)
SCALE = CANVAS_SIZE[0] / SOURCE_SIZE[0]

# Locked Build 30 EAST. visual system; mirrors lib/theme/east_design.dart.
BACKGROUND = (226, 224, 217)  # #E2E0D9
INK = (44, 41, 36)  # #2C2924
UTILITY_INK = (79, 74, 66)  # #4F4A42
SECONDARY = (98, 93, 84)  # #625D54
HINT = (147, 141, 130)  # #938D82
DIVIDER = (195, 189, 178)  # #C3BDB2

LEGACY_FILENAMES = {
    "01_ask_from_your_heart.png",
    "02_one_wisdom_each_day.png",
    "03_keep_what_stays.png",
    "04_write_what_remains.png",
    "05_a_publication_of_what_you_kept.png",
}

PLATES = [
    {
        "filename": "01_one_moment.png",
        "reference": "01_intro_black_reference.png",
        "headline": "EAST. asks for one moment.",
        "regions": [
            ((90, 110, 300, 180), (119, 117, 114), UTILITY_INK),
            ((90, 550, 810, 730), (86, 84, 82), SECONDARY),
            ((80, 1110, 900, 1270), (237, 234, 227), INK),
            ((80, 1250, 900, 1430), (147, 145, 141), UTILITY_INK),
            ((0, 2240, 1284, 2490), (31, 30, 29), DIVIDER),
            ((80, 2560, 920, 2730), (61, 61, 59), SECONDARY),
        ],
    },
    {
        "filename": "02_one_wisdom_every_24_hours.png",
        "reference": "02_reveal_black_reference.png",
        "headline": "One wisdom. Every 24 hours.",
        "regions": [
            ((90, 110, 350, 180), (72, 71, 69), SECONDARY),
            ((80, 330, 800, 445), (237, 234, 227), INK),
            ((80, 440, 900, 550), (119, 117, 114), UTILITY_INK),
            ((80, 630, 1000, 720), (61, 61, 59), SECONDARY),
            ((0, 805, 1284, 840), (29, 28, 28), DIVIDER),
        ],
        "app_capture": "IMG_1939.PNG",
    },
    {
        "filename": "03_the_ritual.png",
        "reference": "03_ritual_black_reference.png",
        "headline": "The ritual — four movements.",
        "regions": [
            ((90, 70, 830, 190), (75, 74, 72), SECONDARY),
            ((70, 530, 650, 710), (75, 74, 72), SECONDARY),
            ((70, 880, 650, 1060), (111, 110, 107), SECONDARY),
            ((70, 1240, 760, 1530), (153, 152, 148), UTILITY_INK),
            ((70, 1770, 800, 2030), (232, 230, 224), INK),
            ((740, 600, 1210, 2040), (33, 32, 32), DIVIDER),
            ((70, 2240, 960, 2430), (70, 69, 68), SECONDARY),
            ((70, 2520, 950, 2740), (51, 51, 49), HINT),
            ((0, 2180, 1284, 2250), (33, 32, 32), DIVIDER),
        ],
    },
    {
        "filename": "04_keep_reflections.png",
        "reference": "04_kept_black_reference.png",
        "headline": "What you keep, returns.",
        "regions": [
            ((90, 100, 700, 180), (72, 71, 69), SECONDARY),
            ((80, 330, 900, 450), (237, 234, 227), INK),
            ((80, 440, 800, 560), (119, 117, 114), UTILITY_INK),
            ((80, 630, 1120, 720), (61, 61, 59), SECONDARY),
            ((0, 805, 1284, 840), (29, 28, 28), DIVIDER),
        ],
        "app_capture": "IMG_1942.PNG",
    },
    {
        "filename": "05_what_east_does_not_have.png",
        "reference": "05_no_feed_black_reference.png",
        "headline": "What EAST. does not have.",
        "regions": [
            ((90, 100, 900, 190), (72, 71, 69), SECONDARY),
            ((70, 340, 700, 710), (72, 71, 69), SECONDARY),
            ((0, 805, 1284, 845), (29, 28, 28), DIVIDER),
            ((80, 1060, 1080, 1220), (237, 234, 227), INK),
            ((80, 1210, 900, 1390), (130, 128, 125), UTILITY_INK),
            ((350, 1580, 940, 2250), None, None),
            ((420, 2200, 850, 2400), (57, 56, 54), UTILITY_INK),
            ((80, 2520, 750, 2740), (57, 56, 54), SECONDARY),
        ],
    },
    {
        "filename": "06_enter_the_circle.png",
        "reference": "06_keeper_black_reference.png",
        "headline": "Enter the Circle.",
        "regions": [
            ((80, 450, 600, 575), (237, 234, 227), INK),
            ((80, 560, 760, 710), (147, 145, 141), UTILITY_INK),
            ((80, 710, 1120, 800), (76, 75, 73), SECONDARY),
            ((0, 805, 1284, 845), (43, 42, 41), DIVIDER),
        ],
        "app_capture": "IMG_1940.PNG",
        "capture_box": (231, 994, 1053, 2778),
        "capture_top_trim": 0,
    },
]

SUPPLEMENTAL_CAPTURES = [
    "IMG_1933.PNG",
    "IMG_1934.PNG",
    "IMG_1935.PNG",
    "IMG_1940.PNG",
]


def _srgb_profile() -> bytes:
    return ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()


def _scaled_box(box: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    return tuple(round(value * SCALE) for value in box)  # type: ignore[return-value]


def _composite_tone(
    canvas: Image.Image,
    reference: Image.Image,
    box: tuple[int, int, int, int],
    source_tone: tuple[int, int, int],
    target_tone: tuple[int, int, int],
) -> None:
    """Re-ink one approved reference region without moving its pixels."""
    x0, y0, x1, y1 = _scaled_box(box)
    crop = reference.crop((x0, y0, x1, y1)).convert("RGB")
    source_luma = sum(source_tone) / 3
    alpha = Image.new("L", crop.size)
    alpha.putdata(
        [max(0, min(255, round((sum(pixel) / 3) / source_luma * 255))) for pixel in crop.getdata()]
    )
    canvas.paste(Image.new("RGB", crop.size, target_tone), (x0, y0), alpha)


def _composite_orb(canvas: Image.Image, reference: Image.Image, box: tuple[int, int, int, int]) -> None:
    """Carry across Plate 5's original low-contrast orb and central ring."""
    x0, y0, x1, y1 = _scaled_box(box)
    crop = reference.crop((x0, y0, x1, y1)).convert("RGB")
    luma = [sum(pixel) / 3 for pixel in crop.getdata()]
    alpha = Image.new("L", crop.size)
    alpha.putdata([max(0, min(255, round(value / 72 * 96))) for value in luma])
    canvas.paste(Image.new("RGB", crop.size, HINT), (x0, y0), alpha)
    ring_alpha = Image.new("L", crop.size)
    ring_alpha.putdata([max(0, min(255, round(max(0, value - 105) / 75 * 255))) for value in luma])
    canvas.paste(Image.new("RGB", crop.size, DIVIDER), (x0, y0), ring_alpha)


def _render_plate(spec: dict[str, object]) -> Image.Image:
    with Image.open(SOURCE_DIR / str(spec["reference"])) as source:
        reference = source.convert("RGB").resize(CANVAS_SIZE, Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", CANVAS_SIZE, BACKGROUND)
    for box, source_tone, target_tone in spec["regions"]:  # type: ignore[index]
        if source_tone is None:
            _composite_orb(canvas, reference, box)
        else:
            _composite_tone(canvas, reference, box, source_tone, target_tone)

    if app_capture := spec.get("app_capture"):
        capture_box = tuple(spec.get("capture_box", (0, 822, 1284, 2778)))
        capture_x, capture_y, capture_right, _ = _scaled_box(capture_box)
        capture_width = capture_right - capture_x
        capture_top_trim = int(spec.get("capture_top_trim", 24))
        with Image.open(SOURCE_DIR / str(app_capture)) as source:
            capture = source.convert("RGB").crop(
                (0, capture_top_trim, source.width, source.height)
            )
        capture = capture.resize(
            (
                capture_width,
                round(capture.height * capture_width / capture.width),
            ),
            Image.Resampling.LANCZOS,
        )
        canvas.paste(capture, (capture_x, capture_y))
    return canvas


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _write_review_assets(paths: list[Path], profile: bytes) -> None:
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    thumbs: list[Image.Image] = []
    for path in paths:
        with Image.open(path) as source:
            preview = source.convert("RGB").resize((440, 956), Image.Resampling.LANCZOS)
            thumb = source.convert("RGB").resize((220, 478), Image.Resampling.LANCZOS)
        preview.save(PREVIEW_DIR / path.name, format="PNG", optimize=True, icc_profile=profile)
        thumbs.append(thumb)
    gap, margin = 14, 20
    sheet = Image.new("RGB", (margin * 2 + len(thumbs) * 220 + (len(thumbs) - 1) * gap, margin * 2 + 478), BACKGROUND)
    for index, thumb in enumerate(thumbs):
        sheet.paste(thumb, (margin + index * (220 + gap), margin))
    sheet.save(REVIEW_DIR / "contact_sheet_app_store_thumbnail.png", format="PNG", optimize=True, icc_profile=profile)


def _write_supplemental_captures(profile: bytes) -> list[Path]:
    """Export supplied full-screen Build 30 captures at the App Store canvas."""
    ADDITIONAL_DIR.mkdir(parents=True, exist_ok=True)
    paths: list[Path] = []
    for filename in SUPPLEMENTAL_CAPTURES:
        with Image.open(SOURCE_DIR / filename) as source:
            capture = source.convert("RGB").resize(CANVAS_SIZE, Image.Resampling.LANCZOS)
        path = ADDITIONAL_DIR / filename.lower()
        capture.save(path, format="PNG", optimize=True, compress_level=9, icc_profile=profile)
        paths.append(path)
    return paths


def _write_manifest(paths: list[Path]) -> None:
    manifest = {
        "locale": "en-US",
        "device_field": "6.9-inch iPhone",
        "canvas": {"width": CANVAS_SIZE[0], "height": CANVAS_SIZE[1]},
        "background": "#E2E0D9",
        "foreground_tokens": {"ink": "#2C2924", "utilityInk": "#4F4A42", "secondary": "#625D54", "hint": "#938D82", "divider": "#C3BDB2"},
        "files": [
            {
                "filename": path.name,
                "width": CANVAS_SIZE[0],
                "height": CANVAS_SIZE[1],
                "color_mode": "RGB",
                "source_reference": spec["reference"],
                "embedded_capture": spec.get("app_capture"),
                "headline": spec["headline"],
                "file_size_bytes": path.stat().st_size,
                "sha256": _sha256(path),
            }
            for spec, path in zip(PLATES, paths)
        ],
    }
    (SCREENSHOT_ROOT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    FINAL_DIR.mkdir(parents=True, exist_ok=True)
    REVIEW_DIR.mkdir(parents=True, exist_ok=True)
    profile = _srgb_profile()
    expected = {str(spec["filename"]) for spec in PLATES}
    for filename in LEGACY_FILENAMES | expected:
        path = FINAL_DIR / filename
        if path.exists():
            path.unlink()
    paths: list[Path] = []
    for spec in PLATES:
        path = FINAL_DIR / str(spec["filename"])
        _render_plate(spec).save(path, format="PNG", optimize=True, compress_level=9, icc_profile=profile)
        paths.append(path)
    _write_review_assets(paths, profile)
    supplemental_paths = _write_supplemental_captures(profile)
    _write_manifest(paths)
    print(
        f"Wrote {len(paths)} Build 30 App Store plates and "
        f"{len(supplemental_paths)} supplemental captures."
    )


if __name__ == "__main__":
    main()
