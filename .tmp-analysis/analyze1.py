#!/usr/bin/env python3
"""Programmatic screenshot analysis: color grid maps, luminance stats, region breakdown.
I cannot view images directly, so this extracts objective visual data."""
import sys
from PIL import Image

def classify(r, g, b):
    # returns a char classifying the pixel color
    mx, mn = max(r,g,b), min(r,g,b)
    lum = 0.2126*r + 0.7152*g + 0.0722*b
    if lum < 12: return ' '   # pitch black
    if lum < 35: return '.'   # near black
    if mx - mn < 18:
        if lum > 200: return 'W'  # bright white
        if lum > 120: return 'w'  # mid gray-white
        if lum > 60:  return 'g'  # gray
        return ','                  # dark gray
    # hue-ish classification
    if g > r and b > r:  # cyan/blue family
        if lum > 150: return 'C'
        if lum > 70:  return 'c'
        return 'b'
    if b > r and b >= g:  # blue/purple family
        if r > 80: return 'p'  # purple
        if lum > 100: return 'B'
        return 'B' if lum > 60 else 'n'  # navy/indigo
    if r > g and r > b:  # red/orange/yellow family
        if g > 100: return 'y'  # yellow
        if g > 60: return 'o'  # orange
        return 'r'  # red
    return '?'

def analyze(path, cols=44, label=""):
    img = Image.open(path).convert('RGB')
    W, H = img.size
    rows = max(10, int(cols * H / W * 0.45))  # aspect-corrected (chars ~2x tall)
    small = img.resize((cols, rows), Image.LANCZOS)
    px = small.load()
    print(f"\n{'='*70}")
    print(f"IMAGE: {label} ({path.split('/')[-1]})  {W}x{H}")
    print(f"grid {cols}x{rows}")
    print('='*70)
    # full-sample luminance stats
    small_stats = img.resize((200, 200), Image.LANCZOS)
    lums = []
    for y in range(200):
        for x in range(200):
            r,g,b = small_stats.getpixel((x,y))
            lums.append(0.2126*r+0.7152*g+0.0722*b)
    lums.sort()
    print(f"luminance: min={lums[0]:.0f} p10={lums[2000]:.0f} p50={lums[10000]:.0f} p90={lums[18000]:.0f} p99={lums[19800]:.0f} max={lums[-1]:.0f}")
    print(f"pct pixels >150 lum (bright text/icons): {sum(1 for l in lums if l>150)/400:.1f}%")
    print(f"pct pixels >60 lum: {sum(1 for l in lums if l>60)/400:.1f}%")
    # color map
    for y in range(rows):
        line = ''
        for x in range(cols):
            r,g,b = px[x,y]
            line += classify(r,g,b)
        print(line)
    # dominant colors of whole image
    q = img.convert('P', palette=Image.ADAPTIVE, colors=8).convert('RGB')
    from collections import Counter
    cnt = Counter(q.getdata())
    print("dominant colors:", [(f"#{r:02x}{g:02x}{b:02x}", c) for (r,g,b),c in cnt.most_common(6)])

for path, label in [
    ("/Users/benjerome/Documents/Dev/mylauncher/.agent-shots/polish/09-lock-final.png", "LOCK SCREEN (polish final)"),
    ("/Users/benjerome/Documents/Dev/mylauncher/.agent-shots/fingerprint-removed/lock-screen-no-fingerprint.png", "LOCK SCREEN (current, no fingerprint)"),
]:
    analyze(path, cols=44, label=label)