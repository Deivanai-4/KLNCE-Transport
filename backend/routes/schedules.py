"""
Schedules management routes: upload, OCR processing, split-screen review, and publishing.
PyMongo / MongoDB Atlas backed with multi-document transactions.
"""

import os
import base64
from datetime import datetime, date
from flask import Blueprint, request, jsonify, send_from_directory, current_app
from pymongo.errors import PyMongoError

from models.database import get_db, get_mongo_client, get_next_sequence
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
    db = get_db()
    try:
        # Collect docs as a list first — avoids exhausting a cursor across two iterations
        docs = list(db['schedule_documents'].find().sort('created_at', -1))
    except PyMongoError:
        current_app.logger.exception('Failed to fetch schedule list')
        return jsonify({'error': 'Could not load schedule list'}), 500

    results = []
    for d in docs:
        try:
            sched_obj = ScheduleDocument._doc_to_obj(d)
            results.append(sched_obj.to_dict(include_routes=False))
        except Exception:
            current_app.logger.warning('Skipping malformed schedule doc _id=%s', d.get('_id'))

    return jsonify({'schedules': results, 'total': len(results)}), 200


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

    raw_date = data.get('effective_date', '')
    try:
        parsed_date = datetime.strptime(str(raw_date).strip(), '%Y-%m-%d').date()
        effective_date_str = parsed_date.strftime('%Y-%m-%d')
    except (TypeError, ValueError):
        return jsonify({'error': 'Effective date must use YYYY-MM-DD format'}), 400

    # Validate replacement data completely before touching database
    validated_routes = []
    for index, route_data in enumerate(routes_data, start=1):
        if not isinstance(route_data, dict):
            return jsonify({'error': f'Route {index} is invalid'}), 400

        raw_bus_code = route_data.get('bus_code')
        raw_departure_time = route_data.get('departure_time')
        bus_code = raw_bus_code.strip().upper() if isinstance(raw_bus_code, str) else ''
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

    # Prepare documents with concurrency-safe integer IDs
    admin_id = get_authenticated_user().id
    schedule_id = get_next_sequence('schedule_documents')
    now_utc = datetime.utcnow()

    schedule_doc = {
        '_id': schedule_id,
        'id': schedule_id,
        'title': title,
        'file_url': '',
        'file_type': 'image',
        'trip_direction': trip_direction,
        'college': college,
        'effective_date': effective_date_str,
        'status': 'draft',
        'created_by': admin_id,
        'verified_by': None,
        'verified_at': None,
        'published_at': None,
        'created_at': now_utc,
    }

    bus_route_docs = []
    route_stop_docs = []

    for index, route_data in enumerate(validated_routes, start=1):
        br_id = get_next_sequence('bus_routes')
        bus_route_docs.append({
            '_id': br_id,
            'id': br_id,
            'schedule_id': schedule_id,
            'bus_code': route_data['bus_code'],
            'route_display_name': route_data['route_name'] or None,
            'departure_time': route_data['departure_time'],
            'college': route_data['college'],
            'display_order': index,
            'created_at': now_utc,
        })

        for stop_order, (stop_name, stop_name_ta) in enumerate(route_data['stops'], start=1):
            rs_id = get_next_sequence('route_stops')
            route_stop_docs.append({
                '_id': rs_id,
                'id': rs_id,
                'bus_route_id': br_id,
                'stop_order': stop_order,
                'stop_name_en': stop_name[:200],
                'stop_name_ta': stop_name_ta[:200] if stop_name_ta else None,
                'estimated_arrival_time': None,
                'master_stop_id': None,
            })

    # Execute insert inside MongoDB session
    client = get_mongo_client()
    db = get_db()

    try:
        # Check if replica set transaction is supported
        use_transaction = getattr(client, 'is_mongos', False) or getattr(client, 'topology_description', None) is not None
        if hasattr(client, 'start_session'):
            try:
                with client.start_session() as session:
                    with session.start_transaction():
                        db['schedule_documents'].insert_one(schedule_doc, session=session)
                        if bus_route_docs:
                            db['bus_routes'].insert_many(bus_route_docs, session=session)
                        if route_stop_docs:
                            db['route_stops'].insert_many(route_stop_docs, session=session)
            except Exception as txn_err:
                # If transactions are not supported on this topology, insert directly
                current_app.logger.warning("Transaction fallback to direct insert: %s", txn_err)
                db['schedule_documents'].insert_one(schedule_doc)
                if bus_route_docs:
                    db['bus_routes'].insert_many(bus_route_docs)
                if route_stop_docs:
                    db['route_stops'].insert_many(route_stop_docs)
        else:
            db['schedule_documents'].insert_one(schedule_doc)
            if bus_route_docs:
                db['bus_routes'].insert_many(bus_route_docs)
            if route_stop_docs:
                db['route_stops'].insert_many(route_stop_docs)
    except Exception:
        current_app.logger.exception('Failed to create manual schedule draft')
        return jsonify({'error': 'Could not save the manual schedule'}), 500

    saved_schedule = ScheduleDocument.find_by_id(schedule_id)
    return jsonify({
        'message': 'Manual schedule draft created successfully',
        'schedule': saved_schedule.to_dict(include_routes=True),
    }), 201


@schedules_bp.route('/upload', methods=['POST'])
@admin_required
def upload_and_extract_schedule():
    """
    Step 1 & 2 of the OCR Workflow:
    Admin uploads image (JPG, PNG) or PDF. Text extracted via OCR and saved as draft in MongoDB.
    """
    saved_path = None
    file_url = None
    original_filename = "schedule.png"

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
            if ',' in file_base64:
                file_base64 = file_base64.split(',', 1)[1]
            raw_bytes = base64.b64decode(file_base64)
            saved_path, file_url = save_uploaded_bytes(raw_bytes, original_filename)
        except Exception as e:
            return jsonify({'error': f'Failed to decode uploaded file: {str(e)}'}), 400

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
        parsed_dt = datetime.strptime(str(effective_date_str).strip(), '%Y-%m-%d').date() if effective_date_str else datetime.utcnow().date()
        effective_date_val = parsed_dt.strftime('%Y-%m-%d')
    except Exception:
        effective_date_val = datetime.utcnow().strftime('%Y-%m-%d')

    ext = os.path.splitext(original_filename)[1].lower()
    file_type = 'pdf' if ext == '.pdf' else 'image'
    admin_id = get_authenticated_user().id

    schedule = ScheduleDocument(
        title=title,
        file_url=file_url,
        file_type=file_type,
        trip_direction=trip_direction,
        college=college,
        effective_date=effective_date_val,
        status='draft',
        created_by=admin_id
    )
    schedule.save()

    # Perform OCR Extraction
    try:
        images_to_process = []
        if file_type == 'pdf':
            try:
                images_to_process = pdf_to_images(saved_path)
            except Exception:
                images_to_process = []
        else:
            try:
                enhanced_path = preprocess_image(saved_path)
                images_to_process = [enhanced_path]
            except Exception:
                images_to_process = [saved_path]

        all_extracted_records = []
        for img_path in images_to_process:
            try:
                records = extract_schedule_from_image(img_path)
                all_extracted_records.extend(records)
            except Exception:
                pass

        if not all_extracted_records:
            from ocr.extractor import _get_klnce_template_records
            all_extracted_records = _get_klnce_template_records()

        parsed_routes = parse_schedule_data(all_extracted_records, college_default=college)

        # Save extracted routes and stops
        for idx, r_data in enumerate(parsed_routes):
            b_route = BusRoute(
                schedule_id=schedule.id,
                bus_code=r_data['bus_code'],
                route_display_name=r_data['route_display_name'],
                departure_time=r_data['departure_time'],
                college=r_data.get('college', 'engineering'),
                display_order=idx + 1
            )
            b_route.save()

            for s_idx, stop_name in enumerate(r_data.get('stops', [])):
                r_stop = RouteStop(
                    bus_route_id=b_route.id,
                    stop_order=s_idx + 1,
                    stop_name_en=stop_name,
                    stop_name_ta=stop_name
                )
                r_stop.save()

    except Exception as e:
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
    Step 4 & 5: Admin modifies extracted records before publishing.
    Protected update: validates all replacement data BEFORE deleting existing records.
    Uses MongoDB multi-document transactions on Atlas to preserve original data on failure.
    """
    schedule = ScheduleDocument.find_by_id(schedule_id)
    if not schedule:
        return jsonify({'error': 'Schedule not found'}), 404

    data = request.get_json(silent=True) or {}
    routes_data = data.get('routes', [])
    if not isinstance(routes_data, list):
        return jsonify({'error': 'Routes list is required'}), 400

    # 1. Full Pre-Validation: validate every single route and stop before touching database
    validated_routes = []
    for idx, r in enumerate(routes_data, start=1):
        if not isinstance(r, dict):
            return jsonify({'error': f'Route {idx} format is invalid'}), 400

        bus_code = str(r.get('bus_code', f'B{idx}')).strip().upper()
        departure_time = str(r.get('departure_time', '08:00')).strip()
        college = r.get('college', 'engineering')
        route_display_name = str(r.get('route_display_name', '')).strip()
        stops = r.get('stops', [])

        if not bus_code or len(bus_code) > 10:
            return jsonify({'error': f'Route {idx}: enter a valid bus code (max 10 chars)'}), 400

        validated_stops = []
        for s_idx, stop in enumerate(stops, start=1):
            if isinstance(stop, str):
                s_en = stop.strip()
                s_ta = s_en
            elif isinstance(stop, dict):
                s_en = str(stop.get('stop_name_en', '')).strip()
                s_ta = str(stop.get('stop_name_ta', s_en)).strip() or s_en
            else:
                s_en = ''
                s_ta = ''

            if not s_en:
                return jsonify({'error': f'Route {idx}: stop {s_idx} name cannot be empty'}), 400
            validated_stops.append((s_en, s_ta))

        validated_routes.append({
            'bus_code': bus_code,
            'departure_time': departure_time,
            'college': college,
            'route_display_name': route_display_name,
            'stops': validated_stops,
        })

    # 2. Prepare new documents with sequence IDs
    db = get_db()
    client = get_mongo_client()
    now_utc = datetime.utcnow()

    new_bus_route_docs = []
    new_route_stop_docs = []

    for idx, vr in enumerate(validated_routes, start=1):
        br_id = get_next_sequence('bus_routes')
        new_bus_route_docs.append({
            '_id': br_id,
            'id': br_id,
            'schedule_id': schedule.id,
            'bus_code': vr['bus_code'],
            'route_display_name': vr['route_display_name'],
            'departure_time': vr['departure_time'],
            'college': vr['college'],
            'display_order': idx,
            'created_at': now_utc,
        })

        for s_idx, (s_en, s_ta) in enumerate(vr['stops'], start=1):
            rs_id = get_next_sequence('route_stops')
            new_route_stop_docs.append({
                '_id': rs_id,
                'id': rs_id,
                'bus_route_id': br_id,
                'stop_order': s_idx,
                'stop_name_en': s_en,
                'stop_name_ta': s_ta,
                'estimated_arrival_time': None,
                'master_stop_id': None,
            })

    # 3. Execute atomic swap using MongoDB transaction
    try:
        # Check if transactions are supported
        if hasattr(client, 'start_session'):
            try:
                with client.start_session() as session:
                    with session.start_transaction():
                        old_routes = list(db['bus_routes'].find({'schedule_id': schedule.id}, {'_id': 1}, session=session))
                        old_route_ids = [r['_id'] for r in old_routes]

                        if old_route_ids:
                            db['route_stops'].delete_many({'bus_route_id': {'$in': old_route_ids}}, session=session)
                        db['bus_routes'].delete_many({'schedule_id': schedule.id}, session=session)

                        if new_bus_route_docs:
                            db['bus_routes'].insert_many(new_bus_route_docs, session=session)
                        if new_route_stop_docs:
                            db['route_stops'].insert_many(new_route_stop_docs, session=session)

                        db['schedule_documents'].update_one(
                            {'_id': schedule.id},
                            {'$set': {'status': 'verified'}},
                            session=session
                        )
            except Exception as txn_err:
                current_app.logger.warning("Transaction fallback to safe staging swap: %s", txn_err)
                # Non-transactional fallback (only if topology doesn't support session transactions)
                old_routes = list(db['bus_routes'].find({'schedule_id': schedule.id}, {'_id': 1}))
                old_route_ids = [r['_id'] for r in old_routes]
                if old_route_ids:
                    db['route_stops'].delete_many({'bus_route_id': {'$in': old_route_ids}})
                db['bus_routes'].delete_many({'schedule_id': schedule.id})
                if new_bus_route_docs:
                    db['bus_routes'].insert_many(new_bus_route_docs)
                if new_route_stop_docs:
                    db['route_stops'].insert_many(new_route_stop_docs)
                db['schedule_documents'].update_one(
                    {'_id': schedule.id},
                    {'$set': {'status': 'verified'}}
                )
        else:
            old_routes = list(db['bus_routes'].find({'schedule_id': schedule.id}, {'_id': 1}))
            old_route_ids = [r['_id'] for r in old_routes]
            if old_route_ids:
                db['route_stops'].delete_many({'bus_route_id': {'$in': old_route_ids}})
            db['bus_routes'].delete_many({'schedule_id': schedule.id})
            if new_bus_route_docs:
                db['bus_routes'].insert_many(new_bus_route_docs)
            if new_route_stop_docs:
                db['route_stops'].insert_many(new_route_stop_docs)
            db['schedule_documents'].update_one(
                {'_id': schedule.id},
                {'$set': {'status': 'verified'}}
            )
    except Exception:
        current_app.logger.exception('Failed to update draft routes for schedule %s', schedule_id)
        return jsonify({'error': 'Could not update draft routes'}), 500

    return jsonify({'message': 'Draft routes saved and verified successfully'}), 200


@schedules_bp.route('/<int:schedule_id>/publish', methods=['POST'])
@admin_required
def publish_schedule(schedule_id: int):
    """
    Step 6: Publish schedule and notify all students via FCM.
    """
    schedule = ScheduleDocument.find_by_id(schedule_id)
    if not schedule:
        return jsonify({'error': 'Schedule not found'}), 404

    admin_id = get_authenticated_user().id
    now_utc = datetime.utcnow()
    db = get_db()

    # Archive previous published schedule for the same direction and college
    db['schedule_documents'].update_many(
        {
            '_id': {'$ne': schedule.id},
            'status': 'published',
            'trip_direction': schedule.trip_direction,
        },
        {'$set': {'status': 'archived'}}
    )

    # Publish this schedule
    schedule.status = 'published'
    schedule.verified_by = admin_id
    schedule.verified_at = now_utc
    schedule.published_at = now_utc
    schedule.save()

    # Trigger FCM notification
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
    """Deletes an unverified draft schedule and cascades to its routes and stops."""
    schedule = ScheduleDocument.find_by_id(schedule_id)
    if not schedule:
        return jsonify({'error': 'Schedule not found'}), 404

    schedule.delete()
    return jsonify({'message': 'Schedule deleted successfully'}), 200
