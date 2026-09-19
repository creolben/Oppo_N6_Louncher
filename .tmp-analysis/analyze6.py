#!/usr/bin/env python3
from PIL import Image

def classify(r, g, b):
    mx, mn = max(r,g,b), min(r,g,b)
    lum = 0.2126*r + 0.7152*g + 0.0722*b
    if lum < 12: return ' '
    if lum < 30: return '.'
    if mx - mn < 20:
        if lum > 190: return '#'
        if lum > 110: return '+'
        if lum > 55:  return '-'
        return ','
    if g > r and b > r:
        return 'C' if lum > 100 else 'c'
    if b > r and b >= g:
        return 'P' if lum > 100 else 'p'
    if r > g and r > b:
        return 'R' if lum > 100 else 'r'
    return '?'

def crop_read(path, box, label, px_per_char=4):
    img = Image.open(path).convert('RGB')
    l, t, r, b = box
    crop = img.crop((l, t, r, b))
    cw, ch = r-l, b-t
    cols = cw // px_per_char
    rows = ch // px_per_char
    small = crop.resize((cols, rows), Image.LANCZOS)
    p = small.load()
    print(f"\n--- {label} [{l},{t}]-[{r},{b}] ({cw}x{ch}) ---")
    for y in range(rows):
        print(''.join(classify(*p[x,y]) for x in range(cols)))

nf = "/Users/benjerome/Documents/Dev/mylauncher/.agent-shots/fingerprint-removed/lock-screen-no-fingerprint.png"
# Full chip-row strip
crop_read(nf, (20, 540, 1120, 760), "CHIP ROW full width (y540-760)", 5)
# Tail region below selected chip
crop_read(nf, (330, 700, 700, 1050), "TAIL below chip (y700-1050)", 4)
# Bubble cluster zone with labels
crop_read(nf, (60, 1280, 1080, 1500), "BUBBLE ROW 1 with labels (y1280-1500)", 5)