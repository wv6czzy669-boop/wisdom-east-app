#!/usr/bin/env python3
"""Validate the Build 30 EAST. editorial App Store plates."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageChops


REPO_ROOT = Path(__file__).resolve().parents[2]
ROOT = REPO_ROOT / "artifacts/app_store/screenshots/en-US/iphone_6_9"
FINAL_DIR = ROOT / "final"
ADDITIONAL_DIR = ROOT / "additional"
MANIFEST = ROOT / "manifest.json"
SOURCE_DIR = Path(__file__).resolve().parent / "sources/build_30"
EXPECTED_FILENAMES = [
    "01_one_moment.png",
    "02_one_wisdom_every_24_hours.png",
    "03_the_ritual.png",
    "04_keep_reflections.png",
    "05_what_east_does_not_have.png",
    "06_enter_the_circle.png",
]
EXPECTED_ADDITIONAL_FILENAMES = [
    "img_1933.png",
    "img_1934.png",
    "img_1935.png",
    "img_1940.png",
]
BACKGROUND = (226, 224, 217)
CANVAS_SIZE = (1242, 2688)
CAPTURE_Y = round(822 * CANVAS_SIZE[0] / 1284)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _expected_capture(filename: str, width: int, top_trim: int) -> Image.Image:
    with Image.open(SOURCE_DIR / filename) as source:
        capture = source.convert("RGB").crop((0, top_trim, source.width, source.height))
    return capture.resize(
        (
            width,
            round(capture.height * width / capture.width),
        ),
        Image.Resampling.LANCZOS,
    )


def main() -> None:
    actual = sorted(path.name for path in FINAL_DIR.glob("*.png"))
    if actual != EXPECTED_FILENAMES:
        raise AssertionError(f"Unexpected final PNG set: {actual}")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if manifest["background"] != "#E2E0D9":
        raise AssertionError("Manifest background is not #E2E0D9")
    entries = manifest["files"]
    if [entry["filename"] for entry in entries] != EXPECTED_FILENAMES:
        raise AssertionError("Manifest filename order does not match the plates")
    if entries[1]["embedded_capture"] != "IMG_1939.PNG":
        raise AssertionError("Plate 2 is not sourced from IMG_1939.PNG")
    if entries[3]["embedded_capture"] != "IMG_1942.PNG":
        raise AssertionError("Plate 4 is not sourced from IMG_1942.PNG")
    if entries[5]["embedded_capture"] != "IMG_1940.PNG":
        raise AssertionError("Plate 6 is not sourced from IMG_1940.PNG")
    for entry in entries:
        path = FINAL_DIR / entry["filename"]
        with Image.open(path) as image:
            image.load()
            if image.format != "PNG" or image.size != CANVAS_SIZE or image.mode != "RGB":
                raise AssertionError(f"{path.name}: unexpected PNG dimensions/mode")
            if image.getpixel((0, 0)) != BACKGROUND:
                raise AssertionError(f"{path.name}: plate background is not #E2E0D9")
            if "A" in image.getbands() or "transparency" in image.info:
                raise AssertionError(f"{path.name}: transparency detected")
            if not image.info.get("icc_profile"):
                raise AssertionError(f"{path.name}: embedded sRGB profile missing")
        if entry["sha256"] != _sha256(path):
            raise AssertionError(f"{path.name}: SHA-256 mismatch")

    additional = sorted(path.name for path in ADDITIONAL_DIR.glob("*.png"))
    if additional != EXPECTED_ADDITIONAL_FILENAMES:
        raise AssertionError(f"Unexpected supplemental PNG set: {additional}")
    for filename in additional:
        with Image.open(ADDITIONAL_DIR / filename) as image:
            image.load()
            if image.format != "PNG" or image.size != CANVAS_SIZE or image.mode != "RGB":
                raise AssertionError(f"{filename}: unexpected PNG dimensions/mode")
            if "A" in image.getbands() or "transparency" in image.info:
                raise AssertionError(f"{filename}: transparency detected")

    capture_specs = (
        (EXPECTED_FILENAMES[1], "IMG_1939.PNG", (0, CAPTURE_Y, CANVAS_SIZE[0]), 24),
        (EXPECTED_FILENAMES[3], "IMG_1942.PNG", (0, CAPTURE_Y, CANVAS_SIZE[0]), 24),
        (EXPECTED_FILENAMES[5], "IMG_1940.PNG", (round(231 * CANVAS_SIZE[0] / 1284), round(994 * CANVAS_SIZE[0] / 1284), round(1053 * CANVAS_SIZE[0] / 1284)), 0),
    )
    for plate, capture_name, (capture_x, capture_y, capture_right), top_trim in capture_specs:
        expected_capture = _expected_capture(
            capture_name, capture_right - capture_x, top_trim
        )
        with Image.open(FINAL_DIR / plate) as image:
            embedded = image.convert("RGB").crop(
                (capture_x, capture_y, capture_right, CANVAS_SIZE[1])
            )
        expected_crop = expected_capture.crop(
            (0, 0, capture_right - capture_x, embedded.height)
        )
        if ImageChops.difference(embedded, expected_crop).getbbox() is not None:
            raise AssertionError(f"{plate}: embedded capture differs from {capture_name}")
    print("PASS: 6 Build 30 plates and 4 supplemental captures; 1242x2688; RGB; embedded captures verified.")


if __name__ == "__main__":
    main()
