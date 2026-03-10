#!/usr/bin/env python3
"""
check_mesh_ids.py
Queries the Roblox Open Cloud API for the mesh asset IDs that failed
with 'MeshContentProvider could not fetch' and prints their status.
"""
import os, json, re, time
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from pathlib import Path

WORKSPACE = Path(r"C:\Users\P_Guilleminot\Desktop\Developer\RobloxDefense")
ENV_FILE = WORKSPACE / ".env"

# Load .env
for line in ENV_FILE.read_text().splitlines():
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, _, v = line.partition("=")
        os.environ.setdefault(k.strip(), v.strip())

API_KEY = os.environ.get("ROBLOX_OPEN_CLOUD_KEY", "")
if not API_KEY:
    raise SystemExit("ROBLOX_OPEN_CLOUD_KEY not found in .env")

# All 42 failing IDs from the Studio log, annotated with their MeshMap entry
FAILING = [
    ("Venti",        "Torso",    117848811691934),
    ("Venti",        "LeftLeg",   74581520069858),
    ("Venti",        "RightLeg", 130275304392160),
    ("Venti",        "LeftArm",  108932718989714),
    ("Venti",        "Head",     138341719496319),
    ("Venti",        "RightArm", 100639034835472),
    ("Xiao",         "RightLeg", 103751577853094),
    ("Xiao",         "Torso",    112115272053934),
    ("Xiao",         "Head",      98897340758341),
    ("Xiao",         "LeftLeg",   83021598249886),
    ("Xiao",         "LeftArm",   70445348778446),
    ("Xiao",         "RightArm",  96110738102190),
    ("Raiden Shogun","LeftArm",   88425905149995),
    ("Raiden Shogun","Head",     126222835159434),
    ("Raiden Shogun","Torso",    102771360457730),
    ("Raiden Shogun","RightArm",  94949473006864),
    ("Raiden Shogun","LeftLeg",  140638585452354),
    ("Raiden Shogun","RightLeg",  89722674794943),
    ("Arlecchino",   "Head",      95982831594432),
    ("Arlecchino",   "Torso",    117085762369073),
    ("Arlecchino",   "LeftArm",  116776400327939),
    ("Arlecchino",   "RightArm",  92939152673046),
    ("Arlecchino",   "LeftLeg",  118014652119697),
    ("Arlecchino",   "RightLeg", 125848937143629),
    ("Eula",         "Head",     127128905965036),
    ("Eula",         "Torso",     74923221354202),
    ("Eula",         "LeftArm",  130844097571660),
    ("Eula",         "RightArm", 131479201792390),
    ("Eula",         "LeftLeg",   96426478744645),
    ("Eula",         "RightLeg",  70429454596407),
    ("Skirk",        "Head",      91433155276341),
    ("Skirk",        "Torso",     81054979420025),
    ("Skirk",        "LeftArm",  121518194088009),
    ("Skirk",        "RightArm", 106595621008148),
    ("Skirk",        "LeftLeg",   73498786371303),
    ("Skirk",        "RightLeg", 106634574859269),
    ("Hu Tao",       "Head",      92521300174886),
    ("Hu Tao",       "Torso",    131320228250256),
    ("Hu Tao",       "LeftArm",  109105282749854),
    ("Hu Tao",       "RightArm",  70664062286380),
    ("Hu Tao",       "LeftLeg",   77240630504209),
    ("Hu Tao",       "RightLeg", 120595475073234),
]

# Known-good IDs for baseline comparison
GOOD = [
    ("Zhongli",  "Head",  138026837717299),
    ("Mavuika",  "Head",   82925157333749),
    ("Zhongli",  "Torso", 101166647341472),
]

print("=" * 72)
print(f"{'CHAR':<16} {'PART':<10} {'ID':<18} {'STATUS':<8} DETAIL")
print("=" * 72)

def check(char, part, asset_id):
    url = "https://apis.roblox.com/assets/v1/assets/{}".format(asset_id)
    req = Request(url, headers={"x-api-key": API_KEY})
    try:
        with urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
            asset_type = data.get("assetType", "?")
            name = data.get("displayName", "?")
            print(f"{char:<16} {part:<10} {asset_id:<18} OK       type={asset_type}  name={name}")
    except HTTPError as e:
        body = e.read().decode()[:80]
        print(f"{char:<16} {part:<10} {asset_id:<18} HTTP {e.code}  {body}")
    except Exception as e:
        print(f"{char:<16} {part:<10} {asset_id:<18} ERROR    {e}")
    time.sleep(0.15)

print("\n--- Baseline (should be OK) ---")
for row in GOOD:
    check(*row)

print("\n--- Failing IDs from Studio log ---")
for row in FAILING:
    check(*row)
