"""
Bus search and route discovery endpoints for students and staff.
Supports bilingual search (Tamil and English) and stop autocomplete.
PyMongo / MongoDB Atlas backed.
"""

import re
from flask import Blueprint, request, jsonify
from models.database import get_db
from models.schedule import ScheduleDocument
from models.bus_route import BusRoute, _doc_to_obj as _route_to_obj
from models.route_stop import RouteStop, _doc_to_obj as _stop_to_obj
from models.master_stop import MasterStop
from services.schedule_visibility import ist_now, visibility_metadata

buses_bp = Blueprint('buses_bp', __name__, url_prefix='/api/buses')


@buses_bp.route('/search', methods=['GET'])
def search_buses_by_stop():
    """
    Core Student Feature:
    Search buses passing through a boarding point in Tamil or English.
    Query params:
        - stop: stop name query (e.g. 'Teppakulam', 'தெப்பக்குளம்', 'Thirunagar', 'Periyar')
        - trip: 'incoming' or 'outgoing' (defaults to the active IST window)
    """
    stop_query = request.args.get('stop', '').strip()
    trip_direction = request.args.get('trip')
    now = ist_now()
    metadata = visibility_metadata(now)

    if not stop_query:
        return jsonify({'error': 'Stop name query parameter is required'}), 400

    # 1. Fetch current active published schedule
    schedule = ScheduleDocument.get_published(
        trip_direction=trip_direction,
        now=now,
    )
    if not schedule:
        return jsonify({
            'message': 'No published schedule available',
            'buses': [],
            **metadata,
        }), 200

    db = get_db()

    # 2. Find bus routes in this schedule
    sched_routes = list(db['bus_routes'].find({'schedule_id': schedule.id}))
    if not sched_routes:
        return jsonify({
            'query': stop_query,
            'count': 0,
            'buses': [],
            **metadata,
        }), 200

    routes_by_id = {r['_id']: _route_to_obj(r) for r in sched_routes}
    route_ids = list(routes_by_id.keys())

    # 3. Search route_stops matching the query in English or Tamil
    term_pattern = re.compile(re.escape(stop_query), re.IGNORECASE)
    matching_stops = list(db['route_stops'].find({
        'bus_route_id': {'$in': route_ids},
        '$or': [
            {'stop_name_en': term_pattern},
            {'stop_name_ta': term_pattern},
        ]
    }))

    # 4. Group results by bus
    buses_map = {}
    for stop_doc in matching_stops:
        b_route = routes_by_id.get(stop_doc['bus_route_id'])
        if b_route and b_route.bus_code not in buses_map:
            bus_data = b_route.to_dict(include_stops=True)
            bus_data['matched_stop'] = _stop_to_obj(stop_doc).to_dict()
            buses_map[b_route.bus_code] = bus_data

    results = list(buses_map.values())
    return jsonify({
        'query': stop_query,
        'count': len(results),
        'buses': results,
        **metadata,
    }), 200


@buses_bp.route('/<bus_code>/route', methods=['GET'])
def get_bus_full_route(bus_code: str):
    """Returns sequential stop progression and timing for a specific bus."""
    schedule = ScheduleDocument.get_published()
    if not schedule:
        return jsonify({'error': 'No published schedule found'}), 404

    bus_route = BusRoute.find_by_code(schedule.id, bus_code)
    if not bus_route:
        return jsonify({'error': f'Bus {bus_code} not found in current schedule'}), 404

    return jsonify({'bus_route': bus_route.to_dict(include_stops=True)}), 200


@buses_bp.route('', methods=['GET'])
def list_published_buses():
    """Lists all buses currently operating under the published schedule."""
    schedule = ScheduleDocument.get_published()
    if not schedule:
        return jsonify({'buses': []}), 200

    routes = BusRoute.find_by_schedule(schedule.id)
    if not routes:
        return jsonify({'buses': []}), 200

    route_ids = [r.id for r in routes]
    db = get_db()
    all_stops = list(
        db['route_stops'].find({'bus_route_id': {'$in': route_ids}}).sort('stop_order', 1)
    )

    stops_by_route = {}
    for s in all_stops:
        stops_by_route.setdefault(s['bus_route_id'], []).append(_stop_to_obj(s))

    buses_data = []
    for r in routes:
        d = r.to_dict(include_stops=False)
        d['stops'] = [s.to_dict() for s in stops_by_route.get(r.id, [])]
        buses_data.append(d)

    return jsonify({'buses': buses_data}), 200


@buses_bp.route('/all-stops', methods=['GET'])
def get_all_stops():
    """Returns unique list of boarding stops for autocomplete."""
    q = request.args.get('q', '').strip()
    stops = MasterStop.search(q, limit=20 if q else 50)
    return jsonify({'stops': [s.to_dict() for s in stops]}), 200
