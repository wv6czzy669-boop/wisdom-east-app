#!/usr/bin/env python3
"""Reproduce EAST.'s full-glyph Noto Regular production font assets.

Requires FontTools 4.59.1. The script downloads only pinned Google Fonts
distribution binaries, verifies their SHA-256 hashes, instantiates the axes
used by EAST., preserves the complete cmap and shaping tables, and verifies
the generated controlled-copy glyph inventories.
"""

from __future__ import annotations

import hashlib
import subprocess
import sys
import tempfile
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from fontTools.ttLib import TTFont


ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIRECTORY = ROOT / "assets" / "fonts"
INVENTORY_DIRECTORY = OUTPUT_DIRECTORY / "glyphs"


@dataclass(frozen=True)
class FontBuild:
    tag: str
    url: str
    source_sha256: str
    output_name: str
    output_sha256: str
    axes: tuple[str, ...]
    required_tables: tuple[str, ...] = ("GDEF", "GPOS", "GSUB")


FONTS = (
    FontBuild(
        "ja",
        "https://raw.githubusercontent.com/google/fonts/main/ofl/"
        "notoserifjp/NotoSerifJP%5Bwght%5D.ttf",
        "2fd527ba12b6a44ec30d796d633360da0aeba6c5d4af1304ce12bb4dc15a7dfc",
        "NotoSerifJP-Regular.ttf",
        "83181245ea893229f7f171b9de600d48a58ec607ef46cc3bd11d3d66bdd88fbd",
        ("wght=400",),
    ),
    FontBuild(
        "ko",
        "https://raw.githubusercontent.com/google/fonts/main/ofl/"
        "notoserifkr/NotoSerifKR%5Bwght%5D.ttf",
        "11f8d5de6f1b79195efba3828aaa2ec95c1178f5ae976fb23c8d53250a9938f3",
        "NotoSerifKR-Regular.ttf",
        "83d1e17d404ffcb6310c89b3def464617cc4831a5fd89af2e58674bd62812b8b",
        ("wght=400",),
    ),
    FontBuild(
        "zh-Hant",
        "https://raw.githubusercontent.com/google/fonts/main/ofl/"
        "notoseriftc/NotoSerifTC%5Bwght%5D.ttf",
        "0077e18f57c6908f4a000969880940bdb0dad057c0e8d98b49dc364c3d1b09c6",
        "NotoSerifTC-Regular.ttf",
        "703a18dc5b811877ae0bb8aea24a5c61edff3c045fc7abb471c91b54963c1e7f",
        ("wght=400",),
    ),
    FontBuild(
        "ar",
        "https://raw.githubusercontent.com/google/fonts/main/ofl/"
        "notonaskharabic/NotoNaskhArabic%5Bwght%5D.ttf",
        "67b5a525a661b607971fbd3f96a81b89d3a768e74534fca84f18ac97e6fab72f",
        "NotoNaskhArabic-Regular.ttf",
        "0919edeba540a6b27875d4651f2bf26dcbae00324b4bb034f7a030f7f294d381",
        ("wght=400",),
    ),
    FontBuild(
        "th",
        "https://raw.githubusercontent.com/google/fonts/main/ofl/"
        "notoserifthai/NotoSerifThai%5Bwdth%2Cwght%5D.ttf",
        "34a7ad11647c845303aabdde639059806c56b84719e5d2ceb28eb038711bdf53",
        "NotoSerifThai-Regular.ttf",
        "0271d88f4a94c234f47a210f99dc5fb53e2abb50e387d69c20db9c092c5649b1",
        ("wght=400", "wdth=100"),
    ),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_inventory(font_build: FontBuild, output: Path) -> None:
    font = TTFont(output)
    cmap = font.getBestCmap()
    controlled = (INVENTORY_DIRECTORY / f"{font_build.tag}.txt").read_text(
        encoding="utf-8"
    )
    missing_codepoints = sorted(
        {ord(character) for character in controlled if not character.isspace()}
        - set(cmap)
    )
    if missing_codepoints:
        formatted = ", ".join(f"U+{value:04X}" for value in missing_codepoints)
        raise RuntimeError(f"{font_build.tag} inventory missing: {formatted}")
    missing_tables = set(font_build.required_tables) - set(font.keys())
    if missing_tables:
        raise RuntimeError(
            f"{font_build.tag} lost shaping tables: {sorted(missing_tables)}"
        )
    if "fvar" in font:
        raise RuntimeError(f"{font_build.tag} output is still variable")


def main() -> None:
    if __import__("fontTools").__version__ != "4.59.1":
        raise RuntimeError("Install the pinned build dependency: fonttools==4.59.1")
    with tempfile.TemporaryDirectory(prefix="east-noto-") as temporary:
        temporary_directory = Path(temporary)
        for build in FONTS:
            source = temporary_directory / f"{build.tag}-source.ttf"
            urllib.request.urlretrieve(build.url, source)
            if sha256(source) != build.source_sha256:
                raise RuntimeError(f"Upstream SHA-256 mismatch for {build.tag}")
            output = OUTPUT_DIRECTORY / build.output_name
            subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "fontTools.varLib.instancer",
                    str(source),
                    *build.axes,
                    "--update-name-table",
                    "--no-recalc-timestamp",
                    "-o",
                    str(output),
                ],
                check=True,
            )
            if sha256(output) != build.output_sha256:
                raise RuntimeError(f"Generated SHA-256 mismatch for {build.tag}")
            verify_inventory(build, output)
            print(f"{build.tag}: {output.name} {output.stat().st_size} bytes")


if __name__ == "__main__":
    main()
