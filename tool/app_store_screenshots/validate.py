#!/usr/bin/env python3
"""Validate EAST.'s final App Store screenshots and generated metadata."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[2]
SCREENSHOT_ROOT = (
    REPO_ROOT / "artifacts/app_store/screenshots/en-US/iphone_6_9"
)
FINAL_DIR = SCREENSHOT_ROOT / "final"
MANIFEST_PATH = SCREENSHOT_ROOT / "manifest.json"
EXPECTED_FILENAMES = [
    "01_ask_from_your_heart.png",
    "02_one_wisdom_each_day.png",
    "03_keep_what_stays.png",
    "04_write_what_remains.png",
    "05_a_publication_of_what_you_kept.png",
]
EXPECTED_HEADLINES = [
    "Ask from your heart.",
    "One quiet moment. One wisdom each day.",
    "Keep what stays.",
    "Write what remains.",
    "A quiet publication of what you kept.",
]


def _sha256(path: Path) -> str:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return digest


def main() -> None:
    actual = sorted(path.name for path in FINAL_DIR.glob("*.png"))
    if actual != EXPECTED_FILENAMES:
        raise AssertionError(f"Unexpected final PNG set: {actual}")

    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    entries = manifest["files"]
    if [entry["filename"] for entry in entries] != EXPECTED_FILENAMES:
        raise AssertionError("Manifest filename order does not match the storyboard.")
    if [entry["headline"] for entry in entries] != EXPECTED_HEADLINES:
        raise AssertionError("Manifest headlines do not match the approved copy.")

    for entry in entries:
        path = FINAL_DIR / entry["filename"]
        with Image.open(path) as image:
            image.load()
            if image.format != "PNG":
                raise AssertionError(f"{path.name}: format is {image.format}")
            if image.size != (1320, 2868):
                raise AssertionError(f"{path.name}: size is {image.size}")
            if image.mode != "RGB":
                raise AssertionError(f"{path.name}: mode is {image.mode}")
            if "A" in image.getbands() or "transparency" in image.info:
                raise AssertionError(f"{path.name}: alpha/transparency detected")
            if not image.info.get("icc_profile"):
                raise AssertionError(f"{path.name}: embedded sRGB profile missing")
        if entry["sha256"] != _sha256(path):
            raise AssertionError(f"{path.name}: SHA-256 mismatch")
        if entry["file_size_bytes"] != path.stat().st_size:
            raise AssertionError(f"{path.name}: file-size metadata mismatch")

    print("PASS: 5 PNGs; 1320x2868; RGB; opaque; embedded sRGB; manifest hashes valid.")


if __name__ == "__main__":
    main()
