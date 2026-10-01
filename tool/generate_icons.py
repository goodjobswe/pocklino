"""Regenerate Pocklino's original vector-derived branding and launcher icons.

Requires Pillow and fonttools: python -m pip install pillow fonttools
Run from any directory: python tool/generate_icons.py
Fonts are bundled OFL assets. No network access is needed by this script.
"""
from pathlib import Path
import json
from html import escape
import math

from PIL import Image, ImageDraw, ImageFont
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / 'assets' / 'brand'
SCALE = 16
SIZE = 128 * SCALE
OAT = '#F8F6EF'
INK = '#243C53'
BUTTER = '#F4E4AA'
CORAL = '#DD7C65'
PAPER = '#FFFEFA'


def xy(points):
    return [(x * SCALE, y * SCALE) for x, y in points]


def q(start, control, end, steps=32):
    return [((1-t)**2*start[0]+2*(1-t)*t*control[0]+t*t*end[0],
             (1-t)**2*start[1]+2*(1-t)*t*control[1]+t*t*end[1])
            for t in [i / steps for i in range(steps + 1)]]


def icon_image():
    result = Image.new('RGB', (SIZE, SIZE), OAT)
    slip = Image.new('RGBA', (SIZE, SIZE))
    d = ImageDraw.Draw(slip)
    d.rounded_rectangle((39*SCALE, 25*SCALE, 90*SCALE, 87*SCALE), radius=9*SCALE, fill=BUTTER)
    # Precomposited 55% ink on butter; matches vector mark.
    rule = '#82887A'
    for end, y in [(76, 41), (68, 49)]:
        d.line(xy([(49, y), (end, y)]), fill=rule, width=4*SCALE)
        for x in (49, end):
            d.ellipse(((x-2)*SCALE, (y-2)*SCALE, (x+2)*SCALE, (y+2)*SCALE), fill=rule)
    slip = slip.rotate(9, resample=Image.Resampling.BICUBIC, center=(64*SCALE, 56*SCALE))
    result.paste(slip, (0, 0), slip)
    d = ImageDraw.Draw(result)
    d.ellipse((83*SCALE, 27*SCALE, 99*SCALE, 43*SCALE), fill=CORAL)
    pocket = q((26,53), (26,48), (31,50)) + [(64,63), (97,50)]
    pocket += q((97,50), (102,48), (102,53)) + [(102,87)]
    pocket += q((102,87), (102,103), (86,103)) + [(42,103)]
    pocket += q((42,103), (26,103), (26,87))
    d.polygon(xy(pocket), fill=INK)
    seam = q((42,83), (64,96), (86,83), 100)
    seam_color = '#D3D7D9'
    left, right = [], []
    for i, (x, y) in enumerate(seam):
        tangent_y = 26 - 52 * i / 100
        magnitude = math.hypot(44, tangent_y)
        nx, ny = -tangent_y / magnitude * 1.75, 44 / magnitude * 1.75
        left.append((x + nx, y + ny))
        right.append((x - nx, y - ny))
    d.polygon(xy(left + list(reversed(right))), fill=seam_color)
    for x,y in ((42,83),(86,83)):
        r = 1.75
        d.ellipse(((x-r)*SCALE,(y-r)*SCALE,(x+r)*SCALE,(y+r)*SCALE), fill=seam_color)
    return result


def save_icon(base, path, size):
    path.parent.mkdir(parents=True, exist_ok=True)
    base.resize((size, size), Image.Resampling.LANCZOS).save(path)


def outlined_text(text, font, x, baseline, size, letter_spacing=0):
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    factor = size / font['head'].unitsPerEm
    paths = []
    advance = x
    for char in text:
        glyph_name = cmap[ord(char)]
        pen = SVGPathPen(glyphs)
        transformed = TransformPen(pen, (factor, 0, 0, -factor, advance, baseline))
        glyphs[glyph_name].draw(transformed)
        commands = pen.getCommands()
        if commands:
            paths.append(f'<path d="{commands}"/>')
        advance += glyphs[glyph_name].width * factor + letter_spacing
    return ''.join(paths), advance


def logo_svg():
    display = TTFont(ROOT / 'assets/fonts/Lora-Variable.ttf')
    font = instantiateVariableFont(display, {'wght': 600}, inplace=False)
    # Match the app's Lora 600 wordmark and -1px tracking at 26px.
    title, end = outlined_text('pocklino', font, 145, 78, 59, letter_spacing=-59/26)
    variable = TTFont(ROOT / 'assets/fonts/DMSans-Variable.ttf')
    body = instantiateVariableFont(variable, {'wght': 400, 'opsz': 14}, inplace=False)
    tagline, tag_end = outlined_text('A little space for your life.', body, 147, 104, 15)
    width = round(max(end, tag_end) + 24)
    mark = (BRAND / 'mark.svg').read_text(encoding='utf-8-sig')
    mark_content = mark.split('>', 1)[1].rsplit('</svg>', 1)[0]
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} 128" role="img" '
            f'aria-label="{escape("Pocklino. A little space for your life.")}">'
            f'{mark_content}<g fill="{INK}">{title}</g><g fill="#6B777B">{tagline}</g></svg>')


def main():
    BRAND.mkdir(parents=True, exist_ok=True)
    base = icon_image()
    save_icon(base, BRAND / 'app-icon.png', 1024)
    (BRAND / 'logo.svg').write_text(logo_svg(), encoding='utf-8')
    for density, size in {'mdpi':48, 'hdpi':72, 'xhdpi':96, 'xxhdpi':144, 'xxxhdpi':192}.items():
        save_icon(base, ROOT / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', size)
    ios = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    contents = json.loads((ios / 'Contents.json').read_text())
    for item in contents['images']:
        size = round(float(item['size'].split('x')[0]) * float(item['scale'].rstrip('x')))
        save_icon(base, ios / item['filename'], size)
    for name, size in {'Icon-192.png':192, 'Icon-512.png':512,
                       'Icon-maskable-192.png':192, 'Icon-maskable-512.png':512}.items():
        save_icon(base, ROOT / 'web/icons' / name, size)
    save_icon(base, ROOT / 'web/favicon.png', 32)
    windows = ROOT / 'windows/runner/resources/app_icon.ico'
    if windows.parent.exists():
        base.resize((256, 256), Image.Resampling.LANCZOS).save(
            windows, sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
    print('Generated outlined logo, 1024px brand icon, Android/iOS/web/Windows icons.')


if __name__ == '__main__':
    main()
