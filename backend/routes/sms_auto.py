# -*- coding: utf-8 -*-
"""
routes/sms_auto.py — API Endpoints for Automatic Morning (6:30 AM) and Afternoon (2:00 PM) SMS Scheduling.
Enforces:
  - Phone SIM sending only (Render backend never sends SMS directly).
  - Explicit enablement required by administrator.
  - Confirmation Mode as default.
  - Strict publication requirement (no unpublished or draft schedules).
  - Duplicate campaign prevention using {date}_{session}_v{version} keys.
  - Emergency disable safeguard.
PyMongo / MongoDB Atlas backed.
"""

from datetime import datetime, timezone, timedelta
from flask import Blueprint, request, jsonify, current_app, g
from pymongo.errors import PyMongoError

from models.database import get_db
from models.daily_schedule import DailySchedule
from models.sms_campaign import (
    SmsCampaign,
    STATUS_DRAFT,
    STATUS_PENDING_CONFIRMATION,
    STATUS_SENDING,
    RECIPIENT_PENDING,
    mask_mobile,
)
from models.sms_auto_settings import (
    SmsAutoSettings,
    POLICY_CONFIRMATION,
    POLICY_AUTOMATIC,
)
from routes.auth import admin_required
from routes.sms import calculate_sms_segments
from services.excel_student_service import normalize_indian_mobile

sms_auto_bp = Blueprint("sms_auto_bp", __name__, url_prefix="/api/sms/auto-schedule")


def _get_current_ist_time() -> datetime:
    """Return current Indian Standard Time (UTC + 5:30)."""
    return datetime.now(timezone.utc) + timedelta(hours=5, minutes=30)


# ── 1. Settings & Status Endpoint ───────────────────────────────────────────

@sms_auto_bp.route("/settings", methods=["GET"])
@admin_required
def get_auto_settings():
    """
    Get automatic SMS schedule configuration, next scheduled runs,
    published schedule readiness, and pending confirmations count.
    """
    try:
        settings = SmsAutoSettings.get_settings()
        ist_now = _get_current_ist_time()
        today_str = ist_now.strftime("%Y-%m-%d")

        # Check today's published morning and afternoon daily schedules
        morning_sched = DailySchedule.find_by_date_and_session(today_str, "morning")
        afternoon_sched = DailySchedule.find_by_date_and_session(today_str, "afternoon")

        morning_status = (
            "published" if (morning_sched and morning_sched.status == "published")
            else ("draft" if morning_sched else "not_created")
        )
        afternoon_status = (
            "published" if (afternoon_sched and afternoon_sched.status == "published")
            else ("draft" if afternoon_sched else "not_created")
        )

        # Count pending approval campaigns
        pending_campaigns = SmsCampaign.find_pending_confirmations()

        # Compute next scheduled morning & afternoon times
        morning_parts = settings.morning_time.split(":")
        afternoon_parts = settings.afternoon_time.split(":")

        m_hour = int(morning_parts[0]) if len(morning_parts) > 0 else 6
        m_min = int(morning_parts[1]) if len(morning_parts) > 1 else 30

        a_hour = int(afternoon_parts[0]) if len(afternoon_parts) > 0 else 14
        a_min = int(afternoon_parts[1]) if len(afternoon_parts) > 1 else 0

        morning_today = ist_now.replace(hour=m_hour, minute=m_min, second=0, microsecond=0)
        afternoon_today = ist_now.replace(hour=a_hour, minute=a_min, second=0, microsecond=0)

        next_morning_str = (
            morning_today.strftime("%Y-%m-%d %I:%M %p")
            if ist_now < morning_today
            else (morning_today + timedelta(days=1)).strftime("%Y-%m-%d %I:%M %p")
        )
        next_afternoon_str = (
            afternoon_today.strftime("%Y-%m-%d %I:%M %p")
            if ist_now < afternoon_today
            else (afternoon_today + timedelta(days=1)).strftime("%Y-%m-%d %I:%M %p")
        )

        return jsonify({
            "settings": settings.to_dict(),
            "today_date": today_str,
            "current_time_ist": ist_now.strftime("%Y-%m-%d %I:%M:%S %p"),
            "schedule_status": {
                "morning": morning_status,
                "afternoon": afternoon_status,
                "morning_version": morning_sched.version if morning_sched else None,
                "afternoon_version": afternoon_sched.version if afternoon_sched else None,
            },
            "next_scheduled": {
                "morning": next_morning_str,
                "afternoon": next_afternoon_str,
            },
            "pending_confirmations_count": len(pending_campaigns),
            "is_ready_for_morning": (
                settings.is_enabled and "morning" in settings.enabled_sessions and morning_status == "published"
            ),
            "is_ready_for_afternoon": (
                settings.is_enabled and "afternoon" in settings.enabled_sessions and afternoon_status == "published"
            ),
        }), 200
    except Exception:
        current_app.logger.exception("Failed to get auto SMS settings")
        return jsonify({"error": "Could not retrieve auto SMS settings"}), 500


@sms_auto_bp.route("/settings", methods=["PUT"])
@admin_required
def update_auto_settings():
    """Update automatic SMS configuration. Requires explicit enable."""
    data = request.get_json(silent=True) or {}
    try:
        settings = SmsAutoSettings.get_settings()

        if "is_enabled" in data:
            settings.is_enabled = bool(data["is_enabled"])
            if settings.is_enabled:
                settings.emergency_disabled = False  # Reset emergency disable on explicit enable
        if "morning_time" in data:
            settings.morning_time = str(data["morning_time"]).strip()
        if "afternoon_time" in data:
            settings.afternoon_time = str(data["afternoon_time"]).strip()
        if "confirmation_policy" in data:
            policy = str(data["confirmation_policy"]).strip().lower()
            if policy in (POLICY_CONFIRMATION, POLICY_AUTOMATIC):
                settings.confirmation_policy = policy
        if "enabled_sessions" in data and isinstance(data["enabled_sessions"], list):
            settings.enabled_sessions = [s.strip().lower() for s in data["enabled_sessions"]]
        if "recipient_group" in data:
            settings.recipient_group = str(data["recipient_group"]).strip()
        if "test_phone" in data:
            settings.test_phone = str(data["test_phone"]).strip()
        if "message_template_morning" in data:
            settings.message_template_morning = str(data["message_template_morning"]).strip()
        if "message_template_afternoon" in data:
            settings.message_template_afternoon = str(data["message_template_afternoon"]).strip()

        current_user = getattr(g, "current_user", None)
        settings.updated_by = current_user.id if current_user else None
        settings.save()

        return jsonify({
            "message": "Auto SMS settings updated successfully",
            "settings": settings.to_dict(),
        }), 200
    except Exception:
        current_app.logger.exception("Failed to update auto SMS settings")
        return jsonify({"error": "Could not update settings"}), 500


# ── 2. Emergency Disable Endpoint ────────────────────────────────────────────

@sms_auto_bp.route("/emergency-disable", methods=["POST"])
@admin_required
def emergency_disable():
    """Immediately stop all automatic SMS executions."""
    try:
        settings = SmsAutoSettings.get_settings()
        settings.is_enabled = False
        settings.emergency_disabled = True
        settings.save()
        current_app.logger.warning("Emergency disable triggered for automatic SMS")
        return jsonify({
            "message": "Automatic SMS has been EMERGENCY DISABLED.",
            "settings": settings.to_dict(),
        }), 200
    except Exception:
        current_app.logger.exception("Emergency disable failed")
        return jsonify({"error": "Could not trigger emergency disable"}), 500


# ── 3. Prepare Scheduled Campaign (Core Engine) ──────────────────────────────

@sms_auto_bp.route("/prepare", methods=["POST"])
@admin_required
def prepare_scheduled_campaign():
    """
    Core engine called at 6:30 AM or 2:00 PM (or manually by administrator).
    Workflow:
      1. Checks if auto SMS is enabled (unless force_test=true).
      2. Validates session ('morning' | 'afternoon') is active.
      3. Retrieves today's PUBLISHED schedule. Rejects unpublished/draft schedules.
      4. Generates unique campaign key: 'AUTO_{date}_{session}_v{version}'.
      5. Prevents duplicate campaign creation if already exists.
      6. Maps published bus routes to students and creates personalized/route messages.
      7. Sets status to 'pending_confirmation' (Confirmation Mode) or 'draft' (Automatic Mode).
    """
    data = request.get_json(silent=True) or {}
    session = str(data.get("session", "morning")).strip().lower()
    force_test = bool(data.get("force_test", False))
    force_create = bool(data.get("force_create", False))

    if session not in ("morning", "afternoon"):
        return jsonify({"error": "session must be 'morning' or 'afternoon'"}), 400

    ist_now = _get_current_ist_time()
    date_str = str(data.get("date") or ist_now.strftime("%Y-%m-%d")).strip()

    settings = SmsAutoSettings.get_settings()

    # Step 1: Check enabled status
    if not settings.is_enabled and not force_test:
        return jsonify({
            "error": "Automatic SMS is currently disabled. The administrator must explicitly enable it.",
            "is_enabled": False,
        }), 400

    # Step 2: Check session enabled
    if session not in settings.enabled_sessions and not force_test:
        return jsonify({
            "error": f"Session '{session}' is not enabled in automatic SMS settings.",
        }), 400

    # Step 3: Strict Published Schedule Verification
    schedule = DailySchedule.find_by_date_and_session(date_str, session)
    if not schedule:
        return jsonify({
            "error": f"No daily bus schedule found for {date_str} ({session}). Unpublished schedules cannot be sent.",
            "schedule_status": "missing",
        }), 400

    if schedule.status != "published":
        return jsonify({
            "error": f"Daily bus schedule for {date_str} ({session}) is currently in '{schedule.status}' status. "
                     "Automatic SMS strictly requires a PUBLISHED schedule.",
            "schedule_status": schedule.status,
        }), 400

    if not schedule.buses:
        return jsonify({
            "error": f"Published schedule for {date_str} ({session}) contains 0 buses.",
        }), 400

    # Step 4: Unique Campaign Key for Duplicate Prevention
    auto_campaign_key = f"AUTO_{date_str}_{session}_v{schedule.version}"
    existing_campaign = SmsCampaign.find_by_auto_campaign_key(auto_campaign_key)

    if existing_campaign and not force_create and not force_test:
        return jsonify({
            "message": "A campaign for this published schedule version already exists. Duplicate creation prevented.",
            "campaign": existing_campaign.to_dict(include_recipients=False),
            "duplicate_prevented": True,
            "auto_campaign_key": auto_campaign_key,
        }), 200

    # Step 5: Gather Recipients and Prepare Messages
    db = get_db()
    recipients_list = []
    invalid_count = 0
    duplicate_count = 0
    seen_mobiles = set()

    # Case A: Safe Test Campaign
    if force_test:
        raw_test_phone = data.get("test_phone") or settings.test_phone
        is_val, clean_phone, err = normalize_indian_mobile(raw_test_phone)
        if not is_val:
            return jsonify({"error": f"Invalid test phone: {err}"}), 400

        first_bus = schedule.buses[0]
        test_msg = (
            f"[TEST AUTO SMS] KLNCE {session.capitalize()} Bus: {first_bus.get('bus_number', 'S1')} "
            f"on {first_bus.get('route_name', 'Route 1')} departs at {first_bus.get('departure_time', '7:00 AM')}. "
            f"Date: {date_str}."
        )

        recipients_list.append({
            "student_id": 0,
            "register_number": "TEST-AUTO-ADMIN",
            "name": "Administrator Test Device",
            "mobile_number": clean_phone,
            "masked_mobile": mask_mobile(clean_phone),
            "status": RECIPIENT_PENDING,
        })
        campaign_title = f"Test Auto {session.capitalize()} SMS ({date_str})"
        campaign_message = test_msg
    else:
        # Case B: Real Students Assigned to Published Buses
        # Map published routes and buses
        bus_routes = {b.get("route_name"): b for b in schedule.buses if b.get("route_name")}
        bus_numbers = {b.get("bus_number"): b for b in schedule.buses if b.get("bus_number")}

        template = (
            settings.message_template_morning if session == "morning"
            else settings.message_template_afternoon
        )

        # Query all active transport students
        students = list(
            db["students"].find(
                {"is_transport_active": True},
                {
                    "_id": 1,
                    "register_number": 1,
                    "name": 1,
                    "student_mobile": 1,
                    "route_name": 1,
                    "bus_number": 1,
                    "boarding_stop": 1,
                },
            ).sort("register_number", 1)
        )

        for s in students:
            raw_mob = s.get("student_mobile")
            is_valid, clean_mob, _ = normalize_indian_mobile(raw_mob)
            if not is_valid:
                invalid_count += 1
                continue

            # Deduplicate mobile numbers within this automated campaign
            if clean_mob in seen_mobiles:
                duplicate_count += 1
                continue

            seen_mobiles.add(clean_mob)

            # Resolve bus & route info for student
            st_route = s.get("route_name", "")
            st_bus = s.get("bus_number", "")
            matched_bus = bus_routes.get(st_route) or bus_numbers.get(st_bus) or schedule.buses[0]

            dep_time = matched_bus.get("departure_time", "7:00 AM" if session == "morning" else "4:30 PM")
            stops = matched_bus.get("stops", [])
            first_stop = stops[0].get("stop_name", "Campus") if stops else "Campus"

            formatted_msg = template.format(
                bus_number=matched_bus.get("bus_number", st_bus or "S1"),
                route_name=matched_bus.get("route_name", st_route or "Assigned Route"),
                departure_time=dep_time,
                first_stop=first_stop,
                date=date_str,
                session=session.capitalize(),
            )

            recipients_list.append({
                "student_id": s["_id"],
                "register_number": s.get("register_number", ""),
                "name": s.get("name", ""),
                "mobile_number": clean_mob,
                "masked_mobile": mask_mobile(clean_mob),
                "status": RECIPIENT_PENDING,
                "route_name": st_route,
                "bus_number": st_bus,
                "boarding_stop": s.get("boarding_stop", ""),
            })

        campaign_title = f"Daily {session.capitalize()} Bus Schedule ({date_str} v{schedule.version})"
        campaign_message = (
            f"KLNCE Transport: Today's {session} bus schedule is published. "
            f"Buses operating: {', '.join([b.get('bus_number', '') for b in schedule.buses[:5]])}. Check app for stop details."
        )

    if not recipients_list:
        return jsonify({"error": "No valid active student recipients found for this schedule."}), 400

    # Step 6: Confirmation Policy Determination
    policy = settings.confirmation_policy
    if force_test:
        initial_status = STATUS_DRAFT
    else:
        # Default is Confirmation Mode: prepares campaign and waits for administrator approval
        initial_status = (
            STATUS_PENDING_CONFIRMATION if policy == POLICY_CONFIRMATION
            else STATUS_DRAFT
        )

    seg_info = calculate_sms_segments(campaign_message)
    total_sms = len(recipients_list) * seg_info["segments_per_message"]

    current_user = getattr(g, "current_user", None)
    admin_id = current_user.id if current_user else None

    campaign = SmsCampaign(
        title=campaign_title,
        message=campaign_message,
        target_type="daily_schedule_auto",
        recipients=recipients_list,
        target_filter={
            "session": session,
            "date": date_str,
            "schedule_id": schedule.id,
            "schedule_version": schedule.version,
        },
        route_name=f"{session.capitalize()} Schedule ({len(schedule.buses)} Buses)",
        delivery_method="direct_sim",
        status=initial_status,
        allow_duplicates=False,
        duplicates_prevented_count=duplicate_count,
        segments_per_message=seg_info["segments_per_message"],
        total_sms_count=total_sms,
        valid_count=len(recipients_list),
        invalid_count=invalid_count,
        duplicate_count=duplicate_count,
        auto_campaign_key=auto_campaign_key if not force_test else None,
        schedule_id=schedule.id,
        schedule_version=schedule.version,
        confirmation_policy=policy,
        created_by=admin_id,
    )
    campaign_id = campaign.save()

    # Record last run metadata
    if not force_test:
        SmsAutoSettings.record_run(
            session=session,
            campaign_id=campaign_id,
            status=initial_status,
            count=len(recipients_list),
        )

    return jsonify({
        "message": (
            "Campaign prepared and awaiting administrator confirmation."
            if initial_status == STATUS_PENDING_CONFIRMATION
            else "Campaign prepared and ready for automatic SIM dispatch."
        ),
        "campaign": campaign.to_dict(include_recipients=True),
        "confirmation_required": (initial_status == STATUS_PENDING_CONFIRMATION),
        "auto_campaign_key": auto_campaign_key,
        "schedule_version": schedule.version,
    }), 201


# ── 4. Pending Confirmations & Approval ─────────────────────────────────────

@sms_auto_bp.route("/pending-confirmations", methods=["GET"])
@admin_required
def get_pending_confirmations():
    """List scheduled campaigns awaiting administrator approval before SIM dispatch."""
    try:
        pending = SmsCampaign.find_pending_confirmations()
        return jsonify({
            "count": len(pending),
            "campaigns": pending,
        }), 200
    except Exception:
        current_app.logger.exception("Failed to query pending confirmations")
        return jsonify({"error": "Could not retrieve pending campaigns"}), 500


@sms_auto_bp.route("/campaigns/<int:campaign_id>/approve", methods=["POST"])
@admin_required
def approve_pending_campaign(campaign_id: int):
    """
    Administrator approves a scheduled campaign in Confirmation Mode.
    Changes status to 'ready' (draft) so Android phone SIM can immediately dispatch.
    """
    try:
        campaign = SmsCampaign.find_by_id(campaign_id)
        if not campaign:
            return jsonify({"error": f"Campaign {campaign_id} not found"}), 404

        if campaign.status != STATUS_PENDING_CONFIRMATION:
            return jsonify({
                "error": f"Campaign is in '{campaign.status}' state, not pending confirmation.",
            }), 400

        # Change status to draft/ready to send
        db = get_db()
        db["sms_campaigns"].update_one(
            {"_id": campaign_id},
            {"$set": {"status": STATUS_DRAFT, "approved_at": datetime.now(timezone.utc)}},
        )

        updated = SmsCampaign.find_by_id(campaign_id)
        return jsonify({
            "message": "Campaign approved by administrator. Ready for phone SIM dispatch.",
            "campaign": updated.to_dict(include_recipients=True) if updated else {},
        }), 200
    except Exception:
        current_app.logger.exception("Failed to approve campaign")
        return jsonify({"error": "Could not approve campaign"}), 500
