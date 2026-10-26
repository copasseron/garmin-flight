#!/usr/bin/env python3
"""Generate official short airport callouts from an SIA AIXM 4.5 export.

The SIA ``Uni/UniUid/txtName`` value is the compact chart/VAC callout.  It is
usually encoded as ``ICAO SHORT NAME`` (for example ``LFPZ SAINT CYR``), so
the ICAO prefix is removed before the value is embedded in the app.

This deliberately generates a separate compact module instead of replacing
the richer FranceAirports records.  The airport reference data can therefore
keep its existing coordinates, radio and runway maintenance workflow while
the display name is refreshed from each AIRAC export.
"""

from __future__ import annotations

import argparse
import json
import re
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path


ICAO_RE = re.compile(r"^LF[A-Z0-9]{2}$")


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1].split(":")[-1]


def text_of(node: ET.Element | None) -> str:
    return "" if node is None or node.text is None else node.text.strip()


def parse_number(value: str) -> float | None:
    match = re.search(r"[-+]?\d+(?:[.,]\d+)?", value or "")
    if not match:
        return None
    return float(match.group(0).replace(",", "."))


def first_text(node: ET.Element, name: str) -> str:
    for child in node.iter():
        if local_name(child.tag) == name:
            value = text_of(child)
            if value:
                return value
    return ""


def attr(node: ET.Element, name: str) -> str:
    for key, value in node.attrib.items():
        if local_name(key) == name:
            return value
    return ""


def airport_codes(source: Path) -> list[str]:
    codes = []
    pattern = re.compile(r'^\s*\["([A-Z0-9]{4})",')
    for line in source.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match:
            codes.append(match.group(1))
    return codes


def extract_names(xml_bytes: bytes) -> tuple[dict[str, str], dict[str, int], str]:
    root = ET.fromstring(xml_bytes)
    names: dict[str, str] = {}
    elevations: dict[str, int] = {}
    for uni in root.iter():
        if local_name(uni.tag) != "Uni":
            continue
        raw_name = first_text(uni, "txtName").upper()
        code = ""
        for child in uni.iter():
            if local_name(child.tag) == "codeId":
                candidate = text_of(child).upper()
                if ICAO_RE.match(candidate):
                    code = candidate
                    break
        if not code or not raw_name.startswith(code + " "):
            continue
        short_name = raw_name[len(code):].strip()
        if short_name and code not in names:
            names[code] = short_name

    for ahp in root.iter():
        if local_name(ahp.tag) != "Ahp":
            continue
        code = ""
        elevation = ""
        unit = ""
        for child in ahp.iter():
            child_name = local_name(child.tag)
            value = text_of(child).upper()
            if child_name == "codeId" and ICAO_RE.match(value):
                code = value
            elif child_name == "valElev" and not elevation:
                elevation = value
            elif child_name == "uomDistVer" and not unit:
                unit = value
        if not code or not elevation:
            continue
        value = parse_number(elevation)
        if value is None:
            continue
        if unit == "M":
            value *= 3.28084
        elevations[code] = int(round(value))

    return names, elevations, "SIA AIXM 4.5"


def fallback_name(name: str) -> str:
    """Use a compact fallback only for local-only fields absent from AIXM."""
    short_name = name
    upper_name = name.upper()
    for suffix in (" AIRPORT", " AIRFIELD", " AERODROME", " AÉRODROME", " AIR BASE", " BASE"):
        index = upper_name.find(suffix)
        if index is not None and index >= 0:
            short_name = name[:index]
            break
    short_name = short_name.split(" (")[0].strip()
    return short_name.upper() or name.upper()


def update_airport_source(source: Path, output: Path, names: dict[str, str],
                          elevations: dict[str, int]) -> tuple[int, int, int]:
    record_pattern = re.compile(
        r'^(?P<prefix>\s*\["(?P<code>[A-Z0-9]{4})",)'
        r'"(?P<name>(?:\\.|[^"])*)"(?P<suffix>,.*)$'
    )
    official_count = 0
    fallback_count = 0
    elevation_count = 0
    lines = []
    for line in source.read_text(encoding="utf-8").splitlines():
        match = record_pattern.match(line)
        if match:
            code = match.group("code")
            old_name = match.group("name")
            short_name = names.get(code)
            if short_name:
                official_count += 1
            else:
                short_name = fallback_name(old_name)
                fallback_count += 1
            line = match.group("prefix") + '"' + short_name + '"' + match.group("suffix")
            elevation_text = str(elevations[code]) if code in elevations else "null"
            if re.search(r',(?:-?\d+|null)\],\s*$', line):
                line = re.sub(r',(?:-?\d+|null)\],\s*$',
                              "," + elevation_text + "],", line)
            else:
                line = re.sub(r'\],\s*$', "," + elevation_text + "],", line)
            if code in elevations:
                elevation_count += 1
        lines.append(line)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return official_count, fallback_count, elevation_count


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("zip", type=Path, help="SIA AIRAC ZIP containing AIXM4.5_all_*.xml")
    parser.add_argument("--airports", type=Path, default=Path("source/FranceAirports.mc"))
    parser.add_argument("--output", type=Path, default=Path("source/FranceAirports.mc"))
    parser.add_argument("--report", type=Path, default=Path("/private/tmp/airport-names-report.json"))
    args = parser.parse_args()

    with zipfile.ZipFile(args.zip) as archive:
        xml_names = [name for name in archive.namelist() if "AIXM4.5_all_" in name and name.endswith(".xml")]
        if not xml_names:
            raise SystemExit("No AIXM4.5_all_*.xml found in the ZIP")
        xml_name = xml_names[0]
        names, elevations, source_kind = extract_names(archive.read(xml_name))

    codes = airport_codes(args.airports)
    matched = sorted(code for code in codes if code in names)
    missing = sorted(code for code in codes if code not in names)
    airac_match = re.search(r"(20\d{2}-\d{2}-\d{2})", xml_name)
    airac = airac_match.group(1) if airac_match else "UNKNOWN"
    official_count, fallback_count, elevation_count = update_airport_source(
        args.airports, args.output, names, elevations)
    report = {
        "source": source_kind,
        "xml": xml_name,
        "airacDate": airac,
        "airportCount": len(codes),
        "officialShortNameCount": official_count,
        "fallbackShortNameCount": fallback_count,
        "elevationCount": elevation_count,
        "missingElevationCount": len(codes) - elevation_count,
        "missingFromAixmCount": len(missing),
        "missingFromAixm": missing,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
