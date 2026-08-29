#!/usr/bin/env python3
"""
List active CAL FIRE incidents within a radius of the house, sorted by distance.
Public API, no auth required: https://incidents.fire.ca.gov/umbraco/api/IncidentApi/GetIncidents

Usage: calfire-nearby.py [--radius MILES] [--lat LAT] [--lon LON]
Output: JSON list of {uniqueId, name, distanceMiles, active, status, percentContained,
                       acresBurned, counties, started, updated, url}
"""
import argparse
import json
import math
import sys
import urllib.request

HOME_LAT = 36.5556163954115
HOME_LON = -121.7179694545728
API_URL = "https://incidents.fire.ca.gov/umbraco/api/IncidentApi/GetIncidents"


def haversine_miles(lat1, lon1, lat2, lon2):
    r = 3958.8
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--radius", type=float, default=60.0)
    ap.add_argument("--lat", type=float, default=HOME_LAT)
    ap.add_argument("--lon", type=float, default=HOME_LON)
    args = ap.parse_args()

    req = urllib.request.Request(API_URL, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.load(resp)
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)

    out = []
    for inc in data.get("Incidents", []):
        lat, lon = inc.get("Latitude"), inc.get("Longitude")
        if lat is None or lon is None:
            continue
        dist = haversine_miles(args.lat, args.lon, lat, lon)
        if dist > args.radius:
            continue
        out.append(
            {
                "uniqueId": inc.get("UniqueId"),
                "name": (inc.get("Name") or "").strip(),
                "distanceMiles": round(dist, 1),
                "active": inc.get("Active"),
                "status": inc.get("Status"),
                "percentContained": inc.get("PercentContained"),
                "acresBurned": inc.get("AcresBurned"),
                "counties": inc.get("Counties"),
                "started": inc.get("Started"),
                "updated": inc.get("Updated"),
                "url": ("https://incidents.fire.ca.gov" + inc["CanonicalUrl"]) if inc.get("CanonicalUrl") else None,
            }
        )
    out.sort(key=lambda r: r["distanceMiles"])
    print(json.dumps({"fetchedAt": None, "homeLat": args.lat, "homeLon": args.lon, "radiusMiles": args.radius, "incidents": out}, indent=2))


if __name__ == "__main__":
    main()
