# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow>=11"]
# ///
"""Draws the Sonifine app icon: a flat volume dial with a few bold steps, more than half lit."""

import math
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).parent.parent / "App/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
SIZE = 1024
SCALE = 4  # draw large and scale down, for smooth edges
S = SIZE * SCALE
CENTRE = S / 2

TICKS = 13  # the steps on the dial
LIT = 8  # index of the last lit step
START, SWEEP = 135, 270  # degrees, clockwise from the positive x-axis
TOP, BOTTOM = (26, 40, 88), (10, 16, 40)  # background, navy to near black
ORANGE, PINK = (255, 170, 80), (255, 70, 140)  # lit steps, first to last
DIM = (52, 66, 110)  # unlit steps
KNOB, WHITE = (40, 54, 100), (255, 255, 255)


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def point_at(x, y, angle, radius):
    return x + radius * math.cos(angle), y + radius * math.sin(angle)


def point(angle, radius):
    """A point on the dial, at an angle in degrees from the centre."""
    return point_at(CENTRE, CENTRE, math.radians(angle), radius)


def circle(x, y, radius):
    return [x - radius, y - radius, x + radius, y + radius]


def stroke(draw, start, end, width, colour):
    """A line with rounded ends, drawn as a capsule outline."""
    (x1, y1), (x2, y2) = start, end
    direction = math.atan2(y2 - y1, x2 - x1)
    half = range(-90, 91, 5)  # a half circle, in degrees around each end
    outline = [point_at(x2, y2, direction + math.radians(a), width / 2) for a in half]
    outline += [point_at(x1, y1, direction + math.radians(a + 180), width / 2) for a in half]
    draw.polygon(outline, fill=colour)


icon = Image.new("RGB", (S, S))
draw = ImageDraw.Draw(icon)
for y in range(S):
    draw.line([(0, y), (S, y)], fill=mix(TOP, BOTTOM, y / (S - 1)))

for i in range(TICKS):
    angle = START + SWEEP * i / (TICKS - 1)
    colour = mix(ORANGE, PINK, i / LIT) if i <= LIT else DIM
    stroke(draw, point(angle, 0.27 * S), point(angle, 0.37 * S), 0.045 * S, colour)

knob = 0.18 * S
draw.ellipse(circle(CENTRE, CENTRE, knob), fill=KNOB)
level = START + SWEEP * LIT / (TICKS - 1)
stroke(draw, point(level, 0.35 * knob), point(level, 0.75 * knob), 0.035 * S, WHITE)

icon.resize((SIZE, SIZE), Image.LANCZOS).save(OUT)
print(OUT)
