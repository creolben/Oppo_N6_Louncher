#!/usr/bin/env python3
"""High-resolution ASCII crops to READ text glyph shapes."""
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

def crop_read(path, box, label, px_per_char=3):
    img = Image.open(path).convert('RGB')
    W, H = img.size
    l, t, r, b = [int(v*W if i%2==0 else v*H) for i,v in enumerate(box)] if all(v<=1 for v in box) else (int(box[0]),int(box[1]),int(box[2]),int(box[3]))
    crop = img.crop((l, t, r, b))
    cw, ch = r-l, b-t
    cols = cw // px_per_char
    rows = ch // px_per_char
    small = crop.resize((cols, rows), Image.LANCZOS)
    p = small.load()
    print(f"\n--- {label} [{l},{t}]-[{r},{b}] ({cw}x{ch}), {px_per_char}px/char ---")
    for y in range(rows):
        print(''.join(classify(*p[x,y]) for x in range(cols)))

nf = "/Users/benjerome/Documents/Dev/mylauncher/.agent-shots/fingerprint-removed/lock-screen-no-fingerprint.png"
print("############ NO-FINGERPRINT LOCK SCREEN — reading text zones ############")
crop_read(nf, (60, 30, 420, 100), "TOP-LEFT: status bar / LOCKED row", 3)
crop_read(nf, (420, 30, 1080, 100), "TOP-RIGHT: battery row", 3)
crop_read(nf, (300, 280, 860, 480), "CLOCK DIGITS", 3)
crop_read(nf, (280, 470, 880, 560), "DATE LINE below clock", 3)
crop_read(nf, (60, 600, 400, 800), "MYSTERY CYAN BLOCK", 3)
crop_read(nf, (560, 120, 1080, 280), "UPPER-RIGHT BUBBLE(S)", 3)