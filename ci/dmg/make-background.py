#!/usr/bin/env python3
"""Generate the drag-to-install .dmg background used by ci/dmg/appdmg.json.

Produces a light, branded background (title + arrow + hint) at 1x and 2x, then
combine them into a HiDPI TIFF that appdmg reads:

    python3 ci/dmg/make-background.py
    tiffutil -cathidpicheck ci/dmg/background.png ci/dmg/background@2x.png \
        -out ci/dmg/background.tiff

A light background keeps the Finder icon labels ("DeskCast.app" / "Applications")
readable in both light and dark system appearance.
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 2  # retina supersample
W, H = 640 * S, 400 * S
HELV = "/System/Library/Fonts/Helvetica.ttc"
LOGO = "../../../deskcast-landing/public/app-icon.png"  # optional brand mark
APP_X, APPS_X, ICON_Y = 165 * S, 475 * S, 200 * S  # must match appdmg.json


def font(size, bold=False):
    return ImageFont.truetype(HELV, size * S, index=1 if bold else 0)


def main() -> None:
    img = Image.new("RGB", (W, H), (244, 246, 249))
    dr = ImageDraw.Draw(img)

    top, bot = (247, 249, 252), (231, 235, 240)
    for y in range(H):
        t = y / (H - 1)
        dr.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))

    def soft_shadow(cx, cy, rx, ry, alpha):
        mask = Image.new("L", (W, H), 0)
        ImageDraw.Draw(mask).ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=alpha)
        mask = mask.filter(ImageFilter.GaussianBlur(22 * S))
        img.paste(Image.new("RGB", (W, H), (60, 70, 90)), (0, 0), mask)

    soft_shadow(APP_X, ICON_Y + 30 * S, 62 * S, 30 * S, 40)
    soft_shadow(APPS_X, ICON_Y + 30 * S, 62 * S, 30 * S, 34)

    try:
        logo = Image.open(LOGO).convert("RGBA").resize((40 * S, 40 * S), Image.LANCZOS)
        ls = 40 * S
    except Exception:
        logo, ls = None, 0
    wf = font(26, bold=True)
    word = "DeskCast"
    ww = dr.textlength(word, font=wf)
    gap = 12 * S
    total = (ls + gap if logo else 0) + ww
    bx, by = (W - total) // 2, 34 * S
    if logo:
        img.paste(logo, (int(bx), int(by - 2 * S)), logo)
    dr.text((bx + (ls + gap if logo else 0), by), word, font=wf, fill=(28, 38, 64))

    tf = font(12)
    tag = "Menu-bar capture toolbox for macOS"
    dr.text(((W - dr.textlength(tag, font=tf)) // 2, 78 * S), tag, font=tf, fill=(120, 128, 140))

    ax0, ax1, ay, acol, lw, hh = 250 * S, 388 * S, ICON_Y, (150, 160, 176), 3 * S, 12 * S
    dr.line([(ax0, ay), (ax1 - 6 * S, ay)], fill=acol, width=lw)
    dr.line([(ax1 - hh, ay - hh), (ax1, ay)], fill=acol, width=lw)
    dr.line([(ax1 - hh, ay + hh), (ax1, ay)], fill=acol, width=lw)

    hf = font(12)
    hint = "Drag DeskCast onto Applications to install"
    dr.text(((W - dr.textlength(hint, font=hf)) // 2, 340 * S), hint, font=hf, fill=(140, 148, 160))

    img.resize((640, 400), Image.LANCZOS).save("ci/dmg/background.png")
    img.save("ci/dmg/background@2x.png")
    print("wrote ci/dmg/background.png + background@2x.png")


if __name__ == "__main__":
    main()
