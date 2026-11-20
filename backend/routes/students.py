"""
routes/students.py — Endpoints for Excel student registration, route allocation,
and student transport management.
PyMongo / MongoDB Atlas backed.
"""

from flask import Blueprint, request, jsonify, make_response, current_app
from pymongo.errors import PyMongoError

from models.database import get_db
from models.student import Student
from routes.auth import admin_required
from services.excel_student_service import (
    generate_student_template,
    parse_and_validate_file,
    import_students,
    normalize_indian_mobile,
)

students_bp = Blueprint("students_bp", __name__, url_prefix="/api/students")


# ── 1. Excel Template Download ──────────────────────────────────────────────

@students_bp.route("/template", methods=["GET"])
@admin_required
def download_template():
    """
    Download Excel/CSV template for student registration with sample row.
    Query param: format=xlsx (default) or format=csv
    """
    file_format = request.args.get("format", "xlsx").strip().lower()
    try:
        content_bytes, content_type, filename = generate_student_template(file_format)
        response = make_response(content_bytes)
        response.headers["Content-Type"] = content_type
        response.headers["Content-Disposition"] = f'attachment; filename="{filename}"'
        return response
    except Exception:
        current_app.logger.exception("Failed to generate student template")
        return jsonify({"error": "Could not generate student registration template"}), 500


# ── 2. Excel Upload & Preview ───────────────────────────────────────────────

@students_bp.route("/upload-preview", methods=["POST"])
@admin_required
def upload_preview():
    """
    Validate uploaded .xlsx or .csv student file and return validation preview.
    Does NOT import into MongoDB — preview only.
    """
    if "file" not in request.files:
        return jsonify({"error": "No file uploaded. Please select an Excel or CSV file."}), 400

    file_obj = request.files["file"]
    if not file_obj.filename:
        return jsonify({"error": "Empty filename"}), 400

    try:
        preview_data = parse_and_validate_file(file_obj)
        return jsonify(preview_data), 200
    except ValueError as val_err:
        return jsonify({"error": str(val_err)}), 400
    except Exception:
        current_app.logger.exception("Failed to process Excel upload preview")
        return jsonify({"error": "Could not parse file. Ensure it is a valid .xlsx or .csv file."}), 500


# ── 3. Import Confirmation ──────────────────────────────────────────────────

@students_bp.route("/import", methods=["POST"])
@admin_required
def confirm_import():
    """
    Import validated student records into MongoDB Atlas after admin confirmation.
    Payload:
      {
        "students": [ ... validated student dicts ... ],
        "update_existing": bool (default False)
      }
    """
    data = request.get_json(silent=True) or {}
    students_list = data.get("students", [])
    update_existing = bool(data.get("update_existing", False))

    if not isinstance(students_list, list) or not students_list:
        return jsonify({"error": "No student records provided for import"}), 400

    try:
        result = import_students(students_list, update_existing=update_existing)
        return jsonify({
            "message": f"Successfully processed {result['imported_count'] + result['updated_count']} students",
            **result,
        }), 200
    except PyMongoError:
        current_app.logger.exception("Database error during student import")
        return jsonify({"error": "Database error while saving students"}), 500


# ── 4. Student Management: List & Search ────────────────────────────────────

@students_bp.route("", methods=["GET"])
@admin_required
def list_students():
    """
    Search and filter registered students with pagination.
    Query params:
      - page: int (1-based, default 1)
      - per_page: int (default 20, max 100)
      - q: search term (matches register_number, name, boarding_stop)
      - department: str
      - year: str
      - route_name: str
      - bus_number: str
      - is_transport_active: bool
    """
    try:
        page = max(1, int(request.args.get("page", 1)))
        per_page = min(max(1, int(request.args.get("per_page", 20))), 100)
    except (ValueError, TypeError):
        page = 1
        per_page = 20

    q = request.args.get("q", "").strip() or None
    dept = request.args.get("department", "").strip() or None
    year = request.args.get("year", "").strip() or None
    route = request.args.get("route_name", "").strip() or None
    bus = request.args.get("bus_number", "").strip() or None
    active_param = request.args.get("is_transport_active")
    is_active = None
    if active_param is not None:
        is_active = active_param.strip().lower() in {"true", "1"}

    try:
        skip = (page - 1) * per_page
        students, total = Student.list_students(
            q=q,
            department=dept,
            year=year,
            route_name=route,
            bus_number=bus,
            is_transport_active=is_active,
            skip=skip,
            limit=per_page,
        )

        return jsonify({
            "total": total,
            "page": page,
            "per_page": per_page,
            "students": [s.to_dict() for s in students],
        }), 200
    except PyMongoError:
        current_app.logger.exception("Failed to list students")
        return jsonify({"error": "Could not load students"}), 500


# ── 5. Manual Add Student ───────────────────────────────────────────────────

@students_bp.route("", methods=["POST"])
@admin_required
def add_student():
    """Manually add an individual student for corrections or new registrations."""
    data = request.get_json(silent=True) or {}
    if not isinstance(data, dict):
        return jsonify({"error": "Request payload must be a JSON object"}), 400

    reg_no = str(data.get("register_number", "")).strip().upper()
    name = str(data.get("name", "")).strip()
    dept = str(data.get("department", "")).strip().upper()
    year = str(data.get("year", "")).strip().upper()
    section = str(data.get("section", "")).strip().upper()
    raw_student_mobile = str(data.get("student_mobile", "")).strip()
    raw_parent_mobile = str(data.get("parent_mobile", "")).strip()
    route_name = str(data.get("route_name", "")).strip()
    bus_number = str(data.get("bus_number", "")).strip().upper()
    boarding_stop = str(data.get("boarding_stop", "")).strip()

    if not reg_no:
        return jsonify({"error": "Register Number is required"}), 400
    if not name:
        return jsonify({"error": "Student Name is required"}), 400
    if not dept:
        return jsonify({"error": "Department is required"}), 400
    if not year:
        return jsonify({"error": "Year is required"}), 400
    if not route_name:
        return jsonify({"error": "Route Name is required"}), 400
    if not bus_number:
        return jsonify({"error": "Regular Bus Number is required"}), 400
    if not boarding_stop:
        return jsonify({"error": "Boarding Stop is required"}), 400

    # Validate Mobile
    ok, clean_m, err_m = normalize_indian_mobile(raw_student_mobile)
    if not ok:
        return jsonify({"error": f"Student Mobile: {err_m}"}), 400

    clean_p = ""
    if raw_parent_mobile:
        ok_p, clean_p, err_p = normalize_indian_mobile(raw_parent_mobile)
        if not ok_p:
            return jsonify({"error": f"Parent Mobile: {err_p}"}), 400

    try:
        existing = Student.find_by_register_number(reg_no)
        if existing:
            return jsonify({
                "error": f"Student with Register Number '{reg_no}' already exists.",
                "existing_id": existing.id,
            }), 409

        student = Student(
            register_number=reg_no,
            name=name,
            department=dept,
            year=year,
            section=section,
            student_mobile=clean_m,
            parent_mobile=clean_p,
            route_name=route_name,
            bus_number=bus_number,
            boarding_stop=boarding_stop,
            is_transport_active=True,
        )
        student.save()

        return jsonify({
            "message": "Student registered successfully",
            "student": student.to_dict(),
        }), 201
    except PyMongoError:
        current_app.logger.exception("Failed to add student")
        return jsonify({"error": "Could not save student"}), 500


# ── 6. Student Detail, Update & Status Toggle ────────────────────────────────

@students_bp.route("/<int:student_id>", methods=["GET"])
@admin_required
def get_student_detail(student_id: int):
    """Fetch individual student information."""
    try:
        student = Student.find_by_id(student_id)
        if not student:
            return jsonify({"error": "Student not found"}), 404
        return jsonify({"student": student.to_dict()}), 200
    except PyMongoError:
        current_app.logger.exception("Failed to get student detail %s", student_id)
        return jsonify({"error": "Could not load student detail"}), 500


@students_bp.route("/<int:student_id>", methods=["PUT"])
@admin_required
def update_student(student_id: int):
    """Edit student details including mobile numbers and route allocation."""
    data = request.get_json(silent=True) or {}
    if not isinstance(data, dict):
        return jsonify({"error": "Request payload must be a JSON object"}), 400

    try:
        student = Student.find_by_id(student_id)
        if not student:
            return jsonify({"error": "Student not found"}), 404

        # Validate register number collision if changed
        if "register_number" in data:
            new_reg = str(data["register_number"]).strip().upper()
            if new_reg and new_reg != student.register_number:
                collision = Student.find_by_register_number(new_reg)
                if collision and collision.id != student.id:
                    return jsonify({"error": f"Register Number '{new_reg}' is already in use"}), 409
                student.register_number = new_reg

        if "name" in data:
            student.name = str(data["name"]).strip()
        if "department" in data:
            student.department = str(data["department"]).strip().upper()
        if "year" in data:
            student.year = str(data["year"]).strip().upper()
        if "section" in data:
            student.section = str(data["section"]).strip().upper()

        if "student_mobile" in data:
            ok, clean_m, err_m = normalize_indian_mobile(data["student_mobile"])
            if not ok:
                return jsonify({"error": f"Student Mobile: {err_m}"}), 400
            student.student_mobile = clean_m

        if "parent_mobile" in data:
            raw_p = str(data["parent_mobile"]).strip()
            if raw_p:
                ok_p, clean_p, err_p = normalize_indian_mobile(raw_p)
                if not ok_p:
                    return jsonify({"error": f"Parent Mobile: {err_p}"}), 400
                student.parent_mobile = clean_p
            else:
                student.parent_mobile = ""

        # Route Allocation updates
        if "route_name" in data:
            student.route_name = str(data["route_name"]).strip()
        if "bus_number" in data:
            student.bus_number = str(data["bus_number"]).strip().upper()
        if "boarding_stop" in data:
            student.boarding_stop = str(data["boarding_stop"]).strip()
        if "is_transport_active" in data:
            student.is_transport_active = bool(data["is_transport_active"])

        student.save()
        return jsonify({
            "message": "Student details updated successfully",
            "student": student.to_dict(),
        }), 200
    except PyMongoError:
        current_app.logger.exception("Failed to update student %s", student_id)
        return jsonify({"error": "Could not update student"}), 500


@students_bp.route("/<int:student_id>/status", methods=["PATCH", "PUT"])
@admin_required
def toggle_transport_status(student_id: int):
    """Activate or deactivate transport registration for a student."""
    data = request.get_json(silent=True) or {}
    try:
        student = Student.find_by_id(student_id)
        if not student:
            return jsonify({"error": "Student not found"}), 404

        if "is_transport_active" in data:
            student.is_transport_active = bool(data["is_transport_active"])
        else:
            student.is_transport_active = not student.is_transport_active

        student.save()
        status_text = "activated" if student.is_transport_active else "deactivated"
        return jsonify({
            "message": f"Transport registration {status_text} successfully",
            "student": student.to_dict(),
        }), 200
    except PyMongoError:
        current_app.logger.exception("Failed to toggle student transport status %s", student_id)
        return jsonify({"error": "Could not update transport status"}), 500


# ── 7. Route Allocation Summaries ───────────────────────────────────────────

@students_bp.route("/route-allocations", methods=["GET"])
@admin_required
def get_route_allocations():
    """
    Get aggregated route-wise and bus-wise student counts.
    Allows admin to inspect load per route and per bus.
    """
    try:
        summary = Student.get_route_allocations()
        return jsonify(summary), 200
    except PyMongoError:
        current_app.logger.exception("Failed to get route allocations")
        return jsonify({"error": "Could not load route allocations"}), 500


# ── 8. SMS Preparation (Secure Phone Retrieval) ─────────────────────────────

@students_bp.route("/sms-recipients", methods=["GET"])
@admin_required
def get_sms_recipients():
    """
    Secure backend endpoint to query student mobile numbers for future SMS broadcasts.
    Query params:
      - target: 'all_active' | 'route' | 'bus' | 'selected'
      - route_name: string (if target='route')
      - bus_number: string (if target='bus')
      - student_ids: comma-separated list of IDs (if target='selected')
    DOES NOT send SMS. Admin access only.
    """
    target = request.args.get("target", "all_active").strip().lower()
    db = get_db()
    query = {"is_transport_active": True}

    if target == "route":
        route_name = request.args.get("route_name", "").strip()
        if not route_name:
            return jsonify({"error": "route_name parameter is required for route targeting"}), 400
        query["route_name"] = route_name
    elif target == "bus":
        bus_number = request.args.get("bus_number", "").strip().upper()
        if not bus_number:
            return jsonify({"error": "bus_number parameter is required for bus targeting"}), 400
        query["bus_number"] = bus_number
    elif target == "selected":
        raw_ids = request.args.get("student_ids", "").strip()
        if not raw_ids:
            return jsonify({"error": "student_ids parameter is required for selected targeting"}), 400
        try:
            ids = [int(i.strip()) for i in raw_ids.split(",") if i.strip()]
            query["_id"] = {"$in": ids}
        except ValueError:
            return jsonify({"error": "Invalid student_ids list"}), 400

    try:
        docs = list(
            db["students"].find(
                query,
                {
                    "_id": 1,
                    "register_number": 1,
                    "name": 1,
                    "student_mobile": 1,
                    "parent_mobile": 1,
                    "route_name": 1,
                    "bus_number": 1,
                },
            )
        )

        recipients = [
            {
                "student_id": d["_id"],
                "register_number": d.get("register_number", ""),
                "name": d.get("name", ""),
                "student_mobile": d.get("student_mobile", ""),
                "parent_mobile": d.get("parent_mobile", ""),
                "route_name": d.get("route_name", ""),
                "bus_number": d.get("bus_number", ""),
            }
            for d in docs
            if d.get("student_mobile")
        ]

        return jsonify({
            "target": target,
            "count": len(recipients),
            "recipients": recipients,
        }), 200
    except PyMongoError:
        current_app.logger.exception("Failed to query SMS recipients")
        return jsonify({"error": "Could not retrieve SMS recipients"}), 500
