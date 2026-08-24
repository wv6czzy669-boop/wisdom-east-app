#!/usr/bin/env python3
"""EAST. Phase 5F-A -- deterministic validation of `localized_final/`.

Standalone; does not touch `compose.py`/`validate.py`. Checks file
existence/count, PNG decode, exact dimension parity with the English
masters, plate-order/no-duplicate integrity, and manifest/copy-matrix
parity. Never uses OCR -- see `EnglishMasterDifferenceAudit` in the phase
report for the paired visual-inspection evidence this defers to.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

import localize_screenshots as core

OUT_ROOT = core.OUT_ROOT
CANVAS = core.CANVAS
LOCALES = core.LOCALES
FORBIDDEN_LOCALE_DIRS = {"pt", "pt-PT", "zh", "zh-Hans", "zh-CN"}


def main() -> int:
    failures: list[str] = []

    existing_dirs = {p.name for p in OUT_ROOT.iterdir() if p.is_dir()}
    for forbidden in FORBIDDEN_LOCALE_DIRS:
        if forbidden in existing_dirs:
            failures.append(f"forbidden locale directory present: {forbidden}")

    missing_locale_dirs = set(LOCALES) - existing_dirs
    if missing_locale_dirs:
        failures.append(f"missing locale directories: {sorted(missing_locale_dirs)}")

    extra_dirs = existing_dirs - set(LOCALES)
    if extra_dirs:
        failures.append(f"unexpected extra directories: {sorted(extra_dirs)}")

    total_pngs = 0
    en_hashes: dict[str, tuple[int, int]] = {}
    seen_shas: dict[str, list[str]] = {}
    import hashlib

    for locale in LOCALES:
        locale_dir = OUT_ROOT / locale
        if not locale_dir.is_dir():
            continue
        plate_files = sorted(p.name for p in locale_dir.glob("[0-9][0-9].png"))
        expected = [f"{i:02d}.png" for i in range(1, 10)]
        if plate_files != expected:
            failures.append(f"{locale}: expected exactly {expected}, found {plate_files}")
        if not (locale_dir / "contact_sheet.png").exists():
            failures.append(f"{locale}: missing contact_sheet.png")

        for plate in expected:
            path = locale_dir / plate
            if not path.exists():
                failures.append(f"{locale}/{plate}: missing")
                continue
            total_pngs += 1
            try:
                with Image.open(path) as img:
                    img.verify()
                with Image.open(path) as img:
                    size = img.size
                    fmt = img.format
            except Exception as exc:  # noqa: BLE001
                failures.append(f"{locale}/{plate}: failed to decode ({exc})")
                continue
            if fmt != "PNG":
                failures.append(f"{locale}/{plate}: not a PNG (format={fmt})")
            if size != CANVAS:
                failures.append(f"{locale}/{plate}: dimension {size} != canonical {CANVAS}")
            if locale == "en":
                en_hashes[plate] = size
            else:
                if plate in en_hashes and en_hashes[plate] != size:
                    failures.append(f"{locale}/{plate}: dimension {size} != en {en_hashes[plate]}")

            sha = hashlib.sha256(path.read_bytes()).hexdigest()
            seen_shas.setdefault(sha, []).append(f"{locale}/{plate}")

    for sha, paths in seen_shas.items():
        by_locale: dict[str, list[str]] = {}
        for entry in paths:
            loc, plate = entry.split("/")
            by_locale.setdefault(loc, []).append(plate)
        for loc, plates in by_locale.items():
            if len(plates) > 1:
                failures.append(f"{loc}: duplicate/misassigned plate content across {plates}")

    if total_pngs != 135:
        failures.append(f"total upload PNGs = {total_pngs}, expected 135")

    manifest_path = OUT_ROOT / "manifest.json"
    matrix_path = OUT_ROOT / "copy_matrix.json"
    if not manifest_path.exists():
        failures.append("manifest.json missing")
    else:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if len(manifest) != 135:
            failures.append(f"manifest.json has {len(manifest)} records, expected 135")
        manifest_files = {(r["locale"], r["plate"]) for r in manifest}
        expected_pairs = {(loc, f"{i:02d}") for loc in LOCALES for i in range(1, 10)}
        if manifest_files != expected_pairs:
            failures.append("manifest.json locale/plate pairs do not match the expected 15x9 set")
        for r in manifest:
            if r["dimension_validation"] != "PASS":
                failures.append(f"manifest {r['locale']}/{r['plate']}: dimension_validation != PASS")

    if not matrix_path.exists():
        failures.append("copy_matrix.json missing")
    else:
        matrix = json.loads(matrix_path.read_text(encoding="utf-8"))
        expected_matrix_rows = 15 * 9
        if len(matrix) != expected_matrix_rows:
            failures.append(f"copy_matrix.json has {len(matrix)} rows, expected {expected_matrix_rows}")
        unresolved = [r for r in matrix if r["status"] != "APPROVED"]
        if unresolved:
            failures.append(f"copy_matrix.json has {len(unresolved)} UNRESOLVED rows")
        for r in matrix:
            if "EAST." in r["english_source_copy"] and "EAST." not in r["final_localized_copy"]:
                failures.append(
                    f"copy_matrix {r['locale']}/{r['plate']}: EAST. brand token dropped in translation"
                )

    overview_path = OUT_ROOT / "all_locales_overview.png"
    if not overview_path.exists():
        failures.append("all_locales_overview.png missing")

    print(f"Total upload PNGs found: {total_pngs}")
    print(f"Locale directories: {len(existing_dirs & set(LOCALES))}/15")
    if failures:
        print(f"\nFAILURES ({len(failures)}):")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("\nAll deterministic checks PASSED.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
