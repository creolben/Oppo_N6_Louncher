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

def crop_read(path, box, label, px_per_char=6):
    img = Image.open(path).convert('RGB')
    l, t, r, b = box
    crop = img.crop((l, t, r, b))
    cw, ch = r-l, b-t
    cols = max(20, cw // px_per_char)
    rows = max(8, ch // px_per_char)
    small = crop.resize((cols, rows), Image.LANCZOS)
    p = small.load()
    print(f"\n--- {label} [{l},{t}]-[{r},{b}] ({cw}x{ch}) ---")
    for y in range(rows):
        print(''.join(classify(*p[x,y]) for x in range(cols)))

def lum_stats(path, label):
    img = Image.open(path).convert('RGB')
    st = img.resize((150,150), Image.LANCZOS)
    data = list(st.getdata())
    lums = sorted(0.2126*p[0]+0.7152*p[1]+0.0722*p[2] for p in data)
    n = len(lums)
    print(f"\n== {label}: lum p10={lums[n//10]:.0f} p50={lums[n//2]:.0f} p90={lums[9*n//10]:.0f} p99={lums[99*n//100]:.0f} max={lums[-1]:.0f} | >150: {sum(1 for x in lums if x>150)/n*100:.1f}%  60-150: {sum(1 for x in lums if 60<x<=150)/n*100:.1f}%")

g = "/Users/benjerome/Documents/Dev/mylauncher/.agent-shots/after-full-galaxy.png"
pi = "/Users/benjerome/Documents/Dev/mylauncher/.agent-shots/posture-inner.png"
ck = "/Users/benjerome/Documents/Dev/mylauncher/.agent-shots/before-cockpit-blocked.png"

lum_stats(g, "AFTER-FULL-GALAXY")
lum_stats(pi, "POSTURE-INNER")
lum_stats(ck, "BEFORE-COCKPIT")

# Galaxy: full overview at coarse, then zoom key elements
crop_read(g, (0, 0, 1140, 2616), "GALAXY full overview", 24)
crop_read(g, (300, 1230, 900, 1360), "GALAXY wide element y1230-1360", 4)
crop_read(g, (240, 940, 1020, 1300), "GALAXY bubble trio", 6)
crop_read(g, (300, 2540, 850, 2620), "GALAXY bottom hint", 3)

# Posture-inner: overview + zoom
crop_read(pi, (0, 0, 2248, 2480), "POSTURE-INNER full overview", 40)
crop_read(pi, (700, 2380, 1560, 2500), "POSTURE-INNER bottom hint zone", 4)

# Cockpit: overview + zooms
crop_read(ck, (0, 0, 1140, 2616), "COCKPIT full overview", 24)
crop_read(ck, (400, 200, 800, 420), "COCKPIT top element", 4)
crop_read(ck, (0, 600, 1140, 700), "COCKPIT hairline zone y600-700", 6)
crop_read(ck, (380, 1200, 760, 1420), "COCKPIT text+banner y1200-1420", 4)
crop_read(ck, (100, 1420, 1060, 1960), "COCKPIT bubble grid", 8)