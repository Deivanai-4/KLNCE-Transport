"""
services/excel_student_service.py — Excel template generation, validation, preview, and safe import.
Supports .xlsx and .csv files with robust Indian mobile number validation and safe duplicate detection.
"""

import csv
import io
import re
from datetime import datetime
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

from models.database import get_db
from models.student import Student


TEMPLATE_COLUMNS = [
    ("Register Number", "register_number", True),
    ("Student Name", "name", True),
    ("Department", "department", True),
    ("Year", "year", True),
    ("Section", "section", False),
    ("Student Mobile Number", "student_mobile", True),
    ("Parent Mobile Number", "parent_mobile", False),
    ("Route Name", "route_name", True),
    ("Regular Bus Number", "bus_number", True),
    ("Boarding Stop", "boarding_stop", True),
]

SAMPLE_ROW = [
    "SAMPLE9106001",
    "Sample Student (DO NOT IMPORT)",
    "CSE",
    "II",
    "A",
    "9876543210",
    "9876543211",
    "Route A - Periyar",
    "S1",
    "Teppakulam",
]


def normalize_indian_mobile(raw_phone) -> tuple[bool, str, str]:
    """
    Validate and clean an Indian mobile number.
    Returns: (is_valid: bool, cleaned_number: str, error_message: str)
    Rules:
      - Strips spaces, dashes, dots, parentheses
      - Strips leading +91, 91, or 0
      - Must be exactly 10 digits starting with 6, 7, 8, or 9
    """
    if raw_phone is None:
        return False, "", "Mobile number is empty"

    # Convert to string and strip formatting characters
    phone_str = str(raw_phone).strip()
    # Remove all non-digit characters except leading '+'
    cleaned = re.sub(r"[\s\-\(\)\.]+", "", phone_str)

    if cleaned.startswith("+91"):
        cleaned = cleaned[3:]
    elif cleaned.startswith("0") and len(cleaned) == 11:
        cleaned = cleaned[1:]
    elif cleaned.startswith("91") and len(cleaned) == 12:
        cleaned = cleaned[2:]

    if not cleaned:
        return False, "", "Mobile number is empty"

    if not cleaned.isdigit():
        return False, cleaned, f"Mobile number '{phone_str}' contains non-numeric characters"

    if len(cleaned) != 10:
        return (
            False,
            cleaned,
            f"Mobile number '{phone_str}' has {len(cleaned)} digits (must be exactly 10 digits)",
        )

    if cleaned[0] not in {"6", "7", "8", "9"}:
        return (
            False,
            cleaned,
            f"Mobile number '{phone_str}' must start with 6, 7, 8, or 9",
        )

    return True, cleaned, ""


def is_sample_row(reg_no: str, name: str) -> bool:
    """Identify if row is the sample template row that should not be imported."""
    r = str(reg_no or "").upper()
    n = str(name or "").upper()
    return (
        "SAMPLE" in r
        or "SAMPLE" in n
        or "DO NOT IMPORT" in n
        or "EXAMPLE" in r
        or "EXAMPLE" in n
    )


def generate_student_template(file_format: str = "xlsx") -> tuple[bytes, str, str]:
    """
    Generate downloadable student registration template with header and sample row.
    Returns: (file_bytes, content_type, filename)
    """
    if file_format.lower() == "csv":
        output = io.StringIO()
        writer = csv.writer(output)
        writer.writerow([col[0] for col in TEMPLATE_COLUMNS])
        writer.writerow(SAMPLE_ROW)
        csv_bytes = output.getvalue().encode("utf-8-sig")
        return (
            csv_bytes,
            "text/csv; charset=utf-8",
            "klnce_student_template.csv",
        )

    # XLSX format via openpyxl
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Student Registration"

    # Styling constants
    header_fill = PatternFill(
        start_color="1A365D", end_color="1A365D", fill_type="solid"
    )
    header_font = Font(name="Calibri", size=11, bold=True, color="FFFFFF")
    sample_fill = PatternFill(
        start_color="F1F5F9", end_color="F1F5F9", fill_type="solid"
    )
    sample_font = Font(name="Calibri", size=10, italic=True, color="64748B")
    thin_border = Border(
        left=Side(style="thin", color="E2E8F0"),
        right=Side(style="thin", color="E2E8F0"),
        top=Side(style="thin", color="E2E8F0"),
        bottom=Side(style="thin", color="E2E8F0"),
    )
    center_align = Alignment(horizontal="center", vertical="center")
    left_align = Alignment(horizontal="left", vertical="center")

    # Header Row
    headers = [col[0] for col in TEMPLATE_COLUMNS]
    ws.append(headers)
    ws.row_dimensions[1].height = 28

    for col_idx, cell in enumerate(ws[1], start=1):
        cell.fill = header_fill
        cell.font = header_font
        cell.alignment = center_align
        cell.border = thin_border

    # Sample Row
    ws.append(SAMPLE_ROW)
    ws.row_dimensions[2].height = 22
    for cell in ws[2]:
        cell.fill = sample_fill
        cell.font = sample_font
        cell.alignment = left_align
        cell.border = thin_border

    # Adjust column widths automatically
    for col in ws.columns:
        max_len = max(len(str(cell.value or "")) for cell in col)
        col_letter = get_column_letter(col[0].column)
        ws.column_dimensions[col_letter].width = max(max_len + 4, 14)

    output = io.BytesIO()
    wb.save(output)
    xlsx_bytes = output.getvalue()
    return (
        xlsx_bytes,
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "klnce_student_template.xlsx",
    )


def _match_column_index(headers: list[str]) -> dict[str, int]:
    """Map expected field keys to column indices using fuzzy matching."""
    mapping = {}
    patterns = {
        "register_number": [r"reg", r"roll", r"register"],
        "name": [r"student\s*name", r"name"],
        "department": [r"dept", r"department", r"branch"],
        "year": [r"year", r"yr"],
        "section": [r"sec", r"section"],
        "student_mobile": [r"student\s*mobile", r"student\s*phone", r"mobile", r"phone"],
        "parent_mobile": [r"parent\s*mobile", r"parent\s*phone", r"parent"],
        "route_name": [r"route", r"route\s*name"],
        "bus_number": [r"bus", r"bus\s*no", r"bus\s*number", r"regular\s*bus"],
        "boarding_stop": [r"stop", r"boarding", r"boarding\s*stop", r"pickup"],
    }

    clean_headers = [str(h).strip().lower() for h in headers]

    for key, regexes in patterns.items():
        found = False
        for pattern in regexes:
            for idx, h in enumerate(clean_headers):
                if re.search(pattern, h) and idx not in mapping.values():
                    mapping[key] = idx
                    found = True
                    break
            if found:
                break

    return mapping


def parse_and_validate_file(file_storage) -> dict:
    """
    Parse an uploaded .xlsx or .csv file and perform deep validation without importing.
    Returns preview summary with row-by-row status and detailed errors.
    """
    filename = getattr(file_storage, "filename", "") or ""
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""

    if ext not in {"xlsx", "csv"}:
        raise ValueError("Unsupported file format. Please upload an .xlsx or .csv file.")

    raw_rows = []
    if ext == "xlsx":
        wb = openpyxl.load_workbook(file_storage, data_only=True)
        ws = wb.active
        for row in ws.iter_rows(values_only=True):
            raw_rows.append(list(row))
    else:  # csv
        stream = io.StringIO(file_storage.read().decode("utf-8-sig", errors="replace"))
        reader = csv.reader(stream)
        for row in reader:
            raw_rows.append(row)

    if not raw_rows:
        raise ValueError("The uploaded file is empty.")

    # 1. Detect Header Row
    header_idx = 0
    headers = [str(c or "").strip() for c in raw_rows[0]]
    col_map = _match_column_index(headers)

    # Check if essential columns are present
    missing_required_headers = []
    for title, key, required in TEMPLATE_COLUMNS:
        if required and key not in col_map:
            missing_required_headers.append(title)

    if missing_required_headers:
        raise ValueError(
            f"Missing required columns in header: {', '.join(missing_required_headers)}. "
            "Please download and use the official template."
        )

    # 2. Extract and Validate Data Rows
    db = get_db()
    seen_reg_nos = {}  # reg_no -> row_number
    records = []
    valid_count = 0
    invalid_count = 0
    sample_count = 0
    duplicate_in_file_count = 0
    existing_in_db_count = 0
    missing_fields_count = 0
    invalid_mobile_count = 0

    all_reg_nos = []
    data_rows = raw_rows[1:]

    for row_idx, row in enumerate(data_rows, start=2):
        # Skip completely empty rows
        if not any(c is not None and str(c).strip() != "" for c in row):
            continue

        def get_val(key: str) -> str:
            idx = col_map.get(key)
            if idx is not None and idx < len(row):
                val = row[idx]
                return str(val).strip() if val is not None else ""
            return ""

        reg_no = get_val("register_number").upper()
        name = get_val("name")
        dept = get_val("department").upper()
        year = get_val("year").upper()
        section = get_val("section").upper()
        student_mobile_raw = get_val("student_mobile")
        parent_mobile_raw = get_val("parent_mobile")
        route_name = get_val("route_name")
        bus_number = get_val("bus_number").upper()
        boarding_stop = get_val("boarding_stop")

        # 3. Check for Sample Row
        if is_sample_row(reg_no, name):
            sample_count += 1
            records.append({
                "row_number": row_idx,
                "register_number": reg_no,
                "name": name,
                "department": dept,
                "year": year,
                "section": section,
                "student_mobile": student_mobile_raw,
                "parent_mobile": parent_mobile_raw,
                "route_name": route_name,
                "bus_number": bus_number,
                "boarding_stop": boarding_stop,
                "status": "sample",
                "exists_in_db": False,
                "errors": ["Sample template row detected — automatically excluded from import."],
            })
            continue

        row_errors = []

        # 4. Mandatory Fields Check
        if not reg_no:
            row_errors.append("Missing Register Number")
            missing_fields_count += 1
        if not name:
            row_errors.append("Missing Student Name")
            missing_fields_count += 1
        if not dept:
            row_errors.append("Missing Department")
            missing_fields_count += 1
        if not year:
            row_errors.append("Missing Year")
            missing_fields_count += 1
        if not route_name:
            row_errors.append("Missing Route Name")
            missing_fields_count += 1
        if not bus_number:
            row_errors.append("Missing Regular Bus Number")
            missing_fields_count += 1
        if not boarding_stop:
            row_errors.append("Missing Boarding Stop")
            missing_fields_count += 1

        # 5. Mobile Number Validation
        clean_student_mobile = student_mobile_raw
        if not student_mobile_raw:
            row_errors.append("Missing Student Mobile Number")
            missing_fields_count += 1
        else:
            ok, clean_m, err_msg = normalize_indian_mobile(student_mobile_raw)
            if not ok:
                row_errors.append(f"Student Mobile: {err_msg}")
                invalid_mobile_count += 1
            else:
                clean_student_mobile = clean_m

        clean_parent_mobile = parent_mobile_raw
        if parent_mobile_raw:
            ok_p, clean_p, err_p = normalize_indian_mobile(parent_mobile_raw)
            if not ok_p:
                row_errors.append(f"Parent Mobile: {err_p}")
                invalid_mobile_count += 1
            else:
                clean_parent_mobile = clean_p

        # 6. Duplicate in file detection
        if reg_no:
            if reg_no in seen_reg_nos:
                row_errors.append(
                    f"Duplicate Register Number '{reg_no}' (first seen on row {seen_reg_nos[reg_no]})"
                )
                duplicate_in_file_count += 1
            else:
                seen_reg_nos[reg_no] = row_idx
                all_reg_nos.append(reg_no)

        records.append({
            "row_number": row_idx,
            "register_number": reg_no,
            "name": name,
            "department": dept,
            "year": year,
            "section": section,
            "student_mobile": clean_student_mobile,
            "parent_mobile": clean_parent_mobile,
            "route_name": route_name,
            "bus_number": bus_number,
            "boarding_stop": boarding_stop,
            "status": "invalid" if row_errors else "valid",
            "exists_in_db": False,
            "errors": row_errors,
        })

    # 7. Check Existing Records in MongoDB Atlas
    if all_reg_nos:
        existing_docs = list(
            db["students"].find({"register_number": {"$in": all_reg_nos}}, {"register_number": 1})
        )
        existing_set = {d["register_number"] for d in existing_docs}

        for rec in records:
            if rec["register_number"] in existing_set:
                rec["exists_in_db"] = True
                existing_in_db_count += 1
                if rec["status"] == "valid":
                    rec["status"] = "exists"

    # Count final valid and invalid
    for rec in records:
        if rec["status"] in {"valid", "exists"}:
            valid_count += 1
        elif rec["status"] == "invalid":
            invalid_count += 1

    return {
        "total_rows": len(records),
        "valid_count": valid_count,
        "invalid_count": invalid_count,
        "sample_count": sample_count,
        "existing_in_db_count": existing_in_db_count,
        "duplicate_in_file_count": duplicate_in_file_count,
        "missing_fields_count": missing_fields_count,
        "invalid_mobile_count": invalid_mobile_count,
        "records": records,
    }


def import_students(student_records: list[dict], update_existing: bool = False) -> dict:
    """
    Save validated student records to MongoDB Atlas upon administrator confirmation.
    Safely updates existing students when update_existing=True, preventing duplicate documents.
    """
    db = get_db()
    col = db["students"]

    imported_count = 0
    updated_count = 0
    failed_count = 0
    errors = []

    for item in student_records:
        reg_no = str(item.get("register_number", "")).strip().upper()
        if not reg_no or is_sample_row(reg_no, item.get("name", "")):
            continue

        existing = Student.find_by_register_number(reg_no)

        if existing:
            if not update_existing:
                failed_count += 1
                errors.append({
                    "row_number": item.get("row_number"),
                    "register_number": reg_no,
                    "reason": f"Student with Register Number '{reg_no}' already exists in database.",
                })
                continue

            # Safe update existing student
            existing.name = str(item.get("name", existing.name)).strip()
            existing.department = str(item.get("department", existing.department)).strip().upper()
            existing.year = str(item.get("year", existing.year)).strip().upper()
            existing.section = str(item.get("section", existing.section)).strip().upper()
            existing.student_mobile = str(item.get("student_mobile", existing.student_mobile)).strip()
            existing.parent_mobile = str(item.get("parent_mobile", existing.parent_mobile)).strip()
            existing.route_name = str(item.get("route_name", existing.route_name)).strip()
            existing.bus_number = str(item.get("bus_number", existing.bus_number)).strip().upper()
            existing.boarding_stop = str(item.get("boarding_stop", existing.boarding_stop)).strip()
            existing.is_transport_active = True
            existing.save()
            updated_count += 1
        else:
            # Insert new student record
            student = Student(
                register_number=reg_no,
                name=str(item.get("name", "")).strip(),
                department=str(item.get("department", "")).strip().upper(),
                year=str(item.get("year", "")).strip().upper(),
                section=str(item.get("section", "")).strip().upper(),
                student_mobile=str(item.get("student_mobile", "")).strip(),
                parent_mobile=str(item.get("parent_mobile", "")).strip(),
                route_name=str(item.get("route_name", "")).strip(),
                bus_number=str(item.get("bus_number", "")).strip().upper(),
                boarding_stop=str(item.get("boarding_stop", "")).strip(),
                is_transport_active=True,
            )
            student.save()
            imported_count += 1

    return {
        "imported_count": imported_count,
        "updated_count": updated_count,
        "failed_count": failed_count,
        "errors": errors,
    }
