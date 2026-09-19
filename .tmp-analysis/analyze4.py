#!/usr/bin/env python3
"""Connected-component inventory of bright objects in each screenshot."""
from PIL import Image
import sys

def cc_inventory(path, label, min_area=200, lum_thresh=90, max_comps=40):
    img = Image.open(path).convert('RGB')
    W, H = img.size
    # downscale 3x for speed: components still meaningful
    sc = img.resize((W//3, H//3), Image.BOX)
    w, h = sc.size
    px = sc.load()
    visited = [[False]*w for _ in range(h)]
    comps = []
    import sys
    sys.setrecursionlimit(10000)
    from collections import deque
    for y in range(h):
        for x in range(w):
            if visited[y][x]: continue
            r,g,b = px[x,y]
            lum = 0.2126*r+0.7152*g+0.0722*b
            if lum <= lum_thresh: continue
            # BFS
            q = deque([(x,y)])
            visited[y][x] = True
            minx=maxx=x; miny=maxy=y; area=0; rs=gs=bs=0
            while q:
                cx, cy = q.popleft()
                area += 1
                cr,cg,cb = px[cx,cy]
                rs+=cr; gs+=cg; bs+=cb
                minx=min(minx,cx); maxx=max(maxx,cx); miny=min(miny,cy); maxy=max(maxy,cy)
                for dx,dy in ((1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,-1),(1,-1),(-1,1)):
                    nx,ny = cx+dx, cy+dy
                    if 0<=nx<w and 0<=ny<h and not visited[ny][nx]:
                        r2,g2,b2 = px[nx,ny]
                        l2 = 0.2126*r2+0.7152*g2+0.0722*b2
                        if l2 > lum_thresh:
                            visited[ny][nx]=True
                            q.append((nx,ny))
            if area*9 >= min_area:
                comps.append((area*9, (minx*3,miny*3,maxx*3,maxy*3), (rs/area,gs/area,bs/area)))
    comps.sort(key=lambda c: -c[0])
    print(f"\n===== {label} ({path.split('/')[-1]}) {W}x{H} =====")
    print(f"components > {min_area}px^2 at lum>{lum_thresh}: {len(comps)}")
    for area, (x0,y0,x1,y1), (r,g,b) in comps[:max_comps]:
        print(f"  {area:>7}px2  bbox=({x0:>4},{y0:>4})-({x1:>4},{y1:>4})  size={x1-x0+1:>4}x{y1-y0+1:>4}  avg=#{int(r):02x}{int(g):02x}{int(b):02x}")

for path, label in [
    ("/Users/benjerome/Documents/Dev/mylauncher/.agent-shots/fingerprint-removed/lock-screen-no-fingerprint.png", "LOCK no-fingerprint (CURRENT)"),
    ("/Users/benjerome/Documents/Dev/mylauncher/.agent-shots/polish/09-lock-final.png", "LOCK 09 polish"),
    ("/Users/benjerome/Documents/Dev/mylauncher/.agent-shots/polish/08-cover-final.png", "COVER final"),
]:
    cc_inventory(path, label)