# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow>=11"]
# ///
"""Draws the Sonifine app icon: the scale of a volume knob on near black, its
lit marks running from teal through green to lime."""

import math
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).parent.parent / "App/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
SIZE = 1024
SCALE = 4  # draw large and scale down, for smooth edges
S = SIZE * SCALE
CENTRE_X = S / 2
CENTRE_Y = S / 2 + 0.03 * S  # the open bottom makes the scale look high; lower it a little

MARKS = 15  # the steps on the scale
LIT = 9  # index of the last lit mark
START, SWEEP = 135, 270  # degrees, clockwise from the positive x-axis
INNER, OUTER = 0.24 * S, 0.37 * S  # where the marks begin and end
WIDTH = 0.05 * S
TOP, BOTTOM = (18, 28, 24), (4, 9, 7)  # background, dark green to near black
LIT_COLOURS = [(30, 200, 200), (40, 215, 120), (190, 235, 70)]  # teal, green, lime
DIM = (36, 54, 45)  # unlit marks


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def gradient(t):
    """The colour at t (0–1) along the lit colours."""
    t *= len(LIT_COLOURS) - 1
    i = min(int(t), len(LIT_COLOURS) - 2)
    return mix(LIT_COLOURS[i], LIT_COLOURS[i + 1], t - i)


def point_at(x, y, angle, radius):
    return x + radius * math.cos(angle), y + radius * math.sin(angle)


def point(angle, radius):
    """A point on the scale, at an angle in degrees from the centre."""
    return point_at(CENTRE_X, CENTRE_Y, math.radians(angle), radius)


def stroke(draw, start, end, width, colour):
    """A line with rounded ends, drawn as a capsule outline."""
    (x1, y1), (x2, y2) = start, end
    direction = math.atan2(y2 - y1, x2 - x1)
    half = range(-90, 91, 3)  # a half circle, in degrees around each end
    outline = [point_at(x2, y2, direction + math.radians(a), width / 2) for a in half]
    outline += [point_at(x1, y1, direction + math.radians(a + 180), width / 2) for a in half]
    draw.polygon(outline, fill=colour)


icon = Image.new("RGB", (S, S))
draw = ImageDraw.Draw(icon)
for y in range(S):
    draw.line([(0, y), (S, y)], fill=mix(TOP, BOTTOM, y / (S - 1)))

for i in range(MARKS):
    angle = START + SWEEP * i / (MARKS - 1)
    colour = gradient(i / LIT) if i <= LIT else DIM
    stroke(draw, point(angle, INNER + WIDTH / 2), point(angle, OUTER - WIDTH / 2), WIDTH, colour)

icon.resize((SIZE, SIZE), Image.LANCZOS).save(OUT)
print(OUT)
