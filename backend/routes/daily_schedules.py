"""
Daily Bus Schedule management endpoints for transport administrators and students.
Allows the administrator to create, draft, preview, publish, and edit date-specific bus schedules.
PyMongo / MongoDB Atlas backed.
"""

from datetime import datetime
from flask import Blueprint, request, jsonify, current_app
from flask_jwt_extended import verify_jwt_in_request, get_jwt_identity
from pymongo.errors import PyMongoError

from models.database import get_db
from models.daily_schedule import DailySchedule, _doc_to_obj
from models.user import User
from routes.auth import admin_required, get_authenticated_user
from services.schedule_visibility import ist_now
from services.schedule_change_detector import detect_schedule_changes

daily_schedules_bp = Blueprint('daily_schedules_bp', __name__, url_prefix='/api/daily-schedules')


def _is_request_admin() -> bool:
    """Helper to check if current request has a valid admin JWT."""
    try:
        verify_jwt_in_request(optional=True)
        email = get_jwt_identity()
        if not email:
            return False
        user = User.find_by_email(email)
        return user is not None and user.role == 'admin' and user.is_active
    except Exception:
        return False


def _validate_date_string(date_str: str) -> bool:
    """Ensure date is in YYYY-MM-DD format and is a valid calendar date."""
    if not isinstance(date_str, str) or not date_str.strip():
        return False
    try:
        datetime.strptime(date_str.strip(), '%Y-%m-%d')
        return True
    except (ValueError, TypeError):
        return False


def _validate_buses_data(buses_data: list) -> tuple[bool, str, list]:
    """Validate list of bus records and stops."""
    if not isinstance(buses_data, list) or not buses_data:
        return False, "At least one bus is required in the schedule", []

    validated_buses = []
    seen_bus_numbers = set()

    for idx, bus in enumerate(buses_data, start=1):
        if not isinstance(bus, dict):
            return False, f"Bus {idx} format is invalid", []

        raw_number = bus.get('bus_number')
        bus_number = str(raw_number).strip().upper() if raw_number else ''
        if not bus_number or len(bus_number) > 15:
            return False, f"Bus {idx}: Enter a valid bus number (e.g. S1, M1, 15)", []

        if bus_number in seen_bus_numbers:
            return False, f"Duplicate bus number '{bus_number}' found in this schedule", []
        seen_bus_numbers.add(bus_number)

        raw_route = bus.get('route_name')
        route_name = str(raw_route).strip() if raw_route else ''
        if not route_name or len(route_name) > 200:
            return False, f"Bus {bus_number}: Enter a route name or destination", []

        departure_time = str(bus.get('departure_time', '')).strip()
        route_id = bus.get('route_id')
        if route_id is not None:
            try:
                route_id = int(route_id)
            except (ValueError, TypeError):
                route_id = None

        stops_data = bus.get('stops', [])
        if not isinstance(stops_data, list) or not stops_data:
            return False, f"Bus {bus_number}: Add at least one stop with arrival time", []

        validated_stops = []
        for s_idx, stop in enumerate(stops_data, start=1):
            if isinstance(stop, str):
                s_name = stop.strip()
                s_time = departure_time or '07:00 AM'
            elif isinstance(stop, dict):
                s_name = str(stop.get('stop_name', '')).strip()
                s_time = str(stop.get('arrival_time', '')).strip() or departure_time
            else:
                s_name = ''
                s_time = ''

            if not s_name:
                return False, f"Bus {bus_number}: Stop {s_idx} name cannot be empty", []

            validated_stops.append({
                'stop_order': s_idx,
                'stop_name': s_name[:200],
                'arrival_time': s_time[:20] if s_time else departure_time,
            })

        validated_buses.append({
            'bus_number': bus_number,
            'route_id': route_id,
            'route_name': route_name,
            'departure_time': departure_time or (validated_stops[0]['arrival_time'] if validated_stops else '07:00 AM'),
            'stops': validated_stops,
        })

    return True, "", validated_buses


@daily_schedules_bp.route('', methods=['GET'])
def list_daily_schedules():
    """
    List daily bus schedules filtered by date, session, and status.
    Students only see published schedules. Admins can view drafts and published.
    """
    date_param = request.args.get('date', '').strip()
    session_param = request.args.get('session', '').strip().lower()
    status_param = request.args.get('status', '').strip().lower()
    bus_param = request.args.get('bus_number', '').strip().upper() or None

    is_admin = _is_request_admin()
    status_filter = status_param if (is_admin and status_param) else ('published' if not is_admin else None)

    try:
        schedules = DailySchedule.list_schedules(
            date_str=date_param or None,
            session=session_param or None,
            status=status_filter,
            bus_number=bus_param,
            limit=100
        )
        return jsonify({
            'daily_schedules': [s.to_dict() for s in schedules],
            'count': len(schedules),
        }), 200
    except PyMongoError:
        current_app.logger.exception('Failed to list daily schedules')
        return jsonify({'error': 'Could not load daily schedules'}), 500


@daily_schedules_bp.route('/<int:schedule_id>', methods=['GET'])
def get_daily_schedule_detail(schedule_id: int):
    """Fetch details of a specific daily schedule."""
    is_admin = _is_request_admin()
    try:
        schedule = DailySchedule.find_by_id(schedule_id)
        if not schedule:
            return jsonify({'error': 'Daily schedule not found'}), 404

        if not is_admin and schedule.status != 'published':
            return jsonify({'error': 'Schedule is not published yet'}), 404

        return jsonify({'daily_schedule': schedule.to_dict()}), 200
    except PyMongoError:
        current_app.logger.exception('Failed to get daily schedule detail')
        return jsonify({'error': 'Could not load schedule details'}), 500


@daily_schedules_bp.route('', methods=['POST'])
@admin_required
def create_daily_schedule():
    """
    Admin creates a new daily schedule for a date + session.
    Can be saved as 'draft' or 'published'.
    """
    data = request.get_json(silent=True) or {}
    if not isinstance(data, dict):
        return jsonify({'error': 'Request payload must be a JSON object'}), 400

    raw_date = data.get('date')
    if not _validate_date_string(raw_date):
        return jsonify({'error': 'Valid date in YYYY-MM-DD format is required'}), 400
    date_str = raw_date.strip()

    raw_session = str(data.get('session', 'morning')).strip().lower()
    if raw_session not in {'morning', 'afternoon'}:
        return jsonify({'error': 'Session must be either "morning" or "afternoon"'}), 400

    raw_status = str(data.get('status', 'draft')).strip().lower()
    if raw_status not in {'draft', 'published'}:
        return jsonify({'error': 'Status must be either "draft" or "published"'}), 400

    ok, error_msg, validated_buses = _validate_buses_data(data.get('buses', []))
    if not ok:
        return jsonify({'error': error_msg}), 400

    admin = get_authenticated_user()

    try:
        # Check if a schedule already exists for this date and session
        existing = DailySchedule.find_by_date_and_session(date_str, raw_session)
        if existing:
            return jsonify({
                'error': f'A {raw_session} schedule already exists for {date_str}. Please edit the existing schedule.',
                'existing_id': existing.id,
                'existing_status': existing.status,
            }), 409

        now_utc = datetime.utcnow()
        published_at = now_utc if raw_status == 'published' else None

        schedule = DailySchedule(
            date=date_str,
            session=raw_session,
            status=raw_status,
            is_updated=False,
            version=1,
            created_by=admin.id,
            buses=validated_buses,
            created_at=now_utc,
            updated_at=now_utc,
            published_at=published_at,
        )
        schedule.save()

        return jsonify({
            'message': f'Daily schedule {"published" if raw_status == "published" else "saved as draft"} successfully',
            'daily_schedule': schedule.to_dict(),
        }), 201

    except PyMongoError:
        current_app.logger.exception('Failed to create daily schedule')
        return jsonify({'error': 'Could not save daily schedule'}), 500


@daily_schedules_bp.route('/<int:schedule_id>', methods=['PUT'])
@admin_required
def update_daily_schedule(schedule_id: int):
    """
    Admin updates an existing daily schedule.
    If the schedule was already published, automatically flags it as updated.
    """
    data = request.get_json(silent=True) or {}
    if not isinstance(data, dict):
        return jsonify({'error': 'Request payload must be a JSON object'}), 400

    try:
        schedule = DailySchedule.find_by_id(schedule_id)
        if not schedule:
            return jsonify({'error': 'Daily schedule not found'}), 404

        old_schedule_dict = schedule.to_dict()
        was_published = (schedule.status == 'published')

        # Validate date if provided
        if 'date' in data:
            raw_date = data.get('date')
            if not _validate_date_string(raw_date):
                return jsonify({'error': 'Valid date in YYYY-MM-DD format is required'}), 400
            # Check collision with another schedule
            target_date = raw_date.strip()
            target_session = str(data.get('session', schedule.session)).strip().lower()
            existing = DailySchedule.find_by_date_and_session(target_date, target_session)
            if existing and existing.id != schedule.id:
                return jsonify({'error': f'Another schedule exists for {target_date} ({target_session})'}), 409
            schedule.date = target_date

        if 'session' in data:
            raw_session = str(data.get('session', '')).strip().lower()
            if raw_session not in {'morning', 'afternoon'}:
                return jsonify({'error': 'Session must be either "morning" or "afternoon"'}), 400
            schedule.session = raw_session

        if 'status' in data:
            raw_status = str(data.get('status', '')).strip().lower()
            if raw_status in {'draft', 'published'}:
                if raw_status == 'published' and schedule.status != 'published':
                    schedule.published_at = datetime.utcnow()
                schedule.status = raw_status

        if 'buses' in data:
            ok, error_msg, validated_buses = _validate_buses_data(data.get('buses', []))
            if not ok:
                return jsonify({'error': error_msg}), 400
            schedule.buses = validated_buses

        if 'update_summary' in data:
            schedule.update_summary = str(data.get('update_summary', '')).strip()

        # If already published, mark as updated, increment version and flag for SMS
        if schedule.status == 'published':
            schedule.is_updated = True
            schedule.version += 1
            schedule.pending_sms_alert = True

        schedule.updated_at = datetime.utcnow()
        schedule.save()

        # If schedule was already published, run change detection
        change_info = None
        if was_published:
            change_info = detect_schedule_changes(old_schedule_dict, schedule.to_dict())

        resp = {
            'message': 'Daily schedule updated successfully',
            'daily_schedule': schedule.to_dict(),
        }
        if change_info and change_info['has_changes']:
            resp['schedule_change_detected'] = True
            resp['change_summary'] = change_info

        return jsonify(resp), 200

    except PyMongoError:
        current_app.logger.exception('Failed to update daily schedule %s', schedule_id)
        return jsonify({'error': 'Could not update daily schedule'}), 500


@daily_schedules_bp.route('/stats', methods=['GET'])
@admin_required
def get_daily_schedule_stats():
    """
    Return real-time schedule statistics for the admin dashboard overview.
    Requires admin JWT.
    """
    try:
        db = get_db()
        col = db['daily_schedules']
        today_str = ist_now().strftime('%Y-%m-%d')

        today_published = col.count_documents({'date': today_str, 'status': 'published'})
        today_drafts = col.count_documents({'date': today_str, 'status': 'draft'})
        total_published = col.count_documents({'status': 'published'})
        total_drafts = col.count_documents({'status': 'draft'})
        recently_updated = col.count_documents({'is_updated': True, 'status': 'published'})
        pending_sms_alerts = col.count_documents({'pending_sms_alert': True})

        # Count total unique buses and routes from database
        master_buses = set(db['bus_routes'].distinct('bus_code'))
        daily_buses = set(db['daily_schedules'].distinct('buses.bus_number'))
        all_buses = {b for b in (master_buses | daily_buses) if b}
        total_buses = len(all_buses)
        total_routes = db['bus_routes'].count_documents({})

        return jsonify({
            'today_published': today_published,
            'today_drafts': today_drafts,
            'total_published': total_published,
            'total_drafts': total_drafts,
            'recently_updated': recently_updated,
            'pending_sms_alerts': pending_sms_alerts,
            'total_buses': total_buses,
            'total_routes': total_routes,
            'date': today_str,
        }), 200
    except PyMongoError:
        current_app.logger.exception('Failed to get daily schedule stats')
        return jsonify({'error': 'Could not load schedule statistics'}), 500


@daily_schedules_bp.route('/<int:schedule_id>/publish', methods=['POST'])
@admin_required
def publish_daily_schedule(schedule_id: int):
    """
    Publish a draft or revised daily schedule so students can view it.
    Identifies updates if the schedule was previously published.
    """
    try:
        schedule = DailySchedule.find_by_id(schedule_id)
        if not schedule:
            return jsonify({'error': 'Daily schedule not found'}), 404

        was_already_published = (schedule.status == 'published')
        now_utc = datetime.utcnow()

        schedule.status = 'published'
        schedule.published_at = now_utc
        schedule.updated_at = now_utc

        if was_already_published:
            schedule.is_updated = True
            schedule.version += 1
            schedule.pending_sms_alert = True

        schedule.save()

        return jsonify({
            'message': 'Daily schedule published and visible to students',
            'daily_schedule': schedule.to_dict(),
        }), 200

    except PyMongoError:
        current_app.logger.exception('Failed to publish daily schedule %s', schedule_id)
        return jsonify({'error': 'Could not publish daily schedule'}), 500


@daily_schedules_bp.route('/<int:schedule_id>', methods=['DELETE'])
@admin_required
def delete_daily_schedule(schedule_id: int):
    """
    Delete a daily schedule draft or archive a published schedule.
    Published schedules are never permanently removed from MongoDB to preserve history.
    """
    try:
        schedule = DailySchedule.find_by_id(schedule_id)
        if not schedule:
            return jsonify({'error': 'Daily schedule not found'}), 404

        if schedule.status == 'published':
            # Do not permanently delete published schedule history
            schedule.status = 'archived'
            schedule.updated_at = datetime.utcnow()
            schedule.save()
            return jsonify({
                'message': 'Published schedule archived to preserve history',
                'archived': True,
                'status': 'archived',
            }), 200

        schedule.delete()
        return jsonify({'message': 'Daily schedule deleted successfully'}), 200
    except PyMongoError:
        current_app.logger.exception('Failed to delete daily schedule %s', schedule_id)
        return jsonify({'error': 'Could not delete daily schedule'}), 500
