# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow>=11"]
# ///
"""Draws the Sonifine app icon: a volume dial with many fine steps, about two thirds up."""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).parent.parent / "App/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
SIZE = 1024
SCALE = 4  # draw large and scale down, for smooth edges
S = SIZE * SCALE
CENTRE = S / 2

TICKS = 57  # the steps on the dial
LEVEL = 0.68  # share of the steps that light up
START, SWEEP = 135, 270  # degrees, clockwise from the positive x-axis
LIT = round((TICKS - 1) * LEVEL)  # index of the last lit step
CYAN, VIOLET, PINK = (94, 224, 255), (150, 120, 255), (255, 140, 214)


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def lit_colour(t):
    """Cyan through violet to pink along the lit part of the dial."""
    return mix(CYAN, VIOLET, t * 2) if t < 0.5 else mix(VIOLET, PINK, t * 2 - 1)


def step_angle(i):
    return START + SWEEP * i / (TICKS - 1)


def point(angle, radius):
    a = math.radians(angle)
    return CENTRE + radius * math.cos(a), CENTRE + radius * math.sin(a)


def circle(x, y, radius):
    """The bounding box of a circle, as Pillow's ellipse takes it."""
    return [x - radius, y - radius, x + radius, y + radius]


def background():
    """A diagonal gradient from deep violet to near black, lit softly from the top left."""
    small = Image.new("RGB", (256, 256))
    top, bottom = (58, 34, 128), (10, 8, 32)
    small.putdata([mix(top, bottom, min(1, (x + y) / 400)) for y in range(256) for x in range(256)])
    image = small.resize((S, S), Image.BICUBIC)
    light = Image.new("L", (S, S), 0)
    ImageDraw.Draw(light).ellipse([-S * 0.3, -S * 0.3, S * 0.6, S * 0.6], fill=70)
    light = light.filter(ImageFilter.GaussianBlur(S * 0.12))
    return Image.composite(Image.new("RGB", (S, S), (140, 110, 255)), image, light)


def ticks(draw, lit_only, width_scale=1.0):
    inner, outer = 0.300 * S, 0.365 * S
    width = round(0.0125 * S * width_scale)
    for i in range(TICKS):
        if lit_only and i > LIT:
            continue
        angle = step_angle(i)
        colour = lit_colour(i / LIT) if i <= LIT else (255, 255, 255, 46)
        a, b = point(angle, inner), point(angle, outer)
        draw.line([a, b], fill=colour, width=width)
        for end in (a, b):  # rounded caps
            draw.ellipse(circle(*end, width / 2), fill=colour)


def knob(icon):
    """A raised disc with a light indicator dot pointing at the level."""
    radius = 0.215 * S
    shadow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(shadow).ellipse(circle(CENTRE, CENTRE + S * 0.02, radius), fill=150)
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.03))
    icon.paste((4, 2, 16), mask=shadow)

    disc = Image.new("RGB", (S, S))
    disc_draw = ImageDraw.Draw(disc)
    top, bottom = (72, 58, 140), (30, 22, 70)
    for y in range(round(CENTRE - radius), round(CENTRE + radius) + 1):
        t = (y - (CENTRE - radius)) / (2 * radius)
        disc_draw.line([(0, y), (S, y)], fill=mix(top, bottom, t))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse(circle(CENTRE, CENTRE, radius), fill=255)
    icon.paste(disc, mask=mask)

    draw = ImageDraw.Draw(icon)
    draw.ellipse(circle(CENTRE, CENTRE, radius), outline=(150, 130, 230), width=round(S * 0.004))  # rim

    x, y = point(step_angle(LIT), radius * 0.68)
    dot = S * 0.026
    glow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(glow).ellipse(circle(x, y, dot * 2), fill=200)
    icon.paste(lit_colour(1), mask=glow.filter(ImageFilter.GaussianBlur(dot)))
    draw.ellipse(circle(x, y, dot), fill=(255, 255, 255))


icon = background()

glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ticks(ImageDraw.Draw(glow), lit_only=True, width_scale=2.5)
glow = glow.filter(ImageFilter.GaussianBlur(S * 0.022))
icon.paste(glow, mask=glow.getchannel("A").point(lambda a: min(255, a * 1.1)))

layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ticks(ImageDraw.Draw(layer), lit_only=False)
icon.paste(layer, mask=layer)

knob(icon)

icon.resize((SIZE, SIZE), Image.LANCZOS).save(OUT)
print(OUT)
