#!/usr/bin/env python3
"""Component inventory, downscaled harder for speed."""
from PIL import Image
from collections import deque
import sys

def cc_inventory(path, label, scale=4, min_area_px=2000, lum_thresh=90, max_comps=40):
    img = Image.open(path).convert('RGB')
    W, H = img.size
    sw, sh = max(1, W//scale), max(1, H//scale)
    small = img.resize((sw, sh), Image.BOX)
    arr = list(small.getdata())
    lum = [0.2126*r+0.7152*g+0.0722*b for (r,g,b) in arr]
    visited = [False]*(sw*sh)
    comps = []
    for y in range(sh):
        base = y*sw
        for x in range(sw):
            i = base + x
            if visited[i] or lum[i] <= lum_thresh: continue
            q = deque([i]); visited[i] = True
            minx=maxx=x; miny=maxy=y; area=0
            while q:
                ci = q.popleft(); area += 1
                cx, cy = ci % sw, ci // sw
                if cx < minx: minx = cx
                if cx > maxx: maxx = cx
                if cy < miny: miny = cy
                if cy > maxy: maxy = cy
                for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    nx, ny = cx+dx, cy+dy
                    if 0 <= nx < sw and 0 <= ny < sh:
                        ni = ny*sw + nx
                        if not visited[ni] and lum[ni] > lum_thresh:
                            visited[ni] = True; q.append(ni)
            if area*scale*scale >= min_area_px:
                comps.append((area*scale*scale, (minx*scale,miny*scale,maxx*scale,maxy*scale)))
    comps.sort(key=lambda c: -c[0])
    print(f"\n===== {label} ({path.split('/')[-1]}) {W}x{H} (scale {scale}) =====")
    print(f"components >= {min_area_px}px^2: {len(comps)}")
    for area,(x0,y0,x1,y1) in comps[:max_comps]:
        print(f"  {area:>8}px2 ({x0:>4},{y0:>4})-({x1:>4},{y1:>4}) {x1-x0+1:>4}x{y1-y0+1:>4}")

cc_inventory("/Users/benjerome/Documents/Dev/mylauncher/.agent-shots/after-full-galaxy.png", "AFTER-FULL-GALAXY", scale=4)
cc_inventory("/Users/benjerome/Documents/Dev/mylauncher/.agent-shots/posture-inner.png", "POSTURE-INNER", scale=4)
cc_inventory("/Users/benjerome/Documents/Dev/mylauncher/.agent-shots/before-cockpit-blocked.png", "BEFORE-COCKPIT-BLOCKED", scale=4)
sys.stdout.flush()