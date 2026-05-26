#!/usr/bin/env python3
"""Crop the AI-generated icon source to 1024x1024 with transparent squircle corners,
then emit all macOS AppIcon sizes into Assets.xcassets/AppIcon.appiconset.
"""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


DEFAULT_SRC = Path(
    "/Users/el-muncho/.cursor/projects/Users-el-muncho-projects-gamemonitor/assets/app_icon_source_v4.png"
)
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SRC
DST_DIR = Path("/Users/el-muncho/projects/gamemonitor/GameMonitor/Assets.xcassets/AppIcon.appiconset")
WORK_DIR = Path("/Users/el-muncho/projects/gamemonitor/scripts/_build")


def squircle_mask(size: int, radius_ratio: float = 0.225) -> Image.Image:
    """Apple-style superellipse approximation via heavy rounded rect with antialiasing."""
    upscale = 4
    big = size * upscale
    radius = int(big * radius_ratio)
    mask = Image.new("L", (big, big), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, big - 1, big - 1), radius=radius, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"source image not found: {SRC}")

    DST_DIR.mkdir(parents=True, exist_ok=True)
    WORK_DIR.mkdir(parents=True, exist_ok=True)

    src = Image.open(SRC).convert("RGBA")
    w, h = src.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    cropped = src.crop((left, top, left + side, top + side))

    base_size = 1024
    base = cropped.resize((base_size, base_size), Image.LANCZOS)

    mask = squircle_mask(base_size)
    masked = Image.new("RGBA", (base_size, base_size), (0, 0, 0, 0))
    masked.paste(base, (0, 0), mask=mask)

    base_path = WORK_DIR / "icon_1024_master.png"
    masked.save(base_path, optimize=True)
    print(f"[ok] master 1024×1024 → {base_path}")

    sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    for filename, size in sizes:
        if size == base_size:
            img = masked
        else:
            scale_mask = squircle_mask(size)
            scaled = base.resize((size, size), Image.LANCZOS)
            img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            img.paste(scaled, (0, 0), mask=scale_mask)
        out = DST_DIR / filename
        img.save(out, optimize=True)
        print(f"[ok] {filename} ({size}×{size})")

    contents = {
        "images": [
            {"size": "16x16", "idiom": "mac", "filename": "icon_16x16.png", "scale": "1x"},
            {"size": "16x16", "idiom": "mac", "filename": "icon_16x16@2x.png", "scale": "2x"},
            {"size": "32x32", "idiom": "mac", "filename": "icon_32x32.png", "scale": "1x"},
            {"size": "32x32", "idiom": "mac", "filename": "icon_32x32@2x.png", "scale": "2x"},
            {"size": "128x128", "idiom": "mac", "filename": "icon_128x128.png", "scale": "1x"},
            {"size": "128x128", "idiom": "mac", "filename": "icon_128x128@2x.png", "scale": "2x"},
            {"size": "256x256", "idiom": "mac", "filename": "icon_256x256.png", "scale": "1x"},
            {"size": "256x256", "idiom": "mac", "filename": "icon_256x256@2x.png", "scale": "2x"},
            {"size": "512x512", "idiom": "mac", "filename": "icon_512x512.png", "scale": "1x"},
            {"size": "512x512", "idiom": "mac", "filename": "icon_512x512@2x.png", "scale": "2x"},
        ],
        "info": {"version": 1, "author": "xcode"},
    }
    (DST_DIR / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")

    catalog_contents = {"info": {"version": 1, "author": "xcode"}}
    (DST_DIR.parent / "Contents.json").write_text(json.dumps(catalog_contents, indent=2) + "\n")

    shutil.rmtree(WORK_DIR, ignore_errors=True)
    print("[done]")


if __name__ == "__main__":
    main()
