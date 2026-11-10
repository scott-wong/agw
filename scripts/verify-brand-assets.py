#!/usr/bin/env python3
"""Validate the committed AGW brand asset set without external dependencies."""

from __future__ import annotations

import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
BRANDING = ROOT / "branding"
SVG_FILES = (
    "agw-logo.svg",
    "agw-logo-dark.svg",
    "agw-mark.svg",
    "agw-mark-dark.svg",
    "agw-favicon.svg",
    "agw-github-social.svg",
)
PNG_SIZES = {
    "agw-logo.png": (560, 170),
    "agw-logo-dark.png": (560, 170),
    "agw-mark-16.png": (16, 16),
    "agw-mark-32.png": (32, 32),
    "agw-mark-128.png": (128, 128),
    "agw-mark-512.png": (512, 512),
    "agw-social-preview.png": (1280, 640),
}


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError(f"{path.name} is not a valid PNG")
    return struct.unpack(">II", data[16:24])


def main() -> int:
    for name in SVG_FILES:
        path = BRANDING / name
        ET.parse(path)
        text = path.read_text(encoding="utf-8")
        if "#16AFC4" not in text or not any(
            color in text for color in ("#163653", "#F4F7FB")
        ):
            raise SystemExit(f"{name}: AGW palette is missing")

    for name, expected in PNG_SIZES.items():
        actual = png_size(BRANDING / name)
        if actual != expected:
            raise SystemExit(
                f"{name}: expected {expected[0]}x{expected[1]}, got "
                f"{actual[0]}x{actual[1]}"
            )

    ico = (BRANDING / "favicon.ico").read_bytes()
    reserved, image_type, count = struct.unpack("<HHH", ico[:6])
    expected_ico_sizes = {16, 32, 48, 64, 128, 256}
    if (reserved, image_type, count) != (0, 1, len(expected_ico_sizes)):
        raise SystemExit(
            "favicon.ico: expected 6 images, got "
            f"reserved={reserved} type={image_type} count={count}"
        )
    ico_sizes = {
        (ico[6 + index * 16] or 256, ico[7 + index * 16] or 256)
        for index in range(count)
    }
    if ico_sizes != {(size, size) for size in expected_ico_sizes}:
        raise SystemExit(f"favicon.ico: unexpected image sizes {sorted(ico_sizes)}")

    print("[branding] SVG, PNG, and multi-resolution ICO assets are valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
