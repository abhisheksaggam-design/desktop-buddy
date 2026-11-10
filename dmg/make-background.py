"""Draws the DMG window background: a tiny Mac desktop with Desktop Buddy's menu bar,
its pop-up, and a path of notifications flying from the app to Applications.

    python3 dmg/make-background.py        (needs Pillow; writes dmg/background.png, @2x, and .tiff)

Window: 640 × 440 pt. Icons are centred at (170, 215) and (470, 215), size 112 (see dmg/settings.py).
The background is a mid-tone slate blue so Finder's icon labels (black in light mode,
white in dark mode) stay readable either way.
"""
import math
import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
W, H = 640, 440
APP_XY, APPS_XY = (170, 215), (470, 215)

TOP, BOTTOM = (116, 146, 181), (99, 128, 160)       # slate blue, label-safe in light and dark
INK = (29, 29, 31)
MAIL, CHAT, MEET = (10, 132, 255), (48, 209, 88), (191, 90, 242)


def font(size, weight, s):
    f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", int(size * s))
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def render(s):
    im = Image.new("RGBA", (W * s, H * s))
    px = im.load()
    for y in range(H * s):                                   # vertical gradient
        t = y / (H * s - 1)
        c = tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)) + (255,)
        for x in range(W * s):
            px[x, y] = c

    # Soft light from the top left, like a desktop wallpaper.
    glow = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([-160 * s, -220 * s, 420 * s, 300 * s], fill=(255, 255, 255, 34))
    im = Image.alpha_composite(im, glow.filter(ImageFilter.GaussianBlur(70 * s)))
    d = ImageDraw.Draw(im)

    # Menu bar.
    bar = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(bar).rectangle([0, 0, W * s, 24 * s], fill=(246, 246, 248, 205))
    im = Image.alpha_composite(im, bar)
    d = ImageDraw.Draw(im)
    icon = Image.open(os.path.join(ROOT, "docs", "app-icon.png")).convert("RGBA")
    im.alpha_composite(icon.resize((16 * s, 16 * s), Image.LANCZOS), (12 * s, 4 * s))
    d.text((34 * s, 12 * s), "Desktop Buddy", font=font(12.5, "Bold", s), fill=INK, anchor="lm")
    x = 136
    for item in ("Mail", "Chat", "Meetings", "Tasks"):
        d.text((x * s, 12 * s), item, font=font(12.5, "Regular", s), fill=INK, anchor="lm")
        x += d.textlength(item, font=font(12.5, "Regular", s)) / s + 18
    d.text(((W - 14) * s, 12 * s), "9:41", font=font(12.5, "Medium", s), fill=INK, anchor="rm")
    bell(d, (W - 58) * s, 12 * s, s)

    # The pop-up ("island") dropping from the top centre.
    cw, ch, cy = 318, 46, 36
    cx0 = (W - cw) / 2
    shadow = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([cx0 * s, (cy + 4) * s, (cx0 + cw) * s, (cy + ch + 4) * s], 23 * s, fill=(0, 0, 0, 70))
    im = Image.alpha_composite(im, shadow.filter(ImageFilter.GaussianBlur(8 * s)))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([cx0 * s, cy * s, (cx0 + cw) * s, (cy + ch) * s], 23 * s, fill=(12, 12, 14, 255))
    im.alpha_composite(icon.resize((30 * s, 30 * s), Image.LANCZOS), (int((cx0 + 9) * s), int((cy + 8) * s)))
    d.text(((cx0 + 48) * s, (cy + 16) * s), "Desktop Buddy", font=font(12, "Semibold", s), fill=(255, 255, 255), anchor="lm")
    d.text(((cx0 + 48) * s, (cy + 31) * s), "Drag me into Applications. I'll keep an eye on things.",
           font=font(11, "Regular", s), fill=(255, 255, 255, 190), anchor="lm")
    d.ellipse([(cx0 + cw - 20) * s, (cy + 20) * s, (cx0 + cw - 14) * s, (cy + 26) * s], fill=(255, 69, 58))

    # Dotted path from the app to Applications, with notifications flying along it.
    p0, p2 = (APP_XY[0] + 68, APP_XY[1] - 22), (APPS_XY[0] - 70, APPS_XY[1] - 22)
    p1 = ((p0[0] + p2[0]) / 2, 120)

    def at(t):
        return ((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
                (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1])

    steps = 60
    for i in range(steps):
        if i % 2:
            continue
        a, b = at(i / steps), at((i + 1) / steps)
        d.line([(a[0] * s, a[1] * s), (b[0] * s, b[1] * s)], fill=(255, 255, 255, 230), width=int(2.5 * s))
    end, before = at(1), at(0.95)
    ang = math.atan2(end[1] - before[1], end[0] - before[0])
    tip = (end[0] + 6 * math.cos(ang), end[1] + 6 * math.sin(ang))
    head = [tip,
            (tip[0] - 13 * math.cos(ang - 0.5), tip[1] - 13 * math.sin(ang - 0.5)),
            (tip[0] - 13 * math.cos(ang + 0.5), tip[1] - 13 * math.sin(ang + 0.5))]
    d.polygon([(x * s, y * s) for x, y in head], fill=(255, 255, 255))

    for t, colour, glyph in ((0.24, MAIL, envelope), (0.5, CHAT, bubble), (0.76, MEET, camera)):
        x, y = at(t)
        r = 13
        sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse([(x - r) * s, (y - r + 3) * s, (x + r) * s, (y + r + 3) * s], fill=(0, 0, 0, 60))
        im = Image.alpha_composite(im, sh.filter(ImageFilter.GaussianBlur(4 * s)))
        d = ImageDraw.Draw(im)
        d.ellipse([(x - r - 2) * s, (y - r - 2) * s, (x + r + 2) * s, (y + r + 2) * s], fill=(255, 255, 255))
        d.ellipse([(x - r) * s, (y - r) * s, (x + r) * s, (y + r) * s], fill=colour)
        glyph(d, x * s, y * s, s)

    # Instructions.
    d.text((W / 2 * s, 344 * s), "Drag Desktop Buddy into Applications", font=font(17, "Semibold", s),
           fill=(255, 255, 255), anchor="mm")
    d.text((W / 2 * s, 370 * s), "First time opening it?  System Settings  ›  Privacy & Security  ›  Open Anyway",
           font=font(11.5, "Regular", s), fill=(255, 255, 255, 205), anchor="mm")
    return im


def bell(d, x, y, s):
    w = 5.5 * s
    d.pieslice([x - w, y - 6 * s, x + w, y + 5 * s], 180, 360, fill=INK)
    d.rectangle([x - w, y - 0.5 * s, x + w, y + 3 * s], fill=INK)
    d.rounded_rectangle([x - w - 1.5 * s, y + 2.5 * s, x + w + 1.5 * s, y + 4.2 * s], 1 * s, fill=INK)
    d.ellipse([x - 1.6 * s, y + 4.5 * s, x + 1.6 * s, y + 7 * s], fill=INK)
    d.ellipse([x + 3 * s, y - 9 * s, x + 11 * s, y - 1 * s], fill=(255, 59, 48))


def envelope(d, x, y, s):
    w, h = 7 * s, 5 * s
    d.rounded_rectangle([x - w, y - h, x + w, y + h], 1.5 * s, outline=(255, 255, 255), width=int(1.6 * s))
    d.line([(x - w + s, y - h + s), (x, y + 0.5 * s), (x + w - s, y - h + s)], fill=(255, 255, 255), width=int(1.6 * s))


def bubble(d, x, y, s):
    d.rounded_rectangle([x - 7 * s, y - 5.5 * s, x + 7 * s, y + 3.5 * s], 4 * s, fill=(255, 255, 255))
    d.polygon([(x - 4 * s, y + 2 * s), (x - 5.5 * s, y + 7 * s), (x + 0.5 * s, y + 3 * s)], fill=(255, 255, 255))


def camera(d, x, y, s):
    d.rounded_rectangle([x - 7.5 * s, y - 4.5 * s, x + 2.5 * s, y + 4.5 * s], 2 * s, fill=(255, 255, 255))
    d.polygon([(x + 3 * s, y - 1 * s), (x + 7.5 * s, y - 4 * s), (x + 7.5 * s, y + 4 * s), (x + 3 * s, y + 1 * s)], fill=(255, 255, 255))


if __name__ == "__main__":
    one, two = os.path.join(HERE, "background.png"), os.path.join(HERE, "background@2x.png")
    render(1).save(one)
    render(2).save(two)
    # One TIFF with both resolutions, so Finder picks the sharp one on Retina displays.
    subprocess.run(["tiffutil", "-cathidpicheck", one, two, "-out", os.path.join(HERE, "background.tiff")],
                   check=True, capture_output=True)
    print("wrote background.png, background@2x.png, background.tiff")
