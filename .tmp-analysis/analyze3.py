#!/usr/bin/env python3
import sys
from PIL import Image

def classify(r, g, b):
    mx, mn = max(r,g,b), min(r,g,b)
    lum = 0.2126*r + 0.7152*g + 0.0722*b
    if lum < 12: return ' '
    if lum < 35: return '.'
    if mx - mn < 18:
        if lum > 200: return 'W'
        if lum > 120: return 'w'
        if lum > 60:  return 'g'
        return ','
    if g > r and b > r:
        if lum > 150: return 'C'
        if lum > 70:  return 'c'
        return 'b'
    if b > r and b >= g:
        if r > 80: return 'p'
        return 'B' if lum > 60 else 'n'
    if r > g and r > b:
        if g > 100: return 'y'
        if g > 60: return 'o'
        return 'r'
    return '?'

def region_map(img, box, cols, label, show_stats=True):
    W, H = img.size
    l, t, r, b = int(box[0]*W), int(box[1]*H), int(box[2]*W), int(box[3]*H)
    crop = img.crop((l, t, r, b))
    cw, ch = r-l, b-t
    rows = max(6, int(cols * ch / cw * 0.5))
    small = crop.resize((cols, rows), Image.LANCZOS)
    px = small.load()
    print(f"\n--- {label}  px[{l},{t} -> {r},{b}] ({cw}x{ch}) ---")
    if show_stats:
        st = crop.resize((100, 100), Image.LANCZOS)
        data = list(st.getdata())
        lums = sorted(0.2126*p[0]+0.7152*p[1]+0.0722*p[2] for p in data)
        n = len(lums)
        bright = sum(1 for x in lums if x > 150)
        mid = sum(1 for x in lums if 60 < x <= 150)
        print(f"lum p10={lums[n//10]:.0f} p50={lums[n//2]:.0f} p90={lums[9*n//10]:.0f} p99={lums[99*n//100]:.0f} | >150: {bright/n*100:.1f}%  60-150: {mid/n*100:.1f}%")
    for y in range(rows):
        print(''.join(classify(*px[x,y]) for x in range(cols)))

# no-fingerprint lock screen: zoom into mystery blocks
img = Image.open("/Users/benjerome/Documents/Dev/mylauncher/.agent-shots/fingerprint-removed/lock-screen-no-fingerprint.png").convert('RGB')
print("############ lock-screen-no-fingerprint.png (1140x2616) ############")
region_map(img, (0.0, 0.0, 1.0, 0.03), 60, "TOP EDGE (status zone)")
region_map(img, (0.05, 0.20, 0.55, 0.42), 56, "MYSTERY BLOCK zone (y 523-1098, left half)")
region_map(img, (0.0, 0.05, 1.0, 0.13), 60, "BUBBLES NEAR TOP zone")
region_map(img, (0.0, 0.90, 1.0, 0.96), 60, "HINT + SHORTCUTS zone")

# Cover screen
img2 = Image.open("/Users/benjerome/Documents/Dev/mylauncher/.agent-shots/polish/08-cover-final.png").convert('RGB')
print("\n############ 08-cover-final.png (folded cover) ############")
region_map(img2, (0.0, 0.0, 1.0, 0.14), 60, "HEADER + BADGE")
region_map(img2, (0.0, 0.14, 1.0, 0.20), 60, "SEARCH PILL")
region_map(img2, (0.0, 0.20, 1.0, 0.42), 60, "ESSENTIALS SHELF")
region_map(img2, (0.0, 0.42, 1.0, 0.50), 60, "SECTOR TABS")
region_map(img2, (0.0, 0.50, 1.0, 0.80), 60, "SECTOR CARD")
region_map(img2, (0.0, 0.92, 1.0, 1.0), 60, "DOCK")