"""
GPS Live Tracking routes for driver location reporting and student live tracking.
"""

from datetime import datetime
from flask import Blueprint, request, jsonify
from models import db
from models.gps_location import GpsLocation
from routes.auth import driver_or_admin_required, get_authenticated_user

gps_bp = Blueprint('gps_bp', __name__, url_prefix='/api/gps')


@gps_bp.route('/update', methods=['POST'])
@driver_or_admin_required
def update_gps_location():
    """
    Driver app posts GPS location every 10 seconds during active trip.
    Body:
        {
            "bus_code": "K",
            "latitude": 9.8762,
            "longitude": 78.0772,
            "speed_kmh": 34.5
        }
    """
    data = request.get_json(silent=True) or {}
    bus_code = data.get('bus_code', '').strip().upper()
    lat = data.get('latitude')
    lng = data.get('longitude')
    speed = data.get('speed_kmh', 0.0)

    if not bus_code or lat is None or lng is None:
        return jsonify({'error': 'bus_code, latitude, and longitude are required'}), 400

    driver_id = get_authenticated_user().id

    gps_entry = GpsLocation(
        bus_code=bus_code,
        driver_id=driver_id,
        latitude=lat,
        longitude=lng,
        speed_kmh=speed,
        is_active_trip=True,
        recorded_at=datetime.utcnow()
    )
    db.session.add(gps_entry)
    db.session.commit()

    return jsonify({'status': 'updated', 'location': gps_entry.to_dict()}), 200


@gps_bp.route('/live/<bus_code>', methods=['GET'])
def get_live_bus_location(bus_code: str):
    """Returns real-time GPS position for an individual bus for student map rendering."""
    location = GpsLocation.get_latest_for_bus(bus_code.upper())
    if not location:
        return jsonify({
            'bus_code': bus_code.upper(),
            'is_tracking': False,
            'message': 'No live GPS signal currently received for this bus'
        }), 200

    return jsonify({
        'bus_code': bus_code.upper(),
        'is_tracking': True,
        'location': location.to_dict()
    }), 200


@gps_bp.route('/active', methods=['GET'])
def get_all_active_buses():
    """Returns latest GPS location for all buses currently on an active trip."""
    active_records = GpsLocation.get_active_buses()
    return jsonify({
        'count': len(active_records),
        'active_buses': [rec.to_dict() for rec in active_records]
    }), 200


@gps_bp.route('/end-trip', methods=['POST'])
@driver_or_admin_required
def end_trip():
    """Driver ends their morning or evening transport trip."""
    data = request.get_json(silent=True) or {}
    bus_code = data.get('bus_code', '').strip().upper()

    if not bus_code:
        return jsonify({'error': 'bus_code is required'}), 400

    # Mark all active records for this bus as inactive
    GpsLocation.query.filter_by(bus_code=bus_code, is_active_trip=True).update({'is_active_trip': False})
    db.session.commit()

    return jsonify({'message': f'Trip for Bus {bus_code} completed successfully'}), 200

