# -*- coding: utf-8 -*-
"""
routes/announcements.py — Endpoints for broadcast announcements, schedule-change
alerts, recipient targeting, student notification views, and SIM-based SMS linking.

PyMongo / MongoDB Atlas backed.
"""

from datetime import datetime, timezone
import re
from typing import Any, Dict, List, Optional, Set, Tuple

from flask import Blueprint, current_app, jsonify, request
from pymongo.errors import PyMongoError

from models.announcement import (
    Announcement,
    ALL_CATEGORIES,
    ALL_PRIORITIES,
    ALL_STATUSES,
    CATEGORY_GENERAL,
    CATEGORY_EMERGENCY,
    PRIORITY_NORMAL,
    PRIORITY_EMERGENCY,
    STATUS_DRAFT,
    STATUS_PUBLISHED,
    STATUS_ARCHIVED,
    TARGET_ALL_ACTIVE,
    TARGET_ROUTE,
    TARGET_BUS,
    TARGET_SELECTED,
)
from models.database import get_db
from models.daily_schedule import DailySchedule
from models.sms_campaign import (
    SmsCampaign,
    STATUS_PENDING_CONFIRMATION,
    STATUS_DRAFT as SMS_STATUS_DRAFT,
)
from models.user import User
from flask_jwt_extended import verify_jwt_in_request, get_jwt_identity
from routes.auth import admin_required, get_authenticated_user, jwt_auth_required
from services.schedule_change_detector import detect_schedule_changes

announcements_bp = Blueprint("announcements_bp", __name__, url_prefix="/api/announcements")


def _get_optional_user() -> Optional[User]:
    """Extract authenticated user from JWT if present, else None."""
    try:
        verify_jwt_in_request(optional=True)
        email = get_jwt_identity()
        if email:
            return User.find_by_email(email)
    except Exception:
        pass
    return None


# ── Helper functions ─────────────────────────────────────────────────────────

def _normalize_indian_mobile(raw_phone: str) -> Optional[str]:
    """Clean and validate standard 10-digit Indian mobile number."""
    if not raw_phone:
        return None
    cleaned = re.sub(r"[^\d]", "", str(raw_phone))
    if len(cleaned) == 12 and cleaned.startswith("91"):
        cleaned = cleaned[2:]
    elif len(cleaned) == 11 and cleaned.startswith("0"):
        cleaned = cleaned[1:]
    if len(cleaned) == 10 and cleaned[0] in "6789":
        return f"+91{cleaned}"
    return None


def _mask_mobile(phone: str) -> str:
    """Mask mobile number for privacy (e.g. +91 98*** **210)."""
    if not phone or len(phone) < 10:
        return "—"
    digits = re.sub(r"[^\d]", "", phone)
    if len(digits) >= 10:
        last10 = digits[-10:]
        return f"+91 {last10[:2]}*** **{last10[-3:]}"
    return "—"


def _calculate_sms_segments(text: str) -> Dict[str, Any]:
    """Calculate SMS character length and segments based on GSM-7 / Unicode."""
    is_unicode = any(ord(c) > 127 for c in text)
    length = len(text)
    if not is_unicode:
        segments = 1 if length <= 160 else (length + 152) // 153
        max_single = 160
    else:
        segments = 1 if length <= 70 else (length + 66) // 67
        max_single = 70
    return {
        "length": length,
        "is_unicode": is_unicode,
        "segments_per_message": max(1, segments),
        "max_single_segment": max_single,
    }


def _resolve_target_students(
    target_type: str,
    target_route: Optional[str] = None,
    target_bus: Optional[str] = None,
    target_student_ids: Optional[List[int]] = None,
) -> Tuple[List[Dict[str, Any]], int, int]:
    """
    Query students matching targeting rules from MongoDB.
    Returns: (students_list, duplicate_count, invalid_count)
    """
    db = get_db()
    query: Dict[str, Any] = {"is_transport_active": True}

    if target_type == TARGET_ROUTE and target_route:
        query["route_name"] = target_route.strip()
    elif target_type == TARGET_BUS and target_bus:
        query["bus_number"] = target_bus.strip().upper()
    elif target_type == TARGET_SELECTED and target_student_ids:
        query["_id"] = {"$in": [int(i) for i in target_student_ids]}

    docs = list(db["students"].find(query))

    seen_phones: Set[str] = set()
    valid_students: List[Dict[str, Any]] = []
    duplicate_count = 0
    invalid_count = 0

    for s in docs:
        phone = _normalize_indian_mobile(s.get("student_mobile", ""))
        if not phone:
            invalid_count += 1
            continue
        if phone in seen_phones:
            duplicate_count += 1
            continue
        seen_phones.add(phone)
        valid_students.append(s)

    return valid_students, duplicate_count, invalid_count


# ── Announcement Endpoints ───────────────────────────────────────────────────

@announcements_bp.route("", methods=["GET"])
@admin_required
def list_announcements():
    """
    Admin lists announcements with optional filters.
    Query params:
      - status: 'draft' | 'published' | 'archived' | 'all'
      - category: category string
      - priority: priority string
      - search: string matching title or message
    """
    status = request.args.get("status", "all")
    category = request.args.get("category")
    priority = request.args.get("priority")
    search = request.args.get("search", "").strip().lower()

    announcements = Announcement.find_all(status=status, category=category, priority=priority)

    if search:
        announcements = [
            a for a in announcements
            if search in a.title.lower() or search in a.message.lower() or search in (a.target_route or "").lower()
        ]

    # Include linked SMS campaign status if present
    db = get_db()
    sms_ids = [a.sms_campaign_id for a in announcements if a.sms_campaign_id]
    sms_map: Dict[int, str] = {}
    if sms_ids:
        c_docs = list(db["sms_campaigns"].find({"_id": {"$in": sms_ids}}, {"_id": 1, "status": 1}))
        sms_map = {c["_id"]: c.get("status", "unknown") for c in c_docs}

    result = []
    for a in announcements:
        d = a.to_dict()
        if a.sms_campaign_id and a.sms_campaign_id in sms_map:
            d["sms_status"] = sms_map[a.sms_campaign_id]
        result.append(d)

    return jsonify({"announcements": result, "total": len(result)}), 200


@announcements_bp.route("", methods=["POST"])
@admin_required
def create_announcement():
    """
    Admin creates an announcement (draft or published).
    Body:
      {
        "title": str,
        "message": str,
        "category": str,
        "priority": 'low' | 'normal' | 'high' | 'emergency',
        "status": 'draft' | 'published',
        "target_type": 'all_active' | 'route' | 'bus' | 'selected',
        "target_route": str | null,
        "target_bus": str | null,
        "target_student_ids": list[int] | null,
        "channels": ['in_app'] | ['in_app', 'sms'] | ['sms'],
        "send_sms": bool (shortcut for adding 'sms' to channels)
      }
    """
    data = request.get_json(silent=True) or {}
    title = (data.get("title") or "").strip()
    message = (data.get("message") or "").strip()
    category = data.get("category", CATEGORY_GENERAL)
    priority = data.get("priority", PRIORITY_NORMAL)
    status = data.get("status", STATUS_DRAFT)
    target_type = data.get("target_type", TARGET_ALL_ACTIVE)
    target_route = data.get("target_route")
    target_bus = data.get("target_bus")
    target_student_ids = data.get("target_student_ids") or []
    channels = data.get("channels") or ["in_app"]

    if data.get("send_sms") and "sms" not in channels:
        channels.append("sms")

    if not title:
        return jsonify({"error": "Title is required"}), 400
    if len(title) > 200:
        return jsonify({"error": "Title must be 200 characters or fewer"}), 400
    if not message:
        return jsonify({"error": "Message body is required"}), 400
    if category not in ALL_CATEGORIES:
        return jsonify({"error": f"Invalid category. Must be one of: {ALL_CATEGORIES}"}), 400
    if priority not in ALL_PRIORITIES:
        return jsonify({"error": f"Invalid priority. Must be one of: {ALL_PRIORITIES}"}), 400
    if status not in ALL_STATUSES:
        return jsonify({"error": f"Invalid status. Must be one of: {ALL_STATUSES}"}), 400

    admin = get_authenticated_user()

    # Resolve target students
    students, duplicate_count, invalid_count = _resolve_target_students(
        target_type, target_route, target_bus, target_student_ids
    )
    recipient_count = len(students)

    now = datetime.now(timezone.utc)
    published_at = now if status == STATUS_PUBLISHED else None

    announcement = Announcement(
        title=title,
        message=message,
        category=category,
        priority=priority,
        status=status,
        target_type=target_type,
        target_route=target_route,
        target_bus=target_bus,
        target_student_ids=target_student_ids,
        channels=channels,
        created_by=admin.id,
        created_by_name=admin.name or "Admin",
        created_at=now,
        published_at=published_at,
        updated_at=now,
        recipient_count=recipient_count,
        in_app_count=recipient_count if ("in_app" in channels and status == STATUS_PUBLISHED) else 0,
        schedule_change_metadata=data.get("schedule_change_metadata"),
    )

    announcement_id = announcement.save()

    # If published and SMS channel is requested, create linked SmsCampaign in pending_confirmation
    sms_campaign_id = None
    if status == STATUS_PUBLISHED and "sms" in channels and students:
        recipients_list = []
        for s in students:
            clean_phone = _normalize_indian_mobile(s.get("student_mobile", ""))
            if clean_phone:
                recipients_list.append({
                    "recipient_id": s.get("_id"),
                    "name": s.get("name", "Student"),
                    "mobile": clean_phone,
                    "mobile_number": clean_phone,
                    "student_mobile": clean_phone,
                    "masked_mobile": _mask_mobile(clean_phone),
                    "route_name": s.get("route_name", ""),
                    "bus_number": s.get("bus_number", ""),
                    "boarding_stop": s.get("boarding_stop", ""),
                    "message": message,
                    "status": "pending",
                })

        seg_info = _calculate_sms_segments(message)
        total_sms = len(recipients_list) * seg_info["segments_per_message"]

        campaign = SmsCampaign(
            title=f"Announcement: {title[:40]}",
            message=message,
            target_type=target_type,
            route_name=target_route,
            bus_number=target_bus,
            status=STATUS_PENDING_CONFIRMATION,
            allow_duplicates=False,
            duplicates_prevented_count=duplicate_count,
            segments_per_message=seg_info["segments_per_message"],
            total_sms_count=total_sms,
            valid_count=len(recipients_list),
            invalid_count=invalid_count,
            duplicate_count=duplicate_count,
            recipients=recipients_list,
            created_by=admin.id,
        )
        sms_campaign_id = campaign.save()
        announcement.sms_campaign_id = sms_campaign_id
        announcement.save()

    return jsonify({
        "message": f"Announcement {'published' if status == STATUS_PUBLISHED else 'saved as draft'}",
        "announcement": announcement.to_dict(),
        "sms_campaign_id": sms_campaign_id,
        "recipient_count": recipient_count,
        "duplicates_prevented": duplicate_count,
    }), 201


@announcements_bp.route("/<int:announcement_id>", methods=["GET"])
@admin_required
def get_announcement(announcement_id: int):
    """Get single announcement detail."""
    announcement = Announcement.find_by_id(announcement_id)
    if not announcement:
        return jsonify({"error": "Announcement not found"}), 404

    result = announcement.to_dict()

    # Attach SMS campaign status if available
    if announcement.sms_campaign_id:
        db = get_db()
        camp = db["sms_campaigns"].find_one({"_id": announcement.sms_campaign_id})
        if camp:
            result["sms_campaign"] = {
                "id": camp["_id"],
                "status": camp.get("status"),
                "total_recipients": camp.get("total_recipients", 0),
                "submitted_count": camp.get("submitted_count", 0),
                "delivery_confirmed_count": camp.get("delivery_confirmed_count", 0),
                "failed_count": camp.get("failed_count", 0),
            }

    return jsonify({"announcement": result}), 200


@announcements_bp.route("/<int:announcement_id>", methods=["PUT"])
@admin_required
def update_announcement(announcement_id: int):
    """
    Edit an announcement (drafts can be edited completely; published announcements
    can have message text or priority updated).
    """
    announcement = Announcement.find_by_id(announcement_id)
    if not announcement:
        return jsonify({"error": "Announcement not found"}), 404

    data = request.get_json(silent=True) or {}

    if "title" in data:
        title = str(data["title"]).strip()
        if not title:
            return jsonify({"error": "Title cannot be empty"}), 400
        announcement.title = title[:200]

    if "message" in data:
        msg = str(data["message"]).strip()
        if not msg:
            return jsonify({"error": "Message cannot be empty"}), 400
        announcement.message = msg

    if "category" in data and data["category"] in ALL_CATEGORIES:
        announcement.category = data["category"]

    if "priority" in data and data["priority"] in ALL_PRIORITIES:
        announcement.priority = data["priority"]

    if announcement.status == STATUS_DRAFT:
        if "target_type" in data:
            announcement.target_type = data["target_type"]
        if "target_route" in data:
            announcement.target_route = data["target_route"]
        if "target_bus" in data:
            announcement.target_bus = data["target_bus"]
        if "target_student_ids" in data:
            announcement.target_student_ids = data["target_student_ids"]
        if "channels" in data:
            announcement.channels = data["channels"]

        # Recompute recipient count for draft
        students, _, _ = _resolve_target_students(
            announcement.target_type,
            announcement.target_route,
            announcement.target_bus,
            announcement.target_student_ids,
        )
        announcement.recipient_count = len(students)

    announcement.save()
    return jsonify({
        "message": "Announcement updated successfully",
        "announcement": announcement.to_dict(),
    }), 200


@announcements_bp.route("/<int:announcement_id>", methods=["DELETE"])
@admin_required
def delete_announcement(announcement_id: int):
    """Delete an announcement (drafts or archived notices)."""
    announcement = Announcement.find_by_id(announcement_id)
    if not announcement:
        return jsonify({"error": "Announcement not found"}), 404

    announcement.delete()
    return jsonify({"message": f"Announcement {announcement_id} deleted successfully"}), 200


@announcements_bp.route("/<int:announcement_id>/publish", methods=["POST"])
@admin_required
def publish_announcement(announcement_id: int):
    """
    Publish an existing draft announcement.
    Body (optional):
      {
        "send_sms": bool
      }
    """
    announcement = Announcement.find_by_id(announcement_id)
    if not announcement:
        return jsonify({"error": "Announcement not found"}), 404

    data = request.get_json(silent=True) or {}
    send_sms = data.get("send_sms", "sms" in announcement.channels)

    admin = get_authenticated_user()

    # Resolve target students
    students, duplicate_count, invalid_count = _resolve_target_students(
        announcement.target_type,
        announcement.target_route,
        announcement.target_bus,
        announcement.target_student_ids,
    )
    announcement.recipient_count = len(students)
    announcement.in_app_count = len(students) if "in_app" in announcement.channels else 0
    announcement.status = STATUS_PUBLISHED
    announcement.published_at = datetime.now(timezone.utc)

    # Optional SMS campaign linking
    sms_campaign_id = None
    if send_sms and students:
        recipients_list = []
        for s in students:
            clean_phone = _normalize_indian_mobile(s.get("student_mobile", ""))
            if clean_phone:
                recipients_list.append({
                    "recipient_id": s.get("_id"),
                    "name": s.get("name", "Student"),
                    "mobile": clean_phone,
                    "mobile_number": clean_phone,
                    "student_mobile": clean_phone,
                    "masked_mobile": _mask_mobile(clean_phone),
                    "route_name": s.get("route_name", ""),
                    "bus_number": s.get("bus_number", ""),
                    "boarding_stop": s.get("boarding_stop", ""),
                    "message": announcement.message,
                    "status": "pending",
                })

        seg_info = _calculate_sms_segments(announcement.message)
        total_sms = len(recipients_list) * seg_info["segments_per_message"]

        campaign = SmsCampaign(
            title=f"Announcement: {announcement.title[:40]}",
            message=announcement.message,
            target_type=announcement.target_type,
            route_name=announcement.target_route,
            bus_number=announcement.target_bus,
            status=STATUS_PENDING_CONFIRMATION,
            allow_duplicates=False,
            duplicates_prevented_count=duplicate_count,
            segments_per_message=seg_info["segments_per_message"],
            total_sms_count=total_sms,
            valid_count=len(recipients_list),
            invalid_count=invalid_count,
            duplicate_count=duplicate_count,
            recipients=recipients_list,
            created_by=admin.id,
        )
        sms_campaign_id = campaign.save()
        announcement.sms_campaign_id = sms_campaign_id
        if "sms" not in announcement.channels:
            announcement.channels.append("sms")

    announcement.save()

    return jsonify({
        "message": "Announcement published successfully",
        "announcement": announcement.to_dict(),
        "sms_campaign_id": sms_campaign_id,
        "recipient_count": len(students),
    }), 200


@announcements_bp.route("/recipient-preview", methods=["POST", "GET"])
@admin_required
def preview_recipients():
    """
    Preview recipient count and privacy-masked sample records before publishing.
    Accepts GET query params or POST JSON:
      target_type: 'all_active' | 'route' | 'bus' | 'selected'
      target_route: str
      target_bus: str
      target_student_ids: list[int]
    """
    if request.method == "POST":
        data = request.get_json(silent=True) or {}
    else:
        data = request.args

    target_type = data.get("target_type", TARGET_ALL_ACTIVE)
    target_route = data.get("target_route")
    target_bus = data.get("target_bus")
    raw_ids = data.get("target_student_ids")

    target_student_ids = []
    if isinstance(raw_ids, list):
        target_student_ids = [int(i) for i in raw_ids if i is not None]
    elif isinstance(raw_ids, str) and raw_ids.strip():
        target_student_ids = [int(i.strip()) for i in raw_ids.split(",") if i.strip()]

    students, duplicate_count, invalid_count = _resolve_target_students(
        target_type, target_route, target_bus, target_student_ids
    )

    sample = []
    for s in students[:10]:
        phone = s.get("student_mobile", "")
        sample.append({
            "id": s.get("_id"),
            "name": s.get("name", "Student"),
            "register_number": s.get("register_number", "—"),
            "route_name": s.get("route_name", "—"),
            "bus_number": s.get("bus_number", "—"),
            "masked_mobile": _mask_mobile(phone),
        })

    return jsonify({
        "total_recipients": len(students),
        "duplicates_prevented": duplicate_count,
        "invalid_mobile_count": invalid_count,
        "sample_recipients": sample,
        "target_type": target_type,
    }), 200


@announcements_bp.route("/detect-schedule-changes", methods=["POST"])
@admin_required
def detect_changes_endpoint():
    """
    Detect differences between a daily schedule's current state and new state.
    Body:
      {
        "schedule_id": int,
        "new_data": dict (updated schedule data with date, session, buses)
      }
    """
    data = request.get_json(silent=True) or {}
    schedule_id = data.get("schedule_id")
    new_data = data.get("new_data") or {}

    if not schedule_id:
        return jsonify({"error": "schedule_id is required"}), 400

    schedule = DailySchedule.find_by_id(int(schedule_id))
    if not schedule:
        return jsonify({"error": "Schedule not found"}), 404

    diff_result = detect_schedule_changes(schedule.to_dict(), new_data)

    return jsonify({
        "schedule_id": schedule_id,
        "has_changes": diff_result["has_changes"],
        "change_bullets": diff_result["change_bullets"],
        "affected_buses": diff_result["affected_buses"],
        "affected_routes": diff_result["affected_routes"],
        "affected_students_count": diff_result["affected_students_count"],
        "affected_student_ids": diff_result["affected_student_ids"],
        "suggested_title": diff_result["suggested_title"],
        "suggested_message": diff_result["suggested_message"],
    }), 200


# ── Student Announcement Endpoints ──────────────────────────────────────────

@announcements_bp.route("/student", methods=["GET"])
def get_student_announcements():
    """
    Student views published announcements relevant to their transport profile:
      - All active notices
      - Notices for their route
      - Notices for their bus
      - Selected notices targeting their student record
    Emergency notices are pinned to the top.
    """
    user = _get_optional_user()
    student_id = None
    route_name = None
    bus_number = None

    if user:
        # Check if user is linked to a student record
        db = get_db()
        student_doc = db["students"].find_one({
            "$or": [
                {"email": user.email},
                {"student_mobile": user.phone},
                {"_id": user.id},
            ]
        })
        if student_doc:
            student_id = student_doc.get("_id")
            route_name = student_doc.get("route_name")
            bus_number = student_doc.get("bus_number")

    limit = min(int(request.args.get("limit", 50)), 100)
    announcements = Announcement.find_for_student(
        route_name=route_name,
        bus_number=bus_number,
        student_id=student_id,
        limit=limit,
    )

    current_uid = user.id if user else None
    result = [a.to_dict(current_user_id=current_uid) for a in announcements]

    unread_count = sum(1 for a in result if not a["is_read"])

    return jsonify({
        "announcements": result,
        "total": len(result),
        "unread_count": unread_count,
    }), 200


@announcements_bp.route("/<int:announcement_id>/read", methods=["POST"])
@jwt_auth_required
def mark_announcement_read(announcement_id: int):
    """Student marks an announcement as read."""
    user = get_authenticated_user()
    if not user:
        return jsonify({"error": "Authentication required"}), 401

    announcement = Announcement.find_by_id(announcement_id)
    if not announcement:
        return jsonify({"error": "Announcement not found"}), 404

    announcement.mark_as_read(user.id)
    return jsonify({"message": "Announcement marked as read", "id": announcement_id}), 200


# ── Notification History Endpoint ───────────────────────────────────────────

@announcements_bp.route("/history", methods=["GET"])
@admin_required
def notification_history():
    """
    Returns full announcement and delivery history for administrator inspection:
      - Title, Category, Priority
      - Target audience description
      - Publication timestamp
      - In-app reach count and read count
      - Linked SMS campaign status, submitted count, and failed count
    """
    db = get_db()
    limit = min(int(request.args.get("limit", 50)), 100)

    # Published and archived announcements
    docs = list(
        db["announcements"]
        .find({"status": {"$in": [STATUS_PUBLISHED, STATUS_ARCHIVED]}})
        .sort("published_at", -1)
        .limit(limit)
    )

    sms_ids = [d.get("sms_campaign_id") for d in docs if d.get("sms_campaign_id")]
    sms_campaign_map = {}
    if sms_ids:
        c_docs = list(db["sms_campaigns"].find({"_id": {"$in": sms_ids}}))
        sms_campaign_map = {c["_id"]: c for c in c_docs}

    history = []
    for d in docs:
        ann = Announcement.from_mongo(d)
        item = ann.to_dict()
        camp = sms_campaign_map.get(ann.sms_campaign_id)
        if camp:
            item["sms_details"] = {
                "campaign_id": camp["_id"],
                "status": camp.get("status"),
                "total_recipients": camp.get("total_recipients", 0),
                "submitted_count": camp.get("submitted_count", 0),
                "delivery_confirmed_count": camp.get("delivery_confirmed_count", 0),
                "failed_count": camp.get("failed_count", 0),
                "cancelled_count": camp.get("cancelled_count", 0),
            }
        else:
            item["sms_details"] = None

        history.append(item)

    return jsonify({"history": history, "total": len(history)}), 200
