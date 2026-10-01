#!/usr/bin/env python3
# Regenerates every icons/pixel/<name>.png from icons/source/<name>.<ext>:
# center-crops each source to a square (side = the shorter dimension, so
# landscape art crops to its height and portrait art crops to its width)
# before pixelating, so every icon ends up a clean square regardless of the
# source image's aspect ratio. Requires github.com/linuskelsey/pixelator
# checked out as a sibling under ~/projects/PYTHON/pyxelator.
import sys
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path.home() / "projects/PYTHON/pyxelator"))
from pixelator.processor import pixelate

SRC_DIR = Path.home() / "projects/QML/game-picker/icons/source"
OUT_DIR = Path.home() / "projects/QML/game-picker/icons/pixel"
GRID_SIZE = 128

def center_square_crop(img: Image.Image) -> Image.Image:
    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    return img.crop((left, top, left + side, top + side))

fails = []
for src in sorted(SRC_DIR.iterdir()):
    if src.is_dir():
        continue
    name = src.stem
    try:
        img = Image.open(src)
    except Exception as e:
        fails.append((name, str(e)))
        continue
    img = center_square_crop(img)
    out_img = pixelate(img, size=GRID_SIZE, colors=16, scale=8, saturation=1.2)
    out_path = OUT_DIR / f"{name}.png"
    out_img.save(out_path)
    print(f"{out_img.size[0]}x{out_img.size[1]}  {name}")

if fails:
    print("FAILED:", fails)
