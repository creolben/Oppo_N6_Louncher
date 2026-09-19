#!/usr/bin/env python3
from PIL import Image
from collections import deque

def cc_inventory(path, label, min_area=400, lum_thresh=90, max_comps=45):
    img = Image.open(path).convert('RGB')
    W, H = img.size
    sc = img.resize((W//3, H//3), Image.BOX)
    w, h = sc.size
    px = sc.load()
    visited = [[False]*w for _ in range(h)]
    comps = []
    for y in range(h):
        for x in range(w):
            if visited[y][x]: continue
            r,g,b = px[x,y]
            if 0.2126*r+0.7152*g+0.0722*b <= lum_thresh: continue
            q = deque([(x,y)]); visited[y][x] = True
            minx=maxx=x; miny=maxy=y; area=0; rs=gs=bs=0
            while q:
                cx, cy = q.popleft(); area += 1
                cr,cg,cb = px[cx,cy]; rs+=cr; gs+=cg; bs+=cb
                minx=min(minx,cx); maxx=max(maxx,cx); miny=min(miny,cy); maxy=max(maxy,cy)
                for dx,dy in ((1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,-1),(1,-1),(-1,1)):
                    nx,ny = cx+dx, cy+dy
                    if 0<=nx<w and 0<=ny<h and not visited[ny][nx]:
                        r2,g2,b2 = px[nx,ny]
                        if 0.2126*r2+0.7152*g2+0.0722*b2 > lum_thresh:
                            visited[ny][nx]=True; q.append((nx,ny))
            if area*9 >= min_area:
                comps.append((area*9, (minx*3,miny*3,maxx*3,maxy*3), (rs/area,gs/area,bs/area)))
    comps.sort(key=lambda c: -c[0])
    print(f"\n===== {label} ({path.split('/')[-1]}) {W}x{H} =====")
    print(f"components: {len(comps)}")
    for area,(x0,y0,x1,y1),(r,g,b) in comps[:max_comps]:
        print(f"  {area:>7}px2 ({x0:>4},{y0:>4})-({x1:>4},{y1:>4}) {x1-x0+1:>4}x{y1-y0+1:>4} #{int(r):02x}{int(g):02x}{int(b):02x}")

for p, l in [
    ("/Users/benjerome/Documents/Dev/mylauncher/.agent-shots/after-full-galaxy.png", "GALAXY after (cover-sized?)"),
    ("/Users/benjerome/Documents/Dev/mylauncher/.agent-shots/posture-inner.png", "POSTURE INNER 2248x2480"),
    ("/Users/benjerome/Documents/Dev/mylauncher/.agent-shots/before-cockpit-blocked.png", "COCKPIT before-blocked"),
]:
    cc_inventory(p, l)