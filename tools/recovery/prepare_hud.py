#!/usr/bin/env python3
"""Copy recovered HUD PNGs unchanged, with provenance and a browser catalogue."""
import hashlib
import html
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
RECOVERY = ROOT / "previous/recovery"
DEST = ROOT / "art/ui/recovered"


def main():
    assets = json.loads((RECOVERY / "reports/assets.json").read_text())
    if isinstance(assets, dict):
        assets = assets["assets"]
    entries = {}
    for asset in assets:
        if asset["type"] != "texture" or "/HUD" not in asset.get("source", ""):
            continue
        name = asset["name"]
        if name in entries:
            if entries[name]["sha256"] != asset["sha256"]:
                raise ValueError(f"Different HUD variants need explicit selection: {name}")
            entries[name]["occurrences"] += 1
            continue
        group = Path(asset["source"]).stem.removesuffix("_TXR").lower()
        target = DEST / group / (Path(name).stem + ".png")
        source = RECOVERY / asset["path"]
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        if digest != asset["sha256"]:
            raise ValueError(f"Recovery hash mismatch: {source}")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        entries[name] = {
            "name": name, "group": group, "width": asset["width"], "height": asset["height"],
            "path": str(target.relative_to(ROOT)), "recovered_path": asset["path"],
            "source": asset["source"], "palette_source": asset.get("paletteSource"),
            "sha256": digest, "occurrences": 1, "gs": asset["metadata"].get("gs", {}),
        }
    catalogue = ROOT / "resources/recovered/hud_catalogue.json"
    catalogue.parent.mkdir(parents=True, exist_ok=True)
    catalogue.write_text(json.dumps({"source": "SOCOM II USA disc recovery", "assets": list(entries.values())}, indent=2) + "\n")
    cards = []
    for entry in sorted(entries.values(), key=lambda e: (e["group"], e["name"])):
        path = str(Path(entry["path"]).relative_to(DEST.relative_to(ROOT)))
        name = html.escape(entry["name"])
        cards.append(f'<figure data-name="{name.lower()}"><a href="{path}"><img src="{path}" alt="{name}"></a><figcaption>{name}<br><small>{entry["group"].upper()} · {entry["width"]}×{entry["height"]}</small></figcaption></figure>')
    (DEST / "index.html").write_text('''<!doctype html><meta charset="utf-8"><title>Recovered SOCOM II HUD</title>
<style>body{background:#26333b;color:#e3e7df;font:16px system-ui;margin:32px}input{padding:10px;width:300px}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px}figure{margin:0;padding:16px;background:#56616a;text-align:center}img{width:128px;height:128px;object-fit:contain;image-rendering:pixelated}figcaption{margin-top:10px;font-size:13px}small{opacity:.7}</style>
<h1>Recovered SOCOM II HUD</h1><p>174 original PNGs, unchanged from the disc recovery. Click an image for its native size. Search “ret_” for crosshairs. HUDW holds weapon icons.</p>
<p><input placeholder="Filter textures" aria-label="Filter textures" oninput="document.querySelectorAll('figure').forEach(f=>f.hidden=!f.dataset.name.includes(this.value.toLowerCase()))"></p><main>
''' + "\n".join(cards) + "\n</main>\n")
    print(f"Copied {len(entries)} HUD textures to {DEST.relative_to(ROOT)}; catalogue: {catalogue.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
