# -*- coding: utf-8 -*-
"""
routes/sms.py — Endpoints for Android Phone SIM-based SMS Integration.
Supports recipient retrieval, validation, duplicate detection & prevention,
segment calculation, campaign creation, dispatch logging, and audit history.
Admin-only access; does not expose student contact details unnecessarily.
PyMongo / MongoDB Atlas backed.
"""

import re
from flask import Blueprint, request, jsonify, current_app, g
from flask_jwt_extended import get_jwt_identity
from pymongo.errors import PyMongoError

from models.database import get_db
from models.sms_campaign import (
    SmsCampaign,
    STATUS_DRAFT,
    STATUS_SENDING,
    RECIPIENT_PENDING,
    mask_mobile,
)
from routes.auth import admin_required
from services.excel_student_service import normalize_indian_mobile

sms_bp = Blueprint("sms_bp", __name__, url_prefix="/api/sms")


def mask_mobile_number(mobile: str) -> str:
    """Mask mobile number so full digits are not exposed: e.g. +91 98*** **210."""
    return mask_mobile(mobile)


def calculate_sms_segments(text: str) -> dict:
    """
    Calculate SMS encoding (GSM-7 vs Unicode) and segment count.
    Rules:
      - GSM-7: 1-160 chars = 1 segment; >160 chars = 153 chars/segment.
      - Unicode (e.g. Tamil or emojis): 1-70 chars = 1 segment; >70 chars = 67 chars/segment.
    """
    if not text:
        return {
            "encoding": "GSM-7",
            "is_unicode": False,
            "char_count": 0,
            "segments_per_message": 0,
            "remaining_in_segment": 160,
        }

    gsm_basic = (
        "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞ\x1bÆæßÉ"
        " !\"#¤%&'()*+,-./0123456789:;<=>?"
        "¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§"
        "¿abcdefghijklmnopqrstuvwxyzäöñüà"
        "^{}\\[~]|€"
    )
    is_unicode = any(c not in gsm_basic for c in text)
    length = len(text)

    if is_unicode:
        encoding = "Unicode (UCS-2)"
        if length <= 70:
            segments = 1
            remaining = 70 - length
        else:
            segments = (length + 66) // 67
            remaining = (segments * 67) - length
    else:
        encoding = "GSM-7"
        if length <= 160:
            segments = 1
            remaining = 160 - length
        else:
            segments = (length + 152) // 153
            remaining = (segments * 153) - length

    return {
        "encoding": encoding,
        "is_unicode": is_unicode,
        "char_count": length,
        "segments_per_message": segments,
        "remaining_in_segment": remaining,
    }


# ── 1. Calculate Segments Endpoint ──────────────────────────────────────────

@sms_bp.route("/calculate-segments", methods=["POST"])
@admin_required
def get_segment_calculation():
    """Calculate SMS character and segment count for a given text."""
    data = request.get_json(silent=True) or {}
    text = data.get("message", "")
    return jsonify(calculate_sms_segments(text)), 200


# ── 2. Secure Recipient Query & Analytics Preview ────────────────────────────

@sms_bp.route("/recipients", methods=["GET"])
@admin_required
def get_recipients():
    """
    Query eligible student recipients for an SMS broadcast with full validation preview:
      - Recipient category & Route / Bus selection
      - Total selected students
      - Valid mobile numbers
      - Invalid mobile numbers (with reasons)
      - Duplicate mobile numbers (grouped)
      - Masked mobile numbers for privacy protection
      - Duplicate prevention logic (unless allow_duplicates=true)

    Query params:
      - target: 'all_active' | 'route' | 'bus' | 'selected'
      - route_name: string (if target='route')
      - bus_number: string (if target='bus')
      - student_ids: comma-separated list of IDs (if target='selected')
      - allow_duplicates: 'true' | 'false' (default 'false')
    """
    target = request.args.get("target", "all_active").strip().lower()
    allow_duplicates = request.args.get("allow_duplicates", "false").strip().lower() == "true"
    db = get_db()
    query = {"is_transport_active": True}

    route_name = None
    bus_number = None

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
            return jsonify({"error": "Invalid student_ids parameter"}), 400

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
                    "boarding_stop": 1,
                },
            ).sort("register_number", 1)
        )

        # Formulate human-readable category
        if target == "route":
            category_label = f"Route: {route_name}"
        elif target == "bus":
            category_label = f"Bus: {bus_number}"
        elif target == "selected":
            category_label = f"Individual Students ({len(docs)})"
        else:
            category_label = "All Active Transport Students"

        valid_recipients = []
        invalid_recipients = []
        seen_phone_map = {}  # clean_phone -> list of student items

        for d in docs:
            raw_mob = d.get("student_mobile")
            is_valid, clean_mob, err_msg = normalize_indian_mobile(raw_mob)
            masked = mask_mobile_number(clean_mob if is_valid else (raw_mob or ""))

            if is_valid:
                item = {
                    "student_id": d["_id"],
                    "register_number": d.get("register_number", ""),
                    "name": d.get("name", ""),
                    "mobile_number": clean_mob,
                    "masked_mobile": masked,
                    "parent_mobile": d.get("parent_mobile", ""),
                    "route_name": d.get("route_name", ""),
                    "bus_number": d.get("bus_number", ""),
                    "boarding_stop": d.get("boarding_stop", ""),
                    "is_duplicate": False,
                }
                if clean_mob not in seen_phone_map:
                    seen_phone_map[clean_mob] = [item]
                else:
                    item["is_duplicate"] = True
                    seen_phone_map[clean_mob].append(item)
                valid_recipients.append(item)
            else:
                invalid_recipients.append({
                    "student_id": d["_id"],
                    "register_number": d.get("register_number", ""),
                    "name": d.get("name", ""),
                    "raw_mobile": str(raw_mob or ""),
                    "masked_mobile": masked,
                    "route_name": d.get("route_name", ""),
                    "bus_number": d.get("bus_number", ""),
                    "boarding_stop": d.get("boarding_stop", ""),
                    "error": err_msg or "Invalid mobile number",
                })

        duplicate_groups = []
        unique_recipients = []
        duplicate_count = 0

        for phone, group in seen_phone_map.items():
            unique_recipients.append(group[0])
            if len(group) > 1:
                duplicate_count += len(group) - 1
                duplicate_groups.append({
                    "clean_mobile": phone,
                    "masked_mobile": mask_mobile_number(phone),
                    "count": len(group),
                    "students": [
                        {
                            "student_id": s["student_id"],
                            "register_number": s["register_number"],
                            "name": s["name"],
                        }
                        for s in group
                    ],
                })

        # By default, prevent duplicate messages to the same number unless explicitly approved
        effective_recipients = valid_recipients if allow_duplicates else unique_recipients
        duplicates_prevented = duplicate_count if not allow_duplicates else 0

        return jsonify({
            "target": target,
            "recipient_category": category_label,
            "route_name": route_name,
            "bus_number": bus_number,
            "total_selected_students": len(docs),
            "valid_count": len(valid_recipients),
            "invalid_count": len(invalid_recipients),
            "duplicate_count": duplicate_count,
            "unique_valid_count": len(unique_recipients),
            "effective_recipient_count": len(effective_recipients),
            "allow_duplicates": allow_duplicates,
            "duplicates_prevented": duplicates_prevented,
            "valid_recipients": valid_recipients,
            "invalid_recipients": invalid_recipients,
            "duplicate_groups": duplicate_groups,
            "count": len(effective_recipients),
            "recipients": effective_recipients,
        }), 200
    except PyMongoError:
        current_app.logger.exception("Failed to query SMS recipients")
        return jsonify({"error": "Could not retrieve recipients from database"}), 500


# ── 3. Create SMS Campaign ──────────────────────────────────────────────────

@sms_bp.route("/campaigns", methods=["POST"])
@admin_required
def create_campaign():
    """
    Create a new SMS broadcast campaign session.
    Payload:
      {
        "title": "Evening Bus Schedule Update",
        "message": "Dear student, Bus S1 will depart at 4:30 PM today from Gate 2.",
        "target_type": "all_active" | "route" | "bus" | "selected" | "test",
        "route_name": "Route 4 - Tirunagar",
        "bus_number": "S1",
        "selected_student_ids": [1, 2, 3],
        "test_phone": "9876543210",
        "allow_duplicates": false (default: false; prevents duplicate messages to the same number),
        "sender_device": { "model": "Samsung SM-A525F", "carrier": "Airtel", "sim_slot": 0 },
        "delivery_method": "direct_sim" | "system_intent"
      }
    """
    data = request.get_json(silent=True) or {}
    message = (data.get("message") or "").strip()
    if not message:
        return jsonify({"error": "SMS message content cannot be empty"}), 400

    title = (data.get("title") or "KLNCE Transport Alert").strip()
    target_type = (data.get("target_type") or "all_active").strip().lower()
    route_name = data.get("route_name")
    bus_number = data.get("bus_number")
    delivery_method = data.get("delivery_method", "direct_sim")
    sender_device = data.get("sender_device", {})
    allow_duplicates = bool(data.get("allow_duplicates", False))

    current_user = getattr(g, "current_user", None)
    admin_id_int = current_user.id if current_user else None

    recipients_list = []
    invalid_count = 0
    duplicate_count = 0
    duplicates_prevented_count = 0

    # Calculate SMS segments for message
    seg_info = calculate_sms_segments(message)
    segments_per_message = seg_info["segments_per_message"]

    # Case A: Test SMS to a single number
    if target_type == "test":
        raw_phone = data.get("test_phone", "").strip()
        is_valid, clean_phone, err_msg = normalize_indian_mobile(raw_phone)
        if not is_valid:
            return jsonify({"error": f"Invalid test mobile number '{raw_phone}': {err_msg}"}), 400

        recipients_list.append({
            "student_id": 0,
            "register_number": "TEST-ADMIN",
            "name": "Administrator Test Device",
            "mobile_number": clean_phone,
            "masked_mobile": mask_mobile_number(clean_phone),
            "status": RECIPIENT_PENDING,
        })
    else:
        # Case B: Real student recipients
        db = get_db()
        query = {"is_transport_active": True}

        if target_type == "route":
            if not route_name:
                return jsonify({"error": "route_name is required when targeting by route"}), 400
            query["route_name"] = route_name
        elif target_type == "bus":
            if not bus_number:
                return jsonify({"error": "bus_number is required when targeting by bus"}), 400
            query["bus_number"] = bus_number.strip().upper()
        elif target_type == "selected":
            raw_ids = data.get("selected_student_ids") or []
            if not raw_ids:
                return jsonify({"error": "selected_student_ids is required when targeting selected students"}), 400
            query["_id"] = {"$in": raw_ids}

        try:
            docs = list(
                db["students"].find(
                    query,
                    {
                        "_id": 1,
                        "register_number": 1,
                        "name": 1,
                        "student_mobile": 1,
                        "route_name": 1,
                        "bus_number": 1,
                    },
                ).sort("register_number", 1)
            )

            seen_phones = set()
            for d in docs:
                raw_mob = d.get("student_mobile")
                is_valid, clean_mob, _ = normalize_indian_mobile(raw_mob)
                if not is_valid:
                    invalid_count += 1
                    continue

                if clean_mob in seen_phones:
                    duplicate_count += 1
                    if not allow_duplicates:
                        # Prevent duplicate message to the same number unless approved
                        duplicates_prevented_count += 1
                        continue

                seen_phones.add(clean_mob)
                recipients_list.append({
                    "student_id": d["_id"],
                    "register_number": d.get("register_number", ""),
                    "name": d.get("name", ""),
                    "mobile_number": clean_mob,
                    "masked_mobile": mask_mobile_number(clean_mob),
                    "status": RECIPIENT_PENDING,
                })
        except PyMongoError:
            current_app.logger.exception("Failed to query student recipients for SMS campaign")
            return jsonify({"error": "Database error retrieving recipients"}), 500

    if not recipients_list:
        return jsonify({"error": "No valid active students with mobile numbers found for the selected target."}), 400

    total_sms_count = len(recipients_list) * segments_per_message

    try:
        campaign = SmsCampaign(
            title=title,
            message=message,
            target_type=target_type,
            recipients=recipients_list,
            target_filter={
                "route_name": route_name,
                "bus_number": bus_number,
                "selected_count": len(recipients_list),
            },
            route_name=route_name,
            bus_number=bus_number,
            sender_device=sender_device,
            delivery_method=delivery_method,
            status=STATUS_DRAFT,
            allow_duplicates=allow_duplicates,
            duplicates_prevented_count=duplicates_prevented_count,
            segments_per_message=segments_per_message,
            total_sms_count=total_sms_count,
            valid_count=len(recipients_list),
            invalid_count=invalid_count,
            duplicate_count=duplicate_count,
            created_by=admin_id_int,
        )
        campaign_id = campaign.save()

        return jsonify({
            "message": "SMS campaign created successfully",
            "campaign": campaign.to_dict(include_recipients=True),
        }), 201
    except Exception:
        current_app.logger.exception("Failed to create SMS campaign")
        return jsonify({"error": "Could not create SMS campaign"}), 500


# ── 4. Update Campaign Dispatch Progress ────────────────────────────────────

@sms_bp.route("/campaigns/<int:campaign_id>/status", methods=["PUT"])
@admin_required
def update_campaign_status(campaign_id: int):
    """
    Update dispatch progress from the administrator's Android device as messages are sent.
    Payload:
      {
        "status": "sending" | "completed" | "partially_failed" | "cancelled",
        "sender_device": { "model": "...", "carrier": "...", "sim_slot": 0 },
        "recipient_updates": [
          {
            "student_id": 1,
            "mobile_number": "9876543210",
            "status": "sent_to_sms_service" | "failed",
            "error_message": null | "NO_SERVICE" | "GENERIC_FAILURE",
            "dispatched_at": "2026-11-20T13:30:00Z"
          }
        ]
      }
    """
    data = request.get_json(silent=True) or {}
    status = data.get("status")
    sender_device = data.get("sender_device")
    recipient_updates = data.get("recipient_updates")

    try:
        success = SmsCampaign.update_progress(
            campaign_id=campaign_id,
            status=status,
            sender_device=sender_device,
            recipient_updates=recipient_updates,
        )
        if not success:
            return jsonify({"error": f"Campaign {campaign_id} not found"}), 404

        updated = SmsCampaign.find_by_id(campaign_id)
        return jsonify({
            "message": "Campaign status updated",
            "campaign": updated.to_dict(include_recipients=True) if updated else {},
        }), 200
    except PyMongoError:
        current_app.logger.exception("Failed to update SMS campaign status")
        return jsonify({"error": "Could not update campaign progress"}), 500


# ── 5. List SMS Campaign History ────────────────────────────────────────────

@sms_bp.route("/campaigns", methods=["GET"])
@admin_required
def list_campaigns():
    """List recent SMS campaigns with summaries and statistics."""
    status = request.args.get("status")
    target_type = request.args.get("target_type")
    try:
        limit = min(int(request.args.get("limit", 50)), 100)
        skip = max(int(request.args.get("skip", 0)), 0)
    except ValueError:
        limit = 50
        skip = 0

    try:
        campaigns = SmsCampaign.list_campaigns(
            status=status,
            target_type=target_type,
            limit=limit,
            skip=skip,
            include_recipients=False,
        )
        return jsonify({
            "count": len(campaigns),
            "campaigns": campaigns,
        }), 200
    except PyMongoError:
        current_app.logger.exception("Failed to list SMS campaigns")
        return jsonify({"error": "Could not list campaigns"}), 500


# ── 6. Get Campaign Details with Recipients & Filter ────────────────────────

@sms_bp.route("/campaigns/<int:campaign_id>", methods=["GET"])
@admin_required
def get_campaign(campaign_id: int):
    """
    Get full details of a specific SMS campaign including per-recipient status.
    Supports filtering recipients by status ('sent_to_sms_service', 'failed', 'pending')
    and searching by name or register number.
    """
    status_filter = request.args.get("status", "").strip().lower()
    search_query = request.args.get("search", "").strip().lower()

    try:
        campaign = SmsCampaign.find_by_id(campaign_id)
        if not campaign:
            return jsonify({"error": f"Campaign {campaign_id} not found"}), 404

        campaign_data = campaign.to_dict(include_recipients=True)

        # Apply filtering if requested
        if status_filter or search_query:
            filtered = []
            for r in campaign_data["recipients"]:
                if status_filter and r.get("status") != status_filter:
                    continue
                if search_query:
                    reg = str(r.get("register_number", "")).lower()
                    name = str(r.get("name", "")).lower()
                    if search_query not in reg and search_query not in name:
                        continue
                filtered.append(r)
            campaign_data["recipients"] = filtered
            campaign_data["filtered_count"] = len(filtered)

        return jsonify(campaign_data), 200
    except PyMongoError:
        current_app.logger.exception("Failed to get SMS campaign details")
        return jsonify({"error": "Could not retrieve campaign details"}), 500


# ── 7. Retry Failed Campaign Recipients ─────────────────────────────────────

@sms_bp.route("/campaigns/<int:campaign_id>/retry-failed", methods=["POST"])
@admin_required
def retry_failed_campaign(campaign_id: int):
    """
    Reset failed/cancelled recipients in a campaign back to pending for retry dispatch.
    Optional payload: {"recipient_ids": [1, 2, ...]}
    Previously successful recipients (submitted/delivered) are strictly NEVER modified or re-sent.
    """
    data = request.get_json(silent=True) or {}
    recipient_ids = data.get("recipient_ids")
    try:
        updated = SmsCampaign.retry_failed(campaign_id, recipient_ids=recipient_ids)
        if not updated:
            return jsonify({"error": f"Campaign {campaign_id} not found"}), 404
        return jsonify({
            "message": "Failed recipients reset to pending for retry.",
            "campaign": updated.to_dict(include_recipients=True),
        }), 200
    except Exception:
        current_app.logger.exception("Failed to retry campaign")
        return jsonify({"error": "Could not reset failed recipients"}), 500


# ── 8. Cancel Pending Recipients ────────────────────────────────────────────

@sms_bp.route("/campaigns/<int:campaign_id>/cancel-pending", methods=["POST"])
@admin_required
def cancel_pending_campaign(campaign_id: int):
    """Cancel all pending/sending recipients in an in-flight campaign."""
    try:
        updated = SmsCampaign.cancel_pending(campaign_id)
        if not updated:
            return jsonify({"error": f"Campaign {campaign_id} not found"}), 404
        return jsonify({
            "message": "Pending recipients cancelled successfully.",
            "campaign": updated.to_dict(include_recipients=True),
        }), 200
    except Exception:
        current_app.logger.exception("Failed to cancel pending campaign recipients")
        return jsonify({"error": "Could not cancel pending recipients"}), 500


# ── 9. Pause & Resume Campaign ──────────────────────────────────────────────

@sms_bp.route("/campaigns/<int:campaign_id>/pause", methods=["POST"])
@admin_required
def pause_campaign(campaign_id: int):
    """Set campaign status to paused."""
    try:
        success = SmsCampaign.update_progress(campaign_id=campaign_id, status="paused")
        if not success:
            return jsonify({"error": f"Campaign {campaign_id} not found"}), 404
        updated = SmsCampaign.find_by_id(campaign_id)
        return jsonify({
            "message": "Campaign paused.",
            "campaign": updated.to_dict(include_recipients=True) if updated else {},
        }), 200
    except Exception:
        current_app.logger.exception("Failed to pause campaign")
        return jsonify({"error": "Could not pause campaign"}), 500


@sms_bp.route("/campaigns/<int:campaign_id>/resume", methods=["POST"])
@admin_required
def resume_campaign(campaign_id: int):
    """Set campaign status from paused back to sending."""
    try:
        success = SmsCampaign.update_progress(campaign_id=campaign_id, status="sending")
        if not success:
            return jsonify({"error": f"Campaign {campaign_id} not found"}), 404
        updated = SmsCampaign.find_by_id(campaign_id)
        return jsonify({
            "message": "Campaign resumed.",
            "campaign": updated.to_dict(include_recipients=True) if updated else {},
        }), 200
    except Exception:
        current_app.logger.exception("Failed to resume campaign")
        return jsonify({"error": "Could not resume campaign"}), 500
