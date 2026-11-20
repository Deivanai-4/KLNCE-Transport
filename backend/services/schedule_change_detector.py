# -*- coding: utf-8 -*-
"""
services/schedule_change_detector.py — Compares published daily schedules and generates
structured change summaries, identifies affected buses and routes, and retrieves
the affected student list for schedule-change announcements.
"""

from typing import Any, Dict, List, Optional, Set, Tuple
from models.database import get_db


def detect_schedule_changes(
    old_schedule_data: Dict[str, Any],
    new_schedule_data: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Compare old daily schedule state against updated daily schedule state.
    Returns:
      {
        "has_changes": bool,
        "change_bullets": list[str],
        "affected_buses": list[str],
        "affected_routes": list[str],
        "affected_students_count": int,
        "affected_student_ids": list[int],
        "suggested_title": str,
        "suggested_message": str,
        "date": str,
        "session": str
      }
    """
    date_str = new_schedule_data.get("date") or old_schedule_data.get("date") or ""
    session_str = (new_schedule_data.get("session") or old_schedule_data.get("session") or "morning").lower()
    session_label = "Morning" if session_str == "morning" else "Afternoon"

    old_buses = old_schedule_data.get("buses") or []
    new_buses = new_schedule_data.get("buses") or []

    # Map by bus_number for quick lookup
    old_bus_map: Dict[str, Dict[str, Any]] = {
        (b.get("bus_number") or "").strip().upper(): b for b in old_buses if b.get("bus_number")
    }
    new_bus_map: Dict[str, Dict[str, Any]] = {
        (b.get("bus_number") or "").strip().upper(): b for b in new_buses if b.get("bus_number")
    }

    change_bullets: List[str] = []
    affected_buses: Set[str] = set()
    affected_routes: Set[str] = set()

    # 1. Detect Removed / Cancelled buses
    for bus_num, old_b in old_bus_map.items():
        if bus_num not in new_bus_map:
            route_name = old_b.get("route_name", "Unknown Route")
            change_bullets.append(f"Bus {bus_num} on {route_name} cancelled / removed.")
            affected_buses.add(bus_num)
            affected_routes.add(route_name)

    # 2. Detect Added buses
    for bus_num, new_b in new_bus_map.items():
        if bus_num not in old_bus_map:
            route_name = new_b.get("route_name", "Unknown Route")
            dep_time = new_b.get("departure_time", "")
            change_bullets.append(f"New bus {bus_num} added on {route_name} departing at {dep_time}.")
            affected_buses.add(bus_num)
            affected_routes.add(route_name)

    # 3. Detect Modified buses
    for bus_num, new_b in new_bus_map.items():
        if bus_num in old_bus_map:
            old_b = old_bus_map[bus_num]
            old_route = old_b.get("route_name", "").strip()
            new_route = new_b.get("route_name", "").strip()
            old_dep = old_b.get("departure_time", "").strip()
            new_dep = new_b.get("departure_time", "").strip()

            bus_changed = False

            # Route changed
            if old_route.lower() != new_route.lower():
                change_bullets.append(f"Bus {bus_num} route changed from {old_route} to {new_route}.")
                affected_buses.add(bus_num)
                affected_routes.add(old_route)
                affected_routes.add(new_route)
                bus_changed = True

            # Departure time changed
            if old_dep and new_dep and old_dep != new_dep:
                change_bullets.append(f"Bus {bus_num} departure time changed from {old_dep} to {new_dep}.")
                affected_buses.add(bus_num)
                affected_routes.add(new_route)
                bus_changed = True

            # Stops or timings changed
            old_stops = old_b.get("stops") or []
            new_stops = new_b.get("stops") or []

            old_stop_map = {(s.get("stop_name") or "").strip().lower(): s.get("time") for s in old_stops}
            new_stop_map = {(s.get("stop_name") or "").strip().lower(): s.get("time") for s in new_stops}

            stop_diffs: List[str] = []
            for stop_name, new_time in new_stop_map.items():
                if stop_name in old_stop_map:
                    old_time = old_stop_map[stop_name]
                    if old_time and new_time and old_time != new_time:
                        stop_diffs.append(f"{stop_name.title()} ({old_time} -> {new_time})")
                else:
                    stop_diffs.append(f"{stop_name.title()} added ({new_time})")

            for stop_name in old_stop_map:
                if stop_name not in new_stop_map:
                    stop_diffs.append(f"{stop_name.title()} removed")

            if stop_diffs:
                change_bullets.append(f"Bus {bus_num} ({new_route}) stop timing changes: " + ", ".join(stop_diffs[:4]))
                affected_buses.add(bus_num)
                affected_routes.add(new_route)
                bus_changed = True

    # 4. Also check explicit update_summary if provided by admin
    custom_summary = new_schedule_data.get("update_summary", "").strip()
    if custom_summary:
        change_bullets.append(f"Note: {custom_summary}")

    has_changes = len(change_bullets) > 0

    # Clean empty strings
    clean_routes = [r for r in affected_routes if r]
    clean_buses = [b for b in affected_buses if b]

    # Retrieve affected students from MongoDB
    affected_students_count = 0
    affected_student_ids: List[int] = []

    if has_changes:
        db = get_db()
        student_query: Dict[str, Any] = {
            "is_transport_active": True,
            "$or": []
        }
        if clean_routes:
            student_query["$or"].append({"route_name": {"$in": clean_routes}})
        if clean_buses:
            student_query["$or"].append({"bus_number": {"$in": clean_buses}})

        if student_query["$or"]:
            students = list(db["students"].find(student_query, {"_id": 1}))
            affected_student_ids = [int(s["_id"]) for s in students if "_id" in s]
            # Deduplicate
            affected_student_ids = list(dict.fromkeys(affected_student_ids))
            affected_students_count = len(affected_student_ids)

    # Generate suggested announcement title & body
    if has_changes:
        suggested_title = f"{session_label} Schedule Update — {date_str}"
        body_points = "\n• ".join(change_bullets)
        suggested_message = (
            f"Notice for {session_label} Bus Schedule ({date_str}):\n"
            f"• {body_points}\n\n"
            f"Please check your KLNCE Transport app for updated timings and live details."
        )
    else:
        suggested_title = f"{session_label} Bus Schedule — {date_str}"
        suggested_message = f"KLNCE Transport: Bus schedules for {date_str} ({session_label}) are published."

    return {
        "has_changes": has_changes,
        "change_bullets": change_bullets,
        "affected_buses": sorted(clean_buses),
        "affected_routes": sorted(clean_routes),
        "affected_students_count": affected_students_count,
        "affected_student_ids": affected_student_ids,
        "suggested_title": suggested_title,
        "suggested_message": suggested_message,
        "date": date_str,
        "session": session_str,
    }
