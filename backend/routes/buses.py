"""
Bus search and route discovery endpoints for students and staff.
Supports bilingual search (Tamil and English) and stop autocomplete.
"""

from flask import Blueprint, request, jsonify
from models import db
from models.schedule import ScheduleDocument
from models.bus_route import BusRoute
from models.route_stop import RouteStop
from models.master_stop import MasterStop

buses_bp = Blueprint('buses_bp', __name__, url_prefix='/api/buses')


@buses_bp.route('/search', methods=['GET'])
def search_buses_by_stop():
    """
    Core Student Feature:
    Search buses passing through a boarding point in Tamil or English.
    Query params:
        - stop: stop name query (e.g. 'Teppakulam', 'தெப்பக்குளம்', 'Thirunagar', 'Periyar')
        - trip: 'incoming' or 'outgoing' (default: 'incoming')
    """
    stop_query = request.args.get('stop', '').strip()
    trip_direction = request.args.get('trip', 'incoming')

    if not stop_query:
        return jsonify({'error': 'Stop name query parameter is required'}), 400

    # 1. Fetch current active published schedule
    schedule = ScheduleDocument.get_published(trip_direction=trip_direction)
    if not schedule:
        return jsonify({'message': 'No published schedule available', 'buses': []}), 200

    # 2. Search route_stops matching the query in English, Tamil, or master stop aliases
    term = f"%{stop_query}%"
    matching_stops = RouteStop.query.join(BusRoute).filter(
        BusRoute.schedule_id == schedule.id,
        db.or_(
            RouteStop.stop_name_en.ilike(term),
            RouteStop.stop_name_ta.ilike(term)
        )
    ).all()

    # Group results by bus
    buses_map = {}
    for stop in matching_stops:
        b_route = stop.route
        if b_route.bus_code not in buses_map:
            bus_data = b_route.to_dict(include_stops=True)
            bus_data['matched_stop'] = stop.to_dict()
            buses_map[b_route.bus_code] = bus_data

    results = list(buses_map.values())
    return jsonify({
        'query': stop_query,
        'count': len(results),
        'buses': results
    }), 200


@buses_bp.route('/<bus_code>/route', methods=['GET'])
def get_bus_full_route(bus_code: str):
    """Returns sequential stop progression and timing for a specific bus."""
    schedule = ScheduleDocument.get_published()
    if not schedule:
        return jsonify({'error': 'No published schedule found'}), 404

    bus_route = BusRoute.query.filter_by(
        schedule_id=schedule.id,
        bus_code=bus_code
    ).first()

    if not bus_route:
        return jsonify({'error': f'Bus {bus_code} not found in current schedule'}), 404

    return jsonify({'bus_route': bus_route.to_dict(include_stops=True)}), 200


@buses_bp.route('', methods=['GET'])
def list_published_buses():
    """Lists all buses currently operating under the published schedule."""
    schedule = ScheduleDocument.get_published()
    if not schedule:
        return jsonify({'buses': []}), 200

    routes = BusRoute.query.filter_by(schedule_id=schedule.id).order_by(BusRoute.display_order.asc()).all()
    return jsonify({'buses': [r.to_dict(include_stops=True) for r in routes]}), 200


@buses_bp.route('/all-stops', methods=['GET'])
def get_all_stops():
    """Returns unique list of boarding stops for autocomplete."""
    q = request.args.get('q', '').strip()
    if q:
        stops = MasterStop.search(q, limit=20)
    else:
        stops = MasterStop.query.order_by(MasterStop.standard_name_en.asc()).limit(50).all()

    return jsonify({'stops': [s.to_dict() for s in stops]}), 200

