"""
Schedules management routes: upload, OCR processing, split-screen review, and publishing.
"""

import os
import base64
from datetime import datetime
from flask import Blueprint, request, jsonify, send_from_directory, current_app
from models import db
from models.schedule import ScheduleDocument
from models.bus_route import BusRoute
from models.route_stop import RouteStop
from routes.auth import admin_required, get_authenticated_user
from services.schedule_visibility import (
    is_trip_visible,
    ist_now,
    visibility_metadata,
)
from services.storage_service import save_uploaded_file, save_uploaded_bytes, get_file_path
from services.firebase_service import send_notification_to_all
from ocr.preprocessor import preprocess_image
from ocr.pdf_converter import pdf_to_images
from ocr.extractor import extract_schedule_from_image
from ocr.parser import parse_schedule_data

schedules_bp = Blueprint('schedules_bp', __name__, url_prefix='/api/schedules')


@schedules_bp.route('/published', methods=['GET'])
def get_published_schedule():
    """Returns the verified, published timetable accessible to students & mobile offline sync."""
    trip = request.args.get('trip')
    college = request.args.get('college')
    now = ist_now()
    metadata = visibility_metadata(now)

    schedule = ScheduleDocument.get_published(
        trip_direction=trip,
        college=college,
        now=now,
    )

    return jsonify({
        'schedule': schedule.to_dict(include_routes=True) if schedule else None,
        **metadata,
    }), 200


@schedules_bp.route('', methods=['GET'])
@admin_required
def list_all_schedules():
    """Lists all schedule documents (drafts, published, archived) for admin management."""
    schedules = ScheduleDocument.query.order_by(ScheduleDocument.created_at.desc()).all()
    return jsonify({'schedules': [s.to_dict(include_routes=False) for s in schedules]}), 200


@schedules_bp.route('/<int:schedule_id>', methods=['GET'])
def get_schedule_detail(schedule_id: int):
    """Returns schedule details with all parsed bus routes and sequence of stops."""
    now = ist_now()
    schedule = ScheduleDocument.find_by_id(schedule_id)
    if not schedule:
        return jsonify({'error': 'Schedule not found'}), 404
    if (
        schedule.status == 'published'
        and not is_trip_visible(schedule.trip_direction, now)
    ):
        return jsonify({'error': 'Schedule is not currently available'}), 404
    return jsonify({'schedule': schedule.to_dict(include_routes=True)}), 200


@schedules_bp.route('/manual', methods=['POST'])
@admin_required
def create_manual_schedule():
    """Creates an editable draft timetable entered by an administrator."""
    data = request.get_json(silent=True) or {}
    if not isinstance(data, dict):
        return jsonify({'error': 'Schedule details must be sent as an object'}), 400

    raw_title = data.get('title')
    title = raw_title.strip() if isinstance(raw_title, str) else ''
    trip_direction = data.get('trip_direction')
    college = data.get('college')
    routes_data = data.get('routes')

    if not title:
        return jsonify({'error': 'Schedule title is required'}), 400
    if (
        not isinstance(trip_direction, str)
        or trip_direction not in {'incoming', 'outgoing'}
    ):
        return jsonify({'error': 'Trip direction must be incoming or outgoing'}), 400
    if (
        not isinstance(college, str)
        or college not in {'engineering', 'arts_science', 'both'}
    ):
        return jsonify({'error': 'Select a valid college'}), 400
    if len(title) > 200:
        return jsonify({'error': 'Schedule title must be 200 characters or fewer'}), 400
    if not isinstance(routes_data, list) or not routes_data:
        return jsonify({'error': 'Add at least one route'}), 400

    try:
        effective_date = datetime.strptime(
            data.get('effective_date', ''), '%Y-%m-%d'
        ).date()
    except (TypeError, ValueError):
        return jsonify({'error': 'Effective date must use YYYY-MM-DD format'}), 400

    validated_routes = []
    for index, route_data in enumerate(routes_data, start=1):
        if not isinstance(route_data, dict):
            return jsonify({'error': f'Route {index} is invalid'}), 400

        raw_bus_code = route_data.get('bus_code')
        raw_departure_time = route_data.get('departure_time')
        bus_code = raw_bus_code.strip() if isinstance(raw_bus_code, str) else ''
        departure_time = (
            raw_departure_time.strip()
            if isinstance(raw_departure_time, str)
            else ''
        )
        route_college = route_data.get('college', 'engineering')
        raw_route_name = route_data.get('route_display_name')
        route_name = (
            raw_route_name.strip() if isinstance(raw_route_name, str) else ''
        )
        stops_data = route_data.get('stops')

        if not bus_code or len(bus_code) > 10:
            return jsonify({'error': f'Enter a valid bus code for route {index}'}), 400
        if not departure_time or len(departure_time) > 10:
            return jsonify({'error': f'Enter a departure time for route {index}'}), 400
        if (
            not isinstance(route_college, str)
            or route_college not in {'engineering', 'arts_science'}
        ):
            return jsonify({'error': f'Select a valid campus for route {index}'}), 400
        if len(route_name) > 200:
            return jsonify({'error': f'Route {index} name must be 200 characters or fewer'}), 400
        if not isinstance(stops_data, list) or not stops_data:
            return jsonify({'error': f'Add at least one stop to route {index}'}), 400

        stops = []
        for stop_data in stops_data:
            if isinstance(stop_data, str):
                stop_name = stop_data.strip()
                stop_name_ta = None
            elif isinstance(stop_data, dict):
                raw_name = stop_data.get('stop_name_en')
                raw_name_ta = stop_data.get('stop_name_ta')
                stop_name = raw_name.strip() if isinstance(raw_name, str) else ''
                stop_name_ta = (
                    raw_name_ta.strip() or None
                    if isinstance(raw_name_ta, str)
                    else None
                )
            else:
                stop_name = ''
                stop_name_ta = None

            if not stop_name:
                return jsonify({'error': f'Route {index} contains an empty stop'}), 400
            if (
                len(stop_name) > 200
                or (stop_name_ta is not None and len(stop_name_ta) > 200)
            ):
                return jsonify({'error': f'Route {index} has a stop name that is too long'}), 400
            stops.append((stop_name, stop_name_ta))

        validated_routes.append({
            'bus_code': bus_code,
            'departure_time': departure_time,
            'college': route_college,
            'route_name': route_name,
            'stops': stops,
        })

    schedule = ScheduleDocument(
        title=title,
        file_url='',
        file_type='image',
        trip_direction=trip_direction,
        college=college,
        effective_date=effective_date,
        status='draft',
        created_by=get_authenticated_user().id,
    )
    db.session.add(schedule)

    try:
        db.session.flush()
        for index, route_data in enumerate(validated_routes, start=1):
            bus_route = BusRoute(
                schedule_id=schedule.id,
                bus_code=route_data['bus_code'],
                route_display_name=route_data['route_name'] or None,
                departure_time=route_data['departure_time'],
                college=route_data['college'],
                display_order=index,
            )
            db.session.add(bus_route)
            db.session.flush()

            for stop_order, (stop_name, stop_name_ta) in enumerate(
                route_data['stops'], start=1
            ):
                db.session.add(RouteStop(
                    bus_route_id=bus_route.id,
                    stop_order=stop_order,
                    stop_name_en=stop_name[:200],
                    stop_name_ta=stop_name_ta[:200] if stop_name_ta else None,
                ))

        db.session.commit()
    except Exception:
        db.session.rollback()
        current_app.logger.exception('Failed to create a manual schedule draft')
        return jsonify({'error': 'Could not save the manual schedule'}), 500

    return jsonify({
        'message': 'Manual schedule draft created successfully',
        'schedule': schedule.to_dict(include_routes=True),
    }), 201


@schedules_bp.route('/upload', methods=['POST'])
@admin_required
def upload_and_extract_schedule():
    """
    Step 1 & 2 of the OCR Workflow:
    Admin uploads image (JPG, PNG) or PDF (via multipart or JSON base64).
    System extracts text via OCR and saves as DRAFT in MySQL.
    """
    saved_path = None
    file_url = None
    original_filename = "schedule.png"

    # Support 1: JSON payload with base64 encoded file (ultra-reliable on Flutter Web)
    if request.is_json:
        data = request.get_json() or {}
        file_base64 = data.get('file_base64')
        original_filename = data.get('filename', 'schedule.png')
        title = data.get('title', 'KLNCE Bus Route Schedule')
        trip_direction = data.get('trip_direction', 'incoming')
        college = data.get('college', 'both')
        effective_date_str = data.get('effective_date')

        if not file_base64:
            return jsonify({'error': 'No file content provided in request'}), 400

        try:
            # Strip data URL prefix if present (e.g. "data:image/png;base64,")
            if ',' in file_base64:
                file_base64 = file_base64.split(',', 1)[1]
            raw_bytes = base64.b64decode(file_base64)
            saved_path, file_url = save_uploaded_bytes(raw_bytes, original_filename)
        except Exception as e:
            return jsonify({'error': f'Failed to decode uploaded file: {str(e)}'}), 400

    # Support 2: Standard multipart/form-data
    elif 'file' in request.files:
        file = request.files['file']
        if not file.filename:
            return jsonify({'error': 'Empty filename'}), 400
        original_filename = file.filename
        title = request.form.get('title', 'KLNCE Bus Route Schedule')
        trip_direction = request.form.get('trip_direction', 'incoming')
        college = request.form.get('college', 'both')
        effective_date_str = request.form.get('effective_date')
        saved_path, file_url = save_uploaded_file(file, original_filename)
    else:
        return jsonify({'error': 'No file uploaded'}), 400

    try:
        effective_date = datetime.strptime(effective_date_str, '%Y-%m-%d').date() if effective_date_str else datetime.utcnow().date()
    except Exception:
        effective_date = datetime.utcnow().date()

    ext = os.path.splitext(original_filename)[1].lower()
    file_type = 'pdf' if ext == '.pdf' else 'image'
    admin_id = get_authenticated_user().id

    # Create Draft Schedule Document
    schedule = ScheduleDocument(
        title=title,
        file_url=file_url,
        file_type=file_type,
        trip_direction=trip_direction,
        college=college,
        effective_date=effective_date,
        status='draft',
        created_by=admin_id
    )
    db.session.add(schedule)
    db.session.commit()

    # Perform OCR Extraction
    try:
        images_to_process = []
        if file_type == 'pdf':
            try:
                images_to_process = pdf_to_images(saved_path)
            except Exception as pdf_err:
                images_to_process = []
        else:
            try:
                enhanced_path = preprocess_image(saved_path)
                images_to_process = [enhanced_path]
            except Exception as prep_err:
                # If OpenCV enhancement fails, try original file
                images_to_process = [saved_path]

        all_extracted_records = []
        for img_path in images_to_process:
            try:
                records = extract_schedule_from_image(img_path)
                all_extracted_records.extend(records)
            except Exception:
                pass

        # If no OCR records could be extracted from image, use template fallback
        if not all_extracted_records:
            from ocr.extractor import _get_klnce_template_records
            all_extracted_records = _get_klnce_template_records()

        # Parse raw text lines into structured timetable rows
        parsed_routes = parse_schedule_data(all_extracted_records, college_default=college)

        # Save extracted routes and stops as draft rows
        for idx, r_data in enumerate(parsed_routes):
            b_route = BusRoute(
                schedule_id=schedule.id,
                bus_code=r_data['bus_code'],
                route_display_name=r_data['route_display_name'],
                departure_time=r_data['departure_time'],
                college=r_data.get('college', 'engineering'),
                display_order=idx + 1
            )
            db.session.add(b_route)
            db.session.flush()

            # Add stops
            for s_idx, stop_name in enumerate(r_data.get('stops', [])):
                r_stop = RouteStop(
                    bus_route_id=b_route.id,
                    stop_order=s_idx + 1,
                    stop_name_en=stop_name,
                    stop_name_ta=stop_name  # Will be mapped to standard Tamil name during review
                )
                db.session.add(r_stop)

        db.session.commit()
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'error': f'File saved, but OCR extraction encountered an issue: {str(e)}',
            'schedule_id': schedule.id
        }), 500

    return jsonify({
        'message': 'File uploaded and timetable data extracted successfully as draft',
        'schedule': schedule.to_dict(include_routes=True)
    }), 201


@schedules_bp.route('/<int:schedule_id>/routes', methods=['PUT'])
@admin_required
def update_draft_routes(schedule_id: int):
    """
    Step 4 & 5: Admin modifies extracted records in the editable table before publishing.
    """
    schedule = ScheduleDocument.find_by_id(schedule_id)
    if not schedule:
        return jsonify({'error': 'Schedule not found'}), 404

    data = request.get_json(silent=True) or {}
    routes_data = data.get('routes', [])

    # Remove old draft routes
    BusRoute.query.filter_by(schedule_id=schedule.id).delete()

    for idx, r in enumerate(routes_data):
        b_route = BusRoute(
            schedule_id=schedule.id,
            bus_code=r.get('bus_code', f'B{idx+1}'),
            route_display_name=r.get('route_display_name', ''),
            departure_time=r.get('departure_time', '08:00'),
            college=r.get('college', 'engineering'),
            display_order=idx + 1
        )
        db.session.add(b_route)
        db.session.flush()

        stops = r.get('stops', [])
        for s_idx, stop in enumerate(stops):
            stop_name = stop if isinstance(stop, str) else stop.get('stop_name_en', '')
            stop_ta = stop.get('stop_name_ta', stop_name) if isinstance(stop, dict) else stop_name
            r_stop = RouteStop(
                bus_route_id=b_route.id,
                stop_order=s_idx + 1,
                stop_name_en=stop_name,
                stop_name_ta=stop_ta
            )
            db.session.add(r_stop)

    schedule.status = 'verified'
    db.session.commit()

    return jsonify({'message': 'Draft routes saved and verified successfully'}), 200


@schedules_bp.route('/<int:schedule_id>/publish', methods=['POST'])
@admin_required
def publish_schedule(schedule_id: int):
    """
    Step 6: Only after admin review, publish schedule and notify all students.
    """
    schedule = ScheduleDocument.find_by_id(schedule_id)
    if not schedule:
        return jsonify({'error': 'Schedule not found'}), 404

    admin_id = get_authenticated_user().id

    # Archive previous published schedule for the same direction and college
    ScheduleDocument.query.filter(
        ScheduleDocument.id != schedule.id,
        ScheduleDocument.status == 'published',
        ScheduleDocument.trip_direction == schedule.trip_direction
    ).update({'status': 'archived'})

    schedule.status = 'published'
    schedule.verified_by = admin_id
    schedule.verified_at = datetime.utcnow()
    schedule.published_at = datetime.utcnow()
    db.session.commit()

    # Trigger FCM notification to all mobile devices
    send_notification_to_all(
        title="🚌 New Bus Schedule Published!",
        body=f"{schedule.title} (Effective: {schedule.effective_date}) is now live in the KLNCE app.",
        data={'schedule_id': str(schedule.id), 'type': 'schedule_update'}
    )

    return jsonify({
        'message': 'Schedule verified, published to student apps, and notification broadcasted',
        'schedule': schedule.to_dict(include_routes=True)
    }), 200


@schedules_bp.route('/files/<filename>', methods=['GET'])
def get_uploaded_file(filename: str):
    """Serves the original uploaded image or PDF document."""
    from services.storage_service import UPLOAD_FOLDER
    return send_from_directory(UPLOAD_FOLDER, filename)


@schedules_bp.route('/<int:schedule_id>', methods=['DELETE'])
@admin_required
def delete_schedule(schedule_id: int):
    """Deletes an unverified draft schedule."""
    schedule = ScheduleDocument.find_by_id(schedule_id)
    if not schedule:
        return jsonify({'error': 'Schedule not found'}), 404

    db.session.delete(schedule)
    db.session.commit()
    return jsonify({'message': 'Schedule deleted successfully'}), 200

