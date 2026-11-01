# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow>=11"]
# ///
"""Draws the Sonifine app icon: a row of bars that rise in small steps."""

from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
OUT = Path(__file__).parent.parent / "App/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
TOP, BOTTOM = (54, 36, 120), (14, 10, 40)  # deep violet to near black

icon = Image.new("RGB", (SIZE, SIZE))
draw = ImageDraw.Draw(icon)
for y in range(SIZE):
    t = y / (SIZE - 1)
    draw.line([(0, y), (SIZE, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))

bars, left, right, base = 12, 200, 824, 760
gap = 14
width = (right - left - gap * (bars - 1)) / bars
for i in range(bars):
    height = 90 + (440 - 90) * i / (bars - 1)
    x = left + i * (width + gap)
    t = i / (bars - 1)
    colour = tuple(round(a + (b - a) * t) for a, b in zip((120, 220, 255), (255, 255, 255)))
    draw.rounded_rectangle([x, base - height, x + width, base], radius=width / 2, fill=colour)

icon.save(OUT)
print(OUT)
