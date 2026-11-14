"""
Schedule parser: converts raw OCR text blocks into structured JSON bus timetable records.
Handles bilingual Tamil and English comma-separated stop lists and normalizes times.
"""

import re
from typing import List, Dict, Any


def normalize_time(time_str: str) -> str:
    """
    Normalizes varied time formats to 24hr 'HH:MM' string.
    Examples:
      '8.00am' -> '08:00'
      '8:05 AM' -> '08:05'
      '7.50am' -> '07:50'
      '1.30pm' -> '13:30'
    """
    if not time_str:
        return '08:00'

    clean = time_str.strip().lower().replace(' ', '')
    # Match patterns like 8.00am, 08:05am, 7.50am, 8:15pm
    match = re.search(r'(\d{1,2})[.:](\d{2})\s*(am|pm)?', clean)
    if not match:
        return '08:00'

    hours = int(match.group(1))
    minutes = int(match.group(2))
    meridiem = match.group(3)

    if meridiem == 'pm' and hours < 12:
        hours += 12
    elif meridiem == 'am' and hours == 12:
        hours = 0

    return f"{hours:02d}:{minutes:02d}"


def split_stops(route_text: str) -> List[str]:
    """
    Splits route string by commas and cleaning whitespace while preserving Tamil characters.
    """
    if not route_text:
        return []

    # Clean brackets or artifacts, split by comma or Tamil punctuation
    raw_stops = re.split(r'[,،]', route_text)
    stops = []
    for s in raw_stops:
        cleaned = s.strip()
        if len(cleaned) > 1 and not re.match(r'^\d{1,2}[.:]\d{2}', cleaned):
            stops.append(cleaned)
    return stops


def parse_schedule_data(ocr_records: List[Dict[str, Any]], college_default: str = 'engineering') -> List[Dict[str, Any]]:
    """
    Parses OCR lines into structured routes.
    Expects rows containing:
    [Row Number] [Bus Code] [Bus Route / Stops list] [Time]
    """
    parsed_routes = []
    bus_code_pattern = re.compile(r'\b([A-Z][0-9A-Za-z]?|IT[0-9]+)\b')
    time_pattern = re.compile(r'(\d{1,2}[.:]\d{2}\s*(?:am|pm)?)', re.IGNORECASE)

    for record in ocr_records:
        text = record.get('text', '').strip()
        confidence = record.get('confidence', 0.90)

        if not text or len(text) < 4:
            continue

        # Skip headers
        lower_text = text.lower()
        if 'bus route for students' in lower_text or 'trip schedule' in lower_text or 'date :' in lower_text:
            continue

        # Extract Time
        time_match = time_pattern.search(text)
        departure_time = '08:00'
        if time_match:
            time_raw = time_match.group(1)
            departure_time = normalize_time(time_raw)
            # Remove time part from text to isolate route
            text_without_time = text[:time_match.start()] + text[time_match.end():]
        else:
            text_without_time = text

        tokens = text_without_time.strip().split()
        if not tokens:
            continue

        # First token might be row number (e.g. 1, 2, 29)
        idx = 0
        if tokens[0].isdigit():
            idx = 1

        if idx >= len(tokens):
            continue

        bus_code = tokens[idx]
        # Match valid bus code format (e.g. K, I1, IT9, J1, T1)
        if not bus_code_pattern.match(bus_code):
            bus_code = f"B{len(parsed_routes) + 1}"
            route_part = " ".join(tokens[idx:])
        else:
            route_part = " ".join(tokens[idx + 1:])

        college = 'arts_science' if 'IT' in bus_code or 'ARTS' in text.upper() else college_default
        stops = split_stops(route_part)

        if not stops:
            stops = [route_part] if len(route_part) > 2 else ["KLNCE Campus"]

        parsed_routes.append({
            'bus_code': bus_code,
            'route_display_name': f"{stops[0]} to KLNCE Campus" if stops else f"Bus {bus_code} Route",
            'departure_time': departure_time,
            'college': college,
            'stops': stops,
            'confidence': confidence,
            'raw_text': text
        })

    return parsed_routes

