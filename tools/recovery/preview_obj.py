#!/usr/bin/env python3
"""Render recovered OBJ/MTL assets for extraction QA (Pillow + NumPy, no Blender)."""
import argparse
from pathlib import Path
import math
import re
import numpy as np
from PIL import Image, ImageDraw


def read_obj(path, exclude_sky=False):
    vertices, uv, faces, materials = [], [], [], {}
    material = None
    sky = set()
    with path.open() as f:
        for line in f:
            parts = line.split()
            if not parts:
                continue
            if parts[0] == 'v':
                vertices.append([float(x) for x in parts[1:4]])
            elif parts[0] == 'vt':
                uv.append([float(x) for x in parts[1:3]])
            elif parts[0] == 'usemtl':
                material = parts[1]
            elif parts[0] == 'f':
                ids = [p.split('/') for p in parts[1:]]
                for i in range(1, len(ids)-1):
                    tri = [ids[0], ids[i], ids[i+1]]
                    faces.append(([int(x[0])-1 for x in tri], [int(x[1])-1 for x in tri], material))
            elif parts[0] == 'mtllib':
                key = None
                for row in (path.parent / ' '.join(parts[1:])).read_text().splitlines():
                    words = row.split()
                    if not words:
                        continue
                    if words[0] == 'newmtl':
                        key = words[1]
                    elif words[0] == 'map_Kd':
                        if re.search(r'sky|cloud|moon|stars', ' '.join(words[1:]), re.I):
                            sky.add(key)
                        with Image.open(path.parent / ' '.join(words[1:])) as image:
                            materials[key] = np.asarray(image.convert('RGBA'))
    if exclude_sky:
        faces = [f for f in faces if f[2] not in sky]
    return np.asarray(vertices), np.asarray(uv), faces, materials


def render(path, target, width=640, height=640, yaw=25, pitch=8, exclude_sky=False):
    vertices, uv, faces, materials = read_obj(path, exclude_sky)
    if not len(vertices):
        raise ValueError(f'Empty model: {path}')
    used = sorted(set(i for face in faces for i in face[0]))
    minimum, maximum = vertices[used].min(axis=0), vertices[used].max(axis=0)
    vertices = vertices - (minimum + maximum)/2
    a, b = math.radians(yaw), math.radians(pitch)
    right = np.array([math.cos(a), 0, -math.sin(a)])
    forward = np.array([math.sin(a)*math.cos(b), math.sin(b), math.cos(a)*math.cos(b)])
    up = np.cross(forward, right)
    q = np.stack([vertices @ right, vertices @ up, vertices @ forward], axis=1)
    span = np.maximum(np.ptp(q[used], axis=0), 0.0001)
    scale = min((width-60)/span[0], (height-90)/span[1])
    q[:, 0] = (q[:, 0]-(q[used, 0].min()+q[used, 0].max())/2)*scale + width/2
    q[:, 1] = height/2 - (q[:, 1]-(q[used, 1].min()+q[used, 1].max())/2)*scale
    pixels = np.zeros((height, width, 3), dtype=np.uint8)
    pixels[:] = [32, 37, 43]
    depth = np.full((height, width), -np.inf)
    light = np.array([0.3, 0.75, 0.6]); light /= np.linalg.norm(light)
    for ids, uvids, material in faces:
        pts = q[ids]
        lo = np.maximum(np.floor(pts[:, :2].min(axis=0)).astype(int), [0, 0])
        hi = np.minimum(np.ceil(pts[:, :2].max(axis=0)).astype(int), [width-1, height-1])
        if np.any(hi < lo):
            continue
        x, y = np.meshgrid(np.arange(lo[0], hi[0]+1)+0.5, np.arange(lo[1], hi[1]+1)+0.5)
        p0, p1, p2 = pts
        det = (p1[1]-p2[1])*(p0[0]-p2[0])+(p2[0]-p1[0])*(p0[1]-p2[1])
        if abs(det) < 1e-10:
            continue
        w0 = ((p1[1]-p2[1])*(x-p2[0])+(p2[0]-p1[0])*(y-p2[1]))/det
        w1 = ((p2[1]-p0[1])*(x-p2[0])+(p0[0]-p2[0])*(y-p2[1]))/det
        w2 = 1-w0-w1
        z = w0*p0[2]+w1*p1[2]+w2*p2[2]
        region = np.s_[lo[1]:hi[1]+1, lo[0]:hi[0]+1]
        mask = (w0 >= 0) & (w1 >= 0) & (w2 >= 0) & (z > depth[region])
        if not mask.any():
            continue
        tex = materials.get(material)
        if tex is not None:
            t = uv[uvids]
            u = (w0*t[0, 0]+w1*t[1, 0]+w2*t[2, 0]) % 1
            v = (1-(w0*t[0, 1]+w1*t[1, 1]+w2*t[2, 1])) % 1
            tx = np.minimum((u*tex.shape[1]).astype(int), tex.shape[1]-1)
            ty = np.minimum((v*tex.shape[0]).astype(int), tex.shape[0]-1)
            color = tex[ty, tx]
            # OBJ opacity defaults to opaque. The textures retain alpha for later materials.
            rgb = color[:, :, :3]
        else:
            rgb = np.full((*x.shape, 3), [174, 187, 170], dtype=np.float32)
        normal = np.cross(vertices[ids[1]]-vertices[ids[0]], vertices[ids[2]]-vertices[ids[0]])
        n = np.linalg.norm(normal)
        shade = 0.6 + 0.4*abs(float(np.dot(normal, light)/n)) if n else 1
        pixels[region][mask] = np.clip(rgb[mask]*shade, 0, 255).astype(np.uint8)
        depth[region][mask] = z[mask]
    image = Image.fromarray(pixels)
    draw = ImageDraw.Draw(image)
    draw.text((16, 14), path.stem, fill='white')
    draw.text((16, height-38), f'{len(faces):,} triangles | {len(vertices):,} vertices', fill='white')
    draw.text((16, height-22), 'Source XYZ extent: ' + ', '.join(f'{v:.3f}' for v in maximum-minimum), fill='white')
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target)
    print(target)


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('obj', type=Path)
    ap.add_argument('png', type=Path)
    ap.add_argument('--yaw', type=float, default=25)
    ap.add_argument('--pitch', type=float, default=8)
    ap.add_argument('--exclude-sky', action='store_true')
    args = ap.parse_args()
    render(args.obj, args.png, yaw=args.yaw, pitch=args.pitch, exclude_sky=args.exclude_sky)
