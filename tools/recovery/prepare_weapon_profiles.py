#!/usr/bin/env python3
"""Extract weapon accuracy/modes from the recovered reader, without a mesh rebuild.

Run from the repository root. See WEAPON_PROFILES.md for units and parser evidence.
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = "previous/recovery/native/scripts/disc/ZWEAPON.ZAR-496d80a9db/00000-zweapon.rdr.json"
STANCE_KEYS = """ReticuleKnock ReticuleKnockReturn ReticuleKnockMax
SniperDistPPFrameX SniperDistPPFrameY SniperDistLimitX SniperDistLimitY SniperDecayRate
TargetDilateUponFire TargetDilateUponMovement TargetDilateUponMovementMult
TargetConstrict TargetMin TargetMax FireRifleKickRate FireRifleKickReturnRate
FireRifleKickBaseDist FireRifleKickRandomDist KnockCount KnockEntryStrength""".split()


def fields(tokens):
    # Comment fragments can leave unpaired tokens: do not step by two.
    return {key: tokens[i + 1] for i, key in enumerate(tokens[:-1])
            if isinstance(key, str) and isinstance(tokens[i + 1], list)}


def scalar(record, key, default=0):
    return float(record[key][0]) if record.get(key) else default


def extract():
    source = (ROOT / SOURCE).read_bytes()
    records = {}
    for tokens in fields(json.loads(source))["ZWEAPON"]:
        raw = fields(tokens)
        modes = set(range(1, int(scalar(raw, "MaxFireMode")) + 1))
        for key, mode in [("SingleMode", 1), ("BurstMode", 2), ("AutoMode", 3)]:
            if key in raw:
                modes.add(mode)
        previous = dict.fromkeys(STANCE_KEYS, 0)
        previous.update(TargetDilateUponMovementMult=1, KnockCount=3, KnockEntryStrength=1)
        stances = []
        for name in ["STANCE_STAND", "STANCE_CROUCH", "STANCE_PRONE"]:
            values = fields(fields(raw.get("Reticule_Modifiers", [])).get(name, []))
            previous = {key: scalar(values, key, previous[key]) for key in STANCE_KEYS}
            stances.append(previous)
        identifier = str(int(scalar(raw, "ID")))
        records[identifier] = {
            "id": int(identifier), "name": raw["InternalName"][0],
            "model": raw["ModelName"][0], "modes": sorted(modes),
            "fire_wait": scalar(raw, "FireWait", .1), "stances": stances,
            "burst": {key: scalar(raw, key) for key in
                      ["AccBurstCnt_Min", "AccBurstCnt_Max", "AccScalar_Min", "AccScalar_Max"]},
            "raw": tokens,
        }
    models = {}
    catalogue = json.loads((ROOT / "resources/recovered/weapons.json").read_text())
    for entry in catalogue["weapons"]:
        if not entry["playable"]:
            continue
        # Disc record 13 points at sig226, although a separate SP10 mesh was recovered.
        candidates = ["13"] if entry["source_name"].lower() == "sp10_gyuraz" else [
            key for key, record in records.items()
            if record["model"].lower() == entry["source_name"].lower() and 4 <= record["id"] <= 120]
        assert candidates, entry["id"]
        models[entry["id"]] = candidates
    return {"source": SOURCE, "sha256": hashlib.sha256(source).hexdigest(),
            "models": models, "records": records,
            "model_overrides": {"sp10_gyuraz": "13: SR-1 Gyurza; source ModelName is sig226"}}


if __name__ == "__main__":
    output = ROOT / "resources/recovered/weapon_profiles.json"
    data = extract()
    output.write_text(json.dumps(data, indent=2) + "\n")
    print(f"{len(data['records'])} records; {len(data['models'])} playable model variants → {output.relative_to(ROOT)}")
