# -*- coding: utf-8 -*-
"""
models/sms_auto_settings.py — Settings and runtime state for automatic morning and afternoon SMS.
Enforces explicit activation, default Confirmation Mode, unique identification,
and emergency disable safeguards.
PyMongo / MongoDB Atlas backed.
"""

from datetime import datetime, timezone
import logging
from typing import Dict, Any, Optional

from models.database import get_db

logger = logging.getLogger(__name__)

SETTINGS_COLLECTION = "sms_auto_settings"
SINGLETON_ID = "global_auto_sms_config"

POLICY_CONFIRMATION = "confirmation"
POLICY_AUTOMATIC = "automatic"

DEFAULT_MORNING_TEMPLATE = (
    "KLNCE Transport: Morning bus {bus_number} on {route_name} departs at {departure_time}. "
    "Check app for stop sequence."
)
DEFAULT_AFTERNOON_TEMPLATE = (
    "KLNCE Transport: Afternoon bus {bus_number} on {route_name} departs at {departure_time}. "
    "Check app for stop sequence."
)


class SmsAutoSettings:
    """Manages Automatic SMS scheduling configuration and state."""

    def __init__(
        self,
        is_enabled: bool = False,
        morning_time: str = "06:30",
        afternoon_time: str = "14:00",
        confirmation_policy: str = POLICY_CONFIRMATION,
        enabled_sessions: Optional[list] = None,
        recipient_group: str = "all_active",
        test_phone: str = "",
        message_template_morning: str = DEFAULT_MORNING_TEMPLATE,
        message_template_afternoon: str = DEFAULT_AFTERNOON_TEMPLATE,
        emergency_disabled: bool = False,
        last_run_morning: Optional[Dict[str, Any]] = None,
        last_run_afternoon: Optional[Dict[str, Any]] = None,
        updated_at: Optional[datetime] = None,
        updated_by: Optional[int] = None,
    ):
        self.is_enabled = bool(is_enabled)
        self.morning_time = morning_time.strip() or "06:30"
        self.afternoon_time = afternoon_time.strip() or "14:00"
        self.confirmation_policy = (
            confirmation_policy if confirmation_policy in (POLICY_CONFIRMATION, POLICY_AUTOMATIC)
            else POLICY_CONFIRMATION
        )
        self.enabled_sessions = enabled_sessions if enabled_sessions is not None else ["morning", "afternoon"]
        self.recipient_group = recipient_group.strip() or "all_active"
        self.test_phone = test_phone.strip()
        self.message_template_morning = message_template_morning.strip() or DEFAULT_MORNING_TEMPLATE
        self.message_template_afternoon = message_template_afternoon.strip() or DEFAULT_AFTERNOON_TEMPLATE
        self.emergency_disabled = bool(emergency_disabled)
        self.last_run_morning = last_run_morning or {}
        self.last_run_afternoon = last_run_afternoon or {}
        self.updated_at = updated_at or datetime.now(timezone.utc)
        self.updated_by = updated_by

    def to_dict(self) -> Dict[str, Any]:
        return {
            "is_enabled": self.is_enabled and not self.emergency_disabled,
            "raw_enabled": self.is_enabled,
            "morning_time": self.morning_time,
            "afternoon_time": self.afternoon_time,
            "confirmation_policy": self.confirmation_policy,
            "enabled_sessions": self.enabled_sessions,
            "recipient_group": self.recipient_group,
            "test_phone": self.test_phone,
            "message_template_morning": self.message_template_morning,
            "message_template_afternoon": self.message_template_afternoon,
            "emergency_disabled": self.emergency_disabled,
            "last_run_morning": self.last_run_morning,
            "last_run_afternoon": self.last_run_afternoon,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
            "updated_by": self.updated_by,
        }

    @classmethod
    def get_settings(cls) -> "SmsAutoSettings":
        """Load global auto SMS settings from MongoDB or return default un-enabled state."""
        db = get_db()
        doc = db[SETTINGS_COLLECTION].find_one({"_id": SINGLETON_ID})
        if not doc:
            default_settings = cls()
            default_settings.save()
            return default_settings

        return cls(
            is_enabled=doc.get("is_enabled", False),
            morning_time=doc.get("morning_time", "06:30"),
            afternoon_time=doc.get("afternoon_time", "14:00"),
            confirmation_policy=doc.get("confirmation_policy", POLICY_CONFIRMATION),
            enabled_sessions=doc.get("enabled_sessions", ["morning", "afternoon"]),
            recipient_group=doc.get("recipient_group", "all_active"),
            test_phone=doc.get("test_phone", ""),
            message_template_morning=doc.get("message_template_morning", DEFAULT_MORNING_TEMPLATE),
            message_template_afternoon=doc.get("message_template_afternoon", DEFAULT_AFTERNOON_TEMPLATE),
            emergency_disabled=doc.get("emergency_disabled", False),
            last_run_morning=doc.get("last_run_morning", {}),
            last_run_afternoon=doc.get("last_run_afternoon", {}),
            updated_at=doc.get("updated_at"),
            updated_by=doc.get("updated_by"),
        )

    def save(self) -> None:
        """Persist auto SMS settings in MongoDB singleton document."""
        db = get_db()
        self.updated_at = datetime.now(timezone.utc)
        doc = {
            "_id": SINGLETON_ID,
            "is_enabled": self.is_enabled,
            "morning_time": self.morning_time,
            "afternoon_time": self.afternoon_time,
            "confirmation_policy": self.confirmation_policy,
            "enabled_sessions": self.enabled_sessions,
            "recipient_group": self.recipient_group,
            "test_phone": self.test_phone,
            "message_template_morning": self.message_template_morning,
            "message_template_afternoon": self.message_template_afternoon,
            "emergency_disabled": self.emergency_disabled,
            "last_run_morning": self.last_run_morning,
            "last_run_afternoon": self.last_run_afternoon,
            "updated_at": self.updated_at,
            "updated_by": self.updated_by,
        }
        db[SETTINGS_COLLECTION].update_one({"_id": SINGLETON_ID}, {"$set": doc}, upsert=True)
        logger.info("Saved auto SMS settings. is_enabled=%s, policy=%s", self.is_enabled, self.confirmation_policy)

    @classmethod
    def record_run(cls, session: str, campaign_id: int, status: str, count: int, error: Optional[str] = None):
        """Update last run metadata for a session."""
        db = get_db()
        now = datetime.now(timezone.utc).isoformat()
        run_data = {
            "timestamp": now,
            "campaign_id": campaign_id,
            "status": status,
            "recipient_count": count,
            "error": error,
        }
        field = "last_run_morning" if session == "morning" else "last_run_afternoon"
        db[SETTINGS_COLLECTION].update_one({"_id": SINGLETON_ID}, {"$set": {field: run_data}})
