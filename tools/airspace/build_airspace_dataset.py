#!/usr/bin/env python3
"""Build the compact Monkey C airspace dataset from an SIA AIXM 4.5 ZIP.

The SIA ZIP is intentionally kept outside the repository.  This tool extracts
the AIXM file, resolves Airspace -> Service -> RadioCommunicationChannel links,
converts supported geometries to polygons, and emits a generated Monkey C
module plus a JSON quality report.

The parser is deliberately namespace-agnostic because SIA exports have used
slightly different namespace prefixes across AIRAC cycles.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import tempfile
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Optional
import xml.etree.ElementTree as ET


METRO_BOUNDS = (41.0, 51.5, -5.8, 10.0)
EARTH_RADIUS_M = 6_371_000.0


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1].split(":")[-1]


def attr(element: ET.Element, name: str, default: str = "") -> str:
    for key, value in element.attrib.items():
        if local_name(key) == name:
            return value
    return default


def text_of(element: Optional[ET.Element]) -> str:
    return "" if element is None or element.text is None else element.text.strip()


def descendants(element: ET.Element, names: Iterable[str]) -> list[ET.Element]:
    wanted = set(names)
    return [child for child in element.iter() if local_name(child.tag) in wanted]


def first_text(element: ET.Element, names: Iterable[str]) -> str:
    for child in descendants(element, names):
        value = text_of(child)
        if value:
            return value
    return ""


def href(element: ET.Element) -> str:
    value = attr(element, "href") or attr(element, "id")
    return value.rsplit("#", 1)[-1]


def parse_number(value: str) -> Optional[float]:
    match = re.search(r"[-+]?\d+(?:[.,]\d+)?", value or "")
    if not match:
        return None
    return float(match.group(0).replace(",", "."))


def parse_pair_values(values: list[float], order: str = "latlon") -> list[list[float]]:
    points = []
    for index in range(0, len(values) - 1, 2):
        first, second = values[index], values[index + 1]
        if order == "lonlat":
            first, second = second, first
        points.append([round(first, 6), round(second, 6)])
    return points


def parse_pos_list(element: ET.Element) -> list[list[float]]:
    values = []
    for node in descendants(element, {"posList", "coordinates", "pos"}):
        raw = text_of(node).replace(",", " ")
        values.extend(float(item) for item in raw.split() if re.match(r"^-?\d", item))
        if values:
            srs = attr(node, "srsName") or attr(element, "srsName")
            # AIXM exports use latitude/longitude for posList.  Older GML
            # coordinates use longitude,latitude and advertise the order in
            # the CRS; keep the default safe for current SIA AIXM 4.5 files.
            order = "lonlat" if local_name(node.tag) == "coordinates" or "CRS84" in srs.upper() else "latlon"
            return parse_pair_values(values, order)
    return []


def destination(lat: float, lon: float, bearing: float, distance_m: float) -> list[float]:
    angular = distance_m / EARTH_RADIUS_M
    bearing_radians = math.radians(bearing)
    lat_radians = math.radians(lat)
    lon_radians = math.radians(lon)
    target_lat = math.asin(
        math.sin(lat_radians) * math.cos(angular)
        + math.cos(lat_radians) * math.sin(angular) * math.cos(bearing_radians)
    )
    target_lon = lon_radians + math.atan2(
        math.sin(bearing_radians) * math.sin(angular) * math.cos(lat_radians),
        math.cos(angular) - math.sin(lat_radians) * math.sin(target_lat),
    )
    return [math.degrees(target_lat), ((math.degrees(target_lon) + 540) % 360) - 180]


def arc_points(center: list[float], radius_m: float, start: float, end: float) -> list[list[float]]:
    start = start % 360
    end = end % 360
    sweep = (end - start) % 360
    if sweep == 0:
        sweep = 360
    count = max(8, int(math.ceil((math.radians(sweep) * radius_m) / 25.0)))
    return [destination(center[0], center[1], start + sweep * i / count, radius_m) for i in range(count + 1)]


def parse_geometry(element: ET.Element, elements_by_id: Optional[dict[str, ET.Element]] = None,
                   seen: Optional[set[str]] = None) -> list[list[float]]:
    """Extract a polygon, or approximate a GML circle/arc at <=25m chord."""
    points = parse_pos_list(element)
    if len(points) >= 3:
        return points

    # AIXM commonly stores the Surface or AirspaceVolume separately and puts
    # only an xlink:href in horizontalProjection/theAirspaceVolume.
    if elements_by_id is not None:
        seen = set() if seen is None else seen
        current_id = find_id(element)
        if current_id:
            seen.add(current_id)
        for node in element.iter():
            reference = attr(node, "href").rsplit("#", 1)[-1]
            target = elements_by_id.get(reference)
            if target is not None and reference not in seen:
                geometry = parse_geometry(target, elements_by_id, seen)
                if len(geometry) >= 3:
                    return geometry

    center_node = next(iter(descendants(element, {"center", "centerPoint"})), None)
    center = parse_pos_list(center_node) if center_node is not None else []
    center = center[0] if center else []
    radius = parse_number(first_text(element, {"radius"}))
    if not center or radius is None:
        return []

    uom = "".join(attr(node, "uom") for node in descendants(element, {"radius"})).upper()
    if "NM" in uom:
        radius *= 1852.0
    elif "KM" in uom:
        radius *= 1000.0
    start = parse_number(first_text(element, {"startAngle"})) or 0.0
    end = parse_number(first_text(element, {"endAngle"})) or 360.0
    if any(local_name(node.tag) == "CircleByCenterPoint" for node in element.iter()):
        start, end = 0.0, 360.0
    return arc_points(center, radius, start, end)


def find_id(element: ET.Element) -> str:
    return attr(element, "id") or attr(element, "gml:id")


def find_time_slices(airspace: ET.Element) -> list[ET.Element]:
    slices = descendants(airspace, {"AirspaceTimeSlice"})
    return slices or [airspace]


def extract_altitude(volume: ET.Element, prefix: str) -> tuple[Optional[float], str, bool]:
    nodes = descendants(volume, {prefix + "Limit"})
    if not nodes:
        return None, "UNKNOWN", False
    node = nodes[0]
    raw = text_of(node).upper()
    ref = first_text(volume, {prefix + "LimitReference", prefix + "Reference"}).upper()
    uom = attr(node, "uom").upper()
    if raw in {"SFC", "GND", "GROUND"}:
        return 0.0, "SFC", True
    value = parse_number(raw)
    if value is None:
        return None, ref or uom or "UNKNOWN", False
    if "FL" in ref or "FL" in uom or raw.startswith("FL"):
        value = value * 100.0
        ref = "FL"
    elif "M" in uom and "FT" not in uom:
        value *= 3.28084
    return value, ref or uom or "AMSL", True


def normalize_frequency(value: str) -> str:
    number = parse_number(value)
    return "" if number is None else f"{number:.3f}"


@dataclass
class Channel:
    service_type: str
    callsign: str
    tx: str
    rx: str
    channel: str
    rank: int
    availability: str


@dataclass
class Service:
    service_type: str
    callsign: str
    airspace_ids: set[str] = field(default_factory=set)
    channel_ids: list[str] = field(default_factory=list)
    availability: str = ""


def parse_frequency_maps(root: ET.Element) -> tuple[dict[str, Channel], list[Service]]:
    channels: dict[str, Channel] = {}
    for node in root.iter():
        if local_name(node.tag) not in {"RadioCommunicationChannel", "RadioCommunicationChannelTimeSlice"}:
            continue
        channel_id = find_id(node)
        if not channel_id:
            continue
        tx = normalize_frequency(first_text(node, {"frequencyTransmission", "frequency"}))
        rx = normalize_frequency(first_text(node, {"frequencyReception"}))
        rank = int(parse_number(first_text(node, {"rank"})) or 999)
        channel = first_text(node, {"channel", "channelNumber"})
        availability = first_text(node, {"availability", "Timesheet", "timesheet"})
        channels[channel_id] = Channel("INFO", "", tx, rx, channel, rank, availability)

    services: list[Service] = []
    for node in root.iter():
        if local_name(node.tag) not in {
            "AirTrafficControlService", "InformationService", "Service", "AirTrafficService"
        }:
            continue
        service_type = first_text(node, {"serviceType", "type", "name"}).upper()
        callsign = first_text(node, {"callsign", "callSign"})
        service = Service(service_type or "INFO", callsign)
        service.availability = first_text(node, {"availability", "Timesheet", "timesheet"})
        for child in node.iter():
            child_name = local_name(child.tag)
            if child_name == "clientAirspace":
                value = href(child)
                if value:
                    service.airspace_ids.add(value)
            elif child_name in {"radioCommunication", "radioCommunicationChannel"}:
                value = href(child)
                if value:
                    service.channel_ids.append(value)
        if service.airspace_ids:
            services.append(service)
    return channels, services


def classify_service(value: str) -> str:
    value = value.upper()
    for name in ("TWR", "APP", "ATIS", "FIS", "INFO", "CTAF", "AFIS"):
        if name in value:
            return name
    return "INFO"


def service_priority(value: str) -> int:
    return {"TWR": 0, "APP": 1, "INFO": 2, "FIS": 2, "ATIS": 3, "CTAF": 4}.get(value, 5)


def parse_modern_airspaces(root: ET.Element) -> tuple[list[dict], dict]:
    elements_by_id = {find_id(node): node for node in root.iter() if find_id(node)}
    channels, services = parse_frequency_maps(root)
    services_by_airspace: dict[str, list[Service]] = {}
    for service in services:
        for airspace_id in service.airspace_ids:
            services_by_airspace.setdefault(airspace_id, []).append(service)

    report = {
        "airac": "UNKNOWN",
        "source": "SIA AIXM 4.5",
        "zones": 0,
        "with_geometry": 0,
        "without_geometry": 0,
        "with_frequency": 0,
        "without_frequency": 0,
        "broken_service_links": 0,
        "broken_channel_links": 0,
        "skipped_outside_metropolitan_france": 0,
    }
    zones = []
    known_airspace_ids = {
        find_id(node) for node in root.iter() if local_name(node.tag) == "Airspace" and find_id(node)
    }
    for service in services:
        report["broken_service_links"] += sum(
            1 for airspace_id in service.airspace_ids if airspace_id not in known_airspace_ids
        )
    for airspace in root.iter():
        if local_name(airspace.tag) != "Airspace":
            continue
        airspace_id = find_id(airspace)
        slices = find_time_slices(airspace)
        current = slices[-1]
        ident = first_text(current, {"designatorICAO", "designator", "name"}) or airspace_id
        name = first_text(current, {"name", "designator"}) or ident
        zone_type = first_text(current, {"type"}) or "AIRSPACE"
        zone_class = first_text(current, {"class"}) or ""
        geometry = []
        volumes = descendants(current, {"AirspaceVolume"}) or [current]
        for volume in volumes:
            geometry = parse_geometry(volume, elements_by_id)
            if geometry:
                break
        if len(geometry) < 3:
            report["without_geometry"] += 1
            continue
        lats = [point[0] for point in geometry]
        lons = [point[1] for point in geometry]
        if max(lats) < METRO_BOUNDS[0] or min(lats) > METRO_BOUNDS[1] or max(lons) < METRO_BOUNDS[2] or min(lons) > METRO_BOUNDS[3]:
            report["skipped_outside_metropolitan_france"] += 1
            continue
        floor_value, floor_ref, floor_ok = extract_altitude(volumes[0], "lower")
        ceiling_value, ceiling_ref, ceiling_ok = extract_altitude(volumes[0], "upper")
        frequency_items = []
        for service in services_by_airspace.get(airspace_id, []):
            kind = classify_service(service.service_type)
            for channel_id in service.channel_ids:
                channel = channels.get(channel_id)
                if channel is None:
                    report["broken_channel_links"] += 1
                    continue
                frequency_items.append({
                    "serviceType": kind,
                    "callsign": service.callsign,
                    "frequencyTx": channel.tx,
                    "frequencyRx": channel.rx,
                    "channel": channel.channel,
                    "rank": channel.rank,
                    "availability": channel.availability or service.availability,
                })
        frequency_items.sort(key=lambda item: (
            item["rank"] if item["rank"] < 999 else 1000,
            service_priority(item["serviceType"]),
        ))
        if frequency_items:
            report["with_frequency"] += 1
        else:
            report["without_frequency"] += 1
        schedule = first_text(current, {"activation", "availability", "Timesheet", "timesheet"})
        zones.append({
            "id": airspace_id,
            "name": name,
            "type": zone_type,
            "class": zone_class,
            "floor": floor_value if floor_ok else None,
            "floorRef": floor_ref,
            "ceiling": ceiling_value if ceiling_ok else None,
            "ceilingRef": ceiling_ref,
            "schedule": schedule,
            "frequencies": frequency_items,
            "bbox": [min(lats), max(lats), min(lons), max(lons)],
            "polygon": geometry,
        })

    report["zones"] = len(zones)
    report["with_geometry"] = len(zones)
    return zones, report


def parse_legacy_coordinate(value: str, latitude: bool) -> Optional[float]:
    """Parse SIA AIXM 4.5 coordinates such as 475916.00N or 0014538.00E."""
    value = (value or "").strip().upper()
    match = re.match(r"^(\d+)(?:\.(\d+))?([NSEW])$", value)
    if not match:
        return None
    digits, fraction, direction = match.groups()
    degree_digits = 2 if latitude else 3
    if len(digits) < degree_digits + 4:
        return None
    degrees = float(digits[:degree_digits])
    minutes = float(digits[degree_digits:degree_digits + 2])
    seconds = float(digits[degree_digits + 2:] + "." + (fraction or "0"))
    result = degrees + minutes / 60.0 + seconds / 3600.0
    return -result if direction in {"S", "W"} else result


def legacy_point(node: ET.Element, lat_name: str = "geoLat", lon_name: str = "geoLong") -> Optional[list[float]]:
    latitude = parse_legacy_coordinate(first_text(node, {lat_name}), True)
    longitude = parse_legacy_coordinate(first_text(node, {lon_name}), False)
    return None if latitude is None or longitude is None else [latitude, longitude]


def bearing_between(start: list[float], end: list[float]) -> float:
    lat1, lat2 = math.radians(start[0]), math.radians(end[0])
    delta_lon = math.radians(end[1] - start[1])
    return math.degrees(math.atan2(
        math.sin(delta_lon) * math.cos(lat2),
        math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(delta_lon),
    )) % 360


def legacy_arc(start: list[float], end: list[float], center: list[float], radius_m: float,
               clockwise: bool) -> list[list[float]]:
    start_bearing = bearing_between(center, start)
    end_bearing = bearing_between(center, end)
    if clockwise:
        sweep = (end_bearing - start_bearing) % 360
    else:
        sweep = -((start_bearing - end_bearing) % 360)
    if sweep == 0:
        sweep = 360 if clockwise else -360
    count = max(2, int(math.ceil(abs(math.radians(sweep)) * radius_m / 25.0)))
    return [destination(center[0], center[1], start_bearing + sweep * i / count, radius_m)
            for i in range(count + 1)]


def simplify_polyline(points: list[list[float]], tolerance_m: float = 25.0) -> list[list[float]]:
    """Douglas-Peucker simplification with a conservative degree tolerance."""
    if len(points) <= 2:
        return points
    tolerance = tolerance_m / 111000.0
    tolerance_sq = tolerance * tolerance
    kept = {0, len(points) - 1}
    pending = [(0, len(points) - 1)]
    while pending:
        start, end = pending.pop()
        ax, ay = points[start]
        bx, by = points[end]
        dx, dy = bx - ax, by - ay
        denominator = dx * dx + dy * dy
        furthest_index = -1
        furthest_distance = tolerance_sq
        for index in range(start + 1, end):
            px, py = points[index]
            if denominator == 0:
                distance = (px - ax) ** 2 + (py - ay) ** 2
            else:
                projection = ((px - ax) * dx + (py - ay) * dy) / denominator
                projection = max(0.0, min(1.0, projection))
                closest_x = ax + projection * dx
                closest_y = ay + projection * dy
                distance = (px - closest_x) ** 2 + (py - closest_y) ** 2
            if distance > furthest_distance:
                furthest_distance = distance
                furthest_index = index
        if furthest_index >= 0:
            kept.add(furthest_index)
            pending.append((start, furthest_index))
            pending.append((furthest_index, end))
    return [point for index, point in enumerate(points) if index in kept]


def legacy_boundary_geometry(boundary: ET.Element) -> list[list[float]]:
    points: list[list[float]] = []
    for vertex in descendants(boundary, {"Avx"}):
        endpoint = legacy_point(vertex)
        if endpoint is None:
            continue
        vertex_type = first_text(vertex, {"codeType"}).upper()
        center = legacy_point(vertex, "geoLatArc", "geoLongArc")
        radius = parse_number(first_text(vertex, {"valRadiusArc"}))
        uom = first_text(vertex, {"uomRadiusArc"}).upper()
        if radius is not None and "NM" in uom:
            radius *= 1852.0
        elif radius is not None and "KM" in uom:
            radius *= 1000.0
        if points and center is not None and radius is not None and vertex_type in {"CWA", "CCA"}:
            points.extend(legacy_arc(points[-1], endpoint, center, radius, vertex_type == "CWA")[1:])
        else:
            points.append(endpoint)
    return simplify_polyline(points)


def legacy_altitude(element: ET.Element, prefix: str) -> tuple[Optional[float], str, bool]:
    code = first_text(element, {"codeDistVer" + prefix}).upper()
    value = parse_number(first_text(element, {"valDistVer" + prefix}))
    unit = first_text(element, {"uomDistVer" + prefix}).upper()
    if value is None:
        return None, code or unit or "UNKNOWN", False
    if code in {"HEI", "GND", "SFC"} and value == 0:
        return 0.0, "SFC", True
    if unit == "FL" or code == "STD":
        return value * 100.0, "FL", True
    if code == "HEI":
        return value * (3.28084 if unit == "M" else 1.0), "AGL", True
    return value * (3.28084 if unit == "M" else 1.0), "AMSL", True


def legacy_schedule(element: ET.Element) -> str:
    work_code = first_text(element, {"codeWorkHr"}).upper()
    note = first_text(element, {"txtRmkWorkHr"})
    if work_code == "H24" or "H24" in note.upper():
        return "H24"
    # Keep the schedule source category without embedding long bilingual
    # remarks in every zone record. Detailed schedule text is not evaluated by
    # the first watch page and remains available in the source XML.
    return work_code or "UNKNOWN"


def legacy_frequencies(root: ET.Element) -> dict[str, list[dict]]:
    frequencies: dict[str, list[dict]] = {}
    for node in root.iter("Fqy"):
        uid = next(iter(descendants(node, {"FqyUid"})), None)
        service_uid = next(iter(descendants(node, {"SerUid"})), None)
        if uid is None or service_uid is None:
            continue
        service_type = classify_service(first_text(service_uid, {"codeType"}))
        rank = int(parse_number(first_text(service_uid, {"noSeq"})) or 999)
        unit_name = first_text(service_uid, {"txtName"})
        keys = set(re.findall(r"\b[A-Z]{4}\b", unit_name.upper()))
        callsigns = [first_text(child, {"txtCallSign"}) for child in descendants(node, {"Cdl"})
                     if first_text(child, {"codeLang"}).upper() in {"", "FR"} and
                     first_text(child, {"txtCallSign"})]
        callsign = callsigns[0] if callsigns else first_text(node, {"txtCallSign"})
        tx = normalize_frequency(first_text(node, {"valFreqTrans"}))
        rx = normalize_frequency(first_text(node, {"valFreqRecep", "valFreqReceive"}))
        availability = legacy_schedule(node)
        item = {
            "serviceType": service_type,
            "callsign": callsign,
            "frequencyTx": tx,
            "frequencyRx": rx,
            "channel": "",
            "rank": rank,
            "availability": availability,
        }
        for key in keys:
            frequencies.setdefault(key, []).append(item)
    for values in frequencies.values():
        values.sort(key=lambda item: (item["rank"], service_priority(item["serviceType"])))
    return frequencies


def parse_legacy_airspaces(root: ET.Element) -> tuple[list[dict], dict]:
    report = {
        "airac": "UNKNOWN",
        "source": "SIA AIXM 4.5 snapshot",
        "zones": 0,
        "with_geometry": 0,
        "without_geometry": 0,
        "with_frequency": 0,
        "without_frequency": 0,
        "broken_service_links": 0,
        "broken_channel_links": 0,
        "skipped_outside_metropolitan_france": 0,
        "skipped_unselected_type": 0,
        "skipped_class_g": 0,
    }
    boundaries: dict[str, list[list[float]]] = {}
    for boundary in root.iter("Abd"):
        uid = next(iter(descendants(boundary, {"AseUid"})), None)
        if uid is None:
            continue
        key = attr(uid, "mid")
        geometry = legacy_boundary_geometry(boundary)
        if key and len(geometry) >= 3:
            boundaries[key] = geometry
    frequencies = legacy_frequencies(root)
    zones = []
    for airspace in root.iter("Ase"):
        uid = next(iter(descendants(airspace, {"AseUid"})), None)
        if uid is None:
            continue
        airspace_id = first_text(uid, {"codeId"})
        mid = attr(uid, "mid")
        zone_type = first_text(airspace, {"txtLocalType", "codeType"}) or "AIRSPACE"
        if zone_type.upper() not in {"P", "R", "D", "TMA", "CTR"}:
            report["skipped_unselected_type"] += 1
            continue
        if first_text(airspace, {"codeClass"}).upper() == "G":
            report["skipped_class_g"] += 1
            continue
        geometry = boundaries.get(mid, [])
        if len(geometry) < 3:
            report["without_geometry"] += 1
            continue
        lats = [point[0] for point in geometry]
        lons = [point[1] for point in geometry]
        if max(lats) < METRO_BOUNDS[0] or min(lats) > METRO_BOUNDS[1] or max(lons) < METRO_BOUNDS[2] or min(lons) > METRO_BOUNDS[3]:
            report["skipped_outside_metropolitan_france"] += 1
            continue
        frequency_items = []
        base_id = re.match(r"^[A-Z]{4}", airspace_id or "")
        for key in {airspace_id, base_id.group(0) if base_id else ""}:
            if key and key in frequencies:
                frequency_items.extend(frequencies[key])
        unique_frequencies = []
        seen_frequencies = set()
        for item in frequency_items:
            signature = (item["serviceType"], item["frequencyTx"], item["callsign"])
            if signature not in seen_frequencies:
                seen_frequencies.add(signature)
                unique_frequencies.append(item)
        unique_frequencies.sort(key=lambda item: (item["rank"], service_priority(item["serviceType"])))
        if unique_frequencies:
            report["with_frequency"] += 1
        else:
            report["without_frequency"] += 1
        floor, floor_ref, floor_ok = legacy_altitude(airspace, "Lower")
        ceiling, ceiling_ref, ceiling_ok = legacy_altitude(airspace, "Upper")
        zones.append({
            "id": airspace_id or mid,
            "name": (first_text(airspace, {"txtName", "txtDesig"}) or airspace_id)[:24],
            "type": zone_type,
            "class": "" if first_text(airspace, {"codeClass"}).upper() == "G" else first_text(airspace, {"codeClass"}),
            "floor": floor if floor_ok else None,
            "floorRef": floor_ref,
            "ceiling": ceiling if ceiling_ok else None,
            "ceilingRef": ceiling_ref,
            "schedule": legacy_schedule(airspace),
            "frequencies": unique_frequencies,
            "bbox": [min(lats), max(lats), min(lons), max(lons)],
            "polygon": geometry,
        })
    report["zones"] = len(zones)
    report["with_geometry"] = len(zones)
    return zones, report


def parse_airspaces(root: ET.Element) -> tuple[list[dict], dict]:
    if any(local_name(node.tag) == "Airspace" for node in root.iter()):
        return parse_modern_airspaces(root)
    return parse_legacy_airspaces(root)


def monkey_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def mc_number(value: Optional[float]) -> str:
    # Vertical limits are stored in feet. A one-foot resolution is more than
    # sufficient here and avoids spending source bytes on insignificant
    # decimal places in the watch application's memory-limited dataset.
    return "null" if value is None else f"{value:.0f}"


def emit_module(zones: list[dict], airac: str, output: Path) -> None:
    lines = [
        "// GENERATED FILE. Run tools/airspace/build_airspace_dataset.py to refresh it.",
        "// Source: SIA AIXM 4.5 AIRAC " + airac,
        "class FranceAirspaces {",
        "    static function getAiracLabel() { return " + monkey_string(airac) + "; }",
        "    static function getAll() {",
        "        return [",
    ]
    for zone in zones:
        frequencies = []
        for item in zone["frequencies"][:2]:
            frequencies.append("[" + ",".join([
                monkey_string(item["serviceType"]), monkey_string(item["frequencyTx"]),
            ]) + "]")
        # Flat coordinate arrays avoid allocating one Monkey C array per
        # vertex while preserving the same latitude/longitude pairs.
        polygon = "[" + ",".join(
            "%.4f,%.4f" % (point[0], point[1]) for point in zone["polygon"]
        ) + "]"
        bbox = "[" + ",".join("%.4f" % value for value in zone["bbox"]) + "]"
        # Compact record: short name, type, class, floor, floorRef, ceiling,
        # ceilingRef, up to two primary frequencies, bbox, polygon. The
        # internal identifier is intentionally omitted from the watch copy:
        # it is not displayed or used for containment and costs precious
        # epix2 application memory.
        record = [
            monkey_string(zone["name"]), monkey_string(zone["type"]),
            monkey_string(zone["class"]),
            mc_number(zone["floor"]), monkey_string(zone["floorRef"]),
            mc_number(zone["ceiling"]), monkey_string(zone["ceilingRef"]),
            "[" + ",".join(frequencies) + "]", bbox, polygon,
        ]
        lines.append("            [" + ",".join(record) + "],")
    lines += ["        ];", "    }", "}", ""]
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines), encoding="utf-8")


def find_aixm(extracted: Path) -> Path:
    candidates = sorted(extracted.rglob("AIXM4.5_all_FR_OM_*.xml"))
    if not candidates:
        candidates = sorted(extracted.rglob("*.xml"))
    if not candidates:
        raise FileNotFoundError("No XML file found in the SIA ZIP")
    return candidates[0]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("zip_path", type=Path)
    parser.add_argument("--output", type=Path, default=Path("source/FranceAirspaces.mc"))
    parser.add_argument("--report", type=Path, default=Path("airspace-quality.json"))
    parser.add_argument("--airac", default="UNKNOWN")
    parser.add_argument(
        "--require-frequency",
        action="store_true",
        help="embed only zones with at least one published frequency",
    )
    parser.add_argument(
        "--omit-types",
        default="",
        help="comma-separated zone types to omit from the embedded dataset",
    )
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="sia-aixm-") as directory:
        with zipfile.ZipFile(args.zip_path) as archive:
            archive.extractall(directory)
        xml_path = find_aixm(Path(directory))
        root = ET.parse(xml_path).getroot()
        zones, report = parse_airspaces(root)
    report["airac"] = args.airac
    report["xml"] = xml_path.name
    omitted_types = {value.strip().upper() for value in args.omit_types.split(",") if value.strip()}
    if omitted_types:
        zones = [zone for zone in zones if zone["type"].upper() not in omitted_types]
        report["omitted_types"] = sorted(omitted_types)
    if args.require_frequency:
        zones = [zone for zone in zones if zone["frequencies"]]
    report["embedded_zones"] = len(zones)
    report["embedded_without_frequency"] = sum(1 for zone in zones if not zone["frequencies"])
    emit_module(zones, args.airac, args.output)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
