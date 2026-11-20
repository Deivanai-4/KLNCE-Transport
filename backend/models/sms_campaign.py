# -*- coding: utf-8 -*-
"""
models/sms_campaign.py — SMS Campaign & Dispatch Log Model for KLNCE Transport.
Tracks SMS broadcast sessions sent via administrator's Android device SIM.
Includes multi-status recipient tracking (Pending, Sending, Submitted, Delivery Confirmed, Failed, Cancelled),
safe deduplication, attempt counting, and retry support.
PyMongo / MongoDB Atlas backed.
"""

from datetime import datetime, timezone
import logging
import re
from typing import Optional, Dict, Any, List

from pymongo.errors import PyMongoError

from models.database import get_db, get_next_sequence

logger = logging.getLogger(__name__)

COLLECTION_NAME = "sms_campaigns"

# Allowed campaign statuses
STATUS_DRAFT = "draft"
STATUS_PENDING_CONFIRMATION = "pending_confirmation"
STATUS_SENDING = "sending"
STATUS_PAUSED = "paused"
STATUS_COMPLETED = "completed"
STATUS_PARTIALLY_FAILED = "partially_failed"
STATUS_CANCELLED = "cancelled"

VALID_CAMPAIGN_STATUSES = {
    STATUS_DRAFT,
    STATUS_PENDING_CONFIRMATION,
    STATUS_SENDING,
    STATUS_PAUSED,
    STATUS_COMPLETED,
    STATUS_PARTIALLY_FAILED,
    STATUS_CANCELLED,
}

# Individual recipient SMS statuses (Stage 7 compliant)
RECIPIENT_PENDING = "pending"
RECIPIENT_SENDING = "sending"
RECIPIENT_SUBMITTED = "submitted_to_sms_service"
RECIPIENT_SENT_TO_SMS_SERVICE = "sent_to_sms_service"  # alias for backwards compatibility
RECIPIENT_DELIVERY_CONFIRMED = "delivery_confirmed"
RECIPIENT_FAILED = "failed"
RECIPIENT_CANCELLED = "cancelled"

VALID_RECIPIENT_STATUSES = {
    RECIPIENT_PENDING,
    RECIPIENT_SENDING,
    RECIPIENT_SUBMITTED,
    RECIPIENT_SENT_TO_SMS_SERVICE,
    RECIPIENT_DELIVERY_CONFIRMED,
    RECIPIENT_FAILED,
    RECIPIENT_CANCELLED,
}


def mask_mobile(mobile: str) -> str:
    """Mask mobile number so full digits are not exposed: e.g. +91 98*** **210."""
    if not mobile:
        return "N/A"
    clean = re.sub(r"\D", "", str(mobile))
    if len(clean) >= 10:
        last10 = clean[-10:]
        return f"+91 {last10[:2]}*** **{last10[-3:]}"
    elif len(clean) > 4:
        return f"{clean[:2]}***{clean[-2:]}"
    else:
        return "***"


class SmsCampaign:
    """Represents an SMS dispatch campaign initiated by the transport administrator."""

    def __init__(
        self,
        title: str,
        message: str,
        target_type: str,
        recipients: List[Dict[str, Any]],
        _id: Optional[int] = None,
        target_filter: Optional[Dict[str, Any]] = None,
        route_name: Optional[str] = None,
        bus_number: Optional[str] = None,
        sender_device: Optional[Dict[str, Any]] = None,
        delivery_method: str = "direct_sim",
        status: str = STATUS_DRAFT,
        submitted_count: int = 0,
        delivery_confirmed_count: int = 0,
        failed_count: int = 0,
        cancelled_count: int = 0,
        sent_count: Optional[int] = None,
        allow_duplicates: bool = False,
        duplicates_prevented_count: int = 0,
        segments_per_message: int = 1,
        total_sms_count: int = 0,
        valid_count: int = 0,
        invalid_count: int = 0,
        duplicate_count: int = 0,
        auto_campaign_key: Optional[str] = None,
        schedule_id: Optional[int] = None,
        schedule_version: Optional[int] = None,
        confirmation_policy: Optional[str] = None,
        created_by: Optional[int] = None,
        created_at: Optional[datetime] = None,
        updated_at: Optional[datetime] = None,
        completed_at: Optional[datetime] = None,
    ):
        self.id = _id
        self.title = (title or "").strip()
        self.message = (message or "").strip()
        self.target_type = (target_type or "all_active").strip().lower()
        self.target_filter = target_filter or {}
        self.route_name = (route_name or "").strip() or None
        self.bus_number = (bus_number or "").strip().upper() or None
        self.sender_device = sender_device or {}
        self.delivery_method = delivery_method
        self.status = status if status in VALID_CAMPAIGN_STATUSES else STATUS_DRAFT
        self.allow_duplicates = bool(allow_duplicates)
        self.duplicates_prevented_count = duplicates_prevented_count
        self.segments_per_message = max(1, segments_per_message)
        self.valid_count = valid_count
        self.invalid_count = invalid_count
        self.duplicate_count = duplicate_count
        self.auto_campaign_key = (auto_campaign_key or "").strip() or None
        self.schedule_id = schedule_id
        self.schedule_version = schedule_version
        self.confirmation_policy = confirmation_policy or "confirmation"

        # Sanitise recipient entries with full Stage 7 metadata
        now_iso = (created_at or datetime.now(timezone.utc)).isoformat()
        sanitised_recipients = []
        for idx, r in enumerate(recipients):
            mob = str(r.get("mobile_number") or r.get("student_mobile", "")).strip()
            msg_ref = r.get("message_ref") or f"SMS-{self.id or 'TMP'}-{idx+1}"
            raw_status = r.get("status", RECIPIENT_PENDING)
            norm_status = raw_status if raw_status in VALID_RECIPIENT_STATUSES else RECIPIENT_PENDING

            sanitised_recipients.append({
                "student_id": r.get("student_id"),
                "register_number": str(r.get("register_number", "")).strip(),
                "name": str(r.get("name", "")).strip(),
                "mobile_number": mob,
                "masked_mobile": r.get("masked_mobile") or mask_mobile(mob),
                "message_ref": msg_ref,
                "status": norm_status,
                "attempt_count": int(r.get("attempt_count", 0)),
                "error_reason": r.get("error_reason") or r.get("error_message"),
                "error_message": r.get("error_reason") or r.get("error_message"),  # compatibility alias
                "created_at": r.get("created_at") or now_iso,
                "sent_at": r.get("sent_at") or r.get("dispatched_at"),
                "dispatched_at": r.get("sent_at") or r.get("dispatched_at"),  # compatibility alias
                "delivered_at": r.get("delivered_at"),
            })
        self.recipients = sanitised_recipients

        self.total_recipients = len(self.recipients)
        self.total_sms_count = total_sms_count or (self.total_recipients * self.segments_per_message)
        self.submitted_count = submitted_count if submitted_count > 0 else (sent_count or 0)
        self.sent_count = self.submitted_count  # compatibility alias
        self.delivery_confirmed_count = delivery_confirmed_count
        self.failed_count = failed_count
        self.cancelled_count = cancelled_count
        self.created_by = created_by
        self.created_at = created_at or datetime.now(timezone.utc)
        self.updated_at = updated_at or datetime.now(timezone.utc)
        self.completed_at = completed_at

    def to_dict(self, include_recipients: bool = True) -> Dict[str, Any]:
        """Convert campaign instance to dictionary."""
        pending_cnt = max(
            0,
            self.total_recipients
            - self.submitted_count
            - self.failed_count
            - self.cancelled_count,
        )

        data = {
            "id": self.id,
            "title": self.title,
            "message": self.message,
            "target_type": self.target_type,
            "target_filter": self.target_filter,
            "route_name": self.route_name,
            "bus_number": self.bus_number,
            "sender_device": self.sender_device,
            "delivery_method": self.delivery_method,
            "status": self.status,
            "allow_duplicates": self.allow_duplicates,
            "duplicates_prevented_count": self.duplicates_prevented_count,
            "segments_per_message": self.segments_per_message,
            "total_sms_count": self.total_sms_count,
            "valid_count": self.valid_count or self.total_recipients,
            "invalid_count": self.invalid_count,
            "duplicate_count": self.duplicate_count,
            "auto_campaign_key": self.auto_campaign_key,
            "schedule_id": self.schedule_id,
            "schedule_version": self.schedule_version,
            "confirmation_policy": self.confirmation_policy,
            "total_recipients": self.total_recipients,
            "submitted_count": self.submitted_count,
            "sent_count": self.submitted_count,  # compatibility alias
            "delivery_confirmed_count": self.delivery_confirmed_count,
            "failed_count": self.failed_count,
            "cancelled_count": self.cancelled_count,
            "pending_count": pending_cnt,
            "created_by": self.created_by,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
        }
        if include_recipients:
            data["recipients"] = self.recipients
        return data

    @classmethod
    def from_mongo(cls, doc: Dict[str, Any]) -> "SmsCampaign":
        """Instantiate SmsCampaign from MongoDB document."""
        return cls(
            _id=doc["_id"],
            title=doc.get("title", ""),
            message=doc.get("message", ""),
            target_type=doc.get("target_type", "all_active"),
            target_filter=doc.get("target_filter", {}),
            route_name=doc.get("route_name"),
            bus_number=doc.get("bus_number"),
            sender_device=doc.get("sender_device", {}),
            delivery_method=doc.get("delivery_method", "direct_sim"),
            status=doc.get("status", STATUS_DRAFT),
            recipients=doc.get("recipients", []),
            submitted_count=doc.get("submitted_count", doc.get("sent_count", 0)),
            delivery_confirmed_count=doc.get("delivery_confirmed_count", 0),
            failed_count=doc.get("failed_count", 0),
            cancelled_count=doc.get("cancelled_count", 0),
            sent_count=doc.get("sent_count", 0),
            allow_duplicates=doc.get("allow_duplicates", False),
            duplicates_prevented_count=doc.get("duplicates_prevented_count", 0),
            segments_per_message=doc.get("segments_per_message", 1),
            total_sms_count=doc.get("total_sms_count", 0),
            valid_count=doc.get("valid_count", 0),
            invalid_count=doc.get("invalid_count", 0),
            duplicate_count=doc.get("duplicate_count", 0),
            auto_campaign_key=doc.get("auto_campaign_key"),
            schedule_id=doc.get("schedule_id"),
            schedule_version=doc.get("schedule_version"),
            confirmation_policy=doc.get("confirmation_policy", "confirmation"),
            created_by=doc.get("created_by"),
            created_at=doc.get("created_at"),
            updated_at=doc.get("updated_at"),
            completed_at=doc.get("completed_at"),
        )

    def save(self) -> int:
        """Insert new campaign into MongoDB with auto-increment ID."""
        db = get_db()
        self.id = get_next_sequence(COLLECTION_NAME)
        self.created_at = datetime.now(timezone.utc)
        self.updated_at = self.created_at

        # Update message_ref with actual ID
        for idx, r in enumerate(self.recipients):
            r["message_ref"] = f"SMS-C{self.id}-{idx+1}"

        doc = {
            "_id": self.id,
            "title": self.title,
            "message": self.message,
            "target_type": self.target_type,
            "target_filter": self.target_filter,
            "route_name": self.route_name,
            "bus_number": self.bus_number,
            "sender_device": self.sender_device,
            "delivery_method": self.delivery_method,
            "status": self.status,
            "allow_duplicates": self.allow_duplicates,
            "duplicates_prevented_count": self.duplicates_prevented_count,
            "segments_per_message": self.segments_per_message,
            "total_sms_count": self.total_sms_count,
            "valid_count": self.valid_count,
            "invalid_count": self.invalid_count,
            "duplicate_count": self.duplicate_count,
            "auto_campaign_key": self.auto_campaign_key,
            "schedule_id": self.schedule_id,
            "schedule_version": self.schedule_version,
            "confirmation_policy": self.confirmation_policy,
            "recipients": self.recipients,
            "total_recipients": self.total_recipients,
            "submitted_count": self.submitted_count,
            "sent_count": self.submitted_count,
            "delivery_confirmed_count": self.delivery_confirmed_count,
            "failed_count": self.failed_count,
            "cancelled_count": self.cancelled_count,
            "created_by": self.created_by,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "completed_at": self.completed_at,
        }
        db[COLLECTION_NAME].insert_one(doc)
        logger.info("Saved SMS campaign id=%d, recipients=%d", self.id, self.total_recipients)
        return self.id

    @classmethod
    def find_by_id(cls, campaign_id: int) -> Optional["SmsCampaign"]:
        """Find campaign by ID."""
        db = get_db()
        doc = db[COLLECTION_NAME].find_one({"_id": campaign_id})
        return cls.from_mongo(doc) if doc else None

    @classmethod
    def find_by_auto_campaign_key(cls, key: str) -> Optional["SmsCampaign"]:
        """Find campaign by unique auto campaign key to prevent duplicates."""
        if not key:
            return None
        db = get_db()
        doc = db[COLLECTION_NAME].find_one({"auto_campaign_key": key.strip()})
        return cls.from_mongo(doc) if doc else None

    @classmethod
    def find_pending_confirmations(cls) -> List[Dict[str, Any]]:
        """List campaigns awaiting administrator confirmation before SIM dispatch."""
        db = get_db()
        cursor = (
            db[COLLECTION_NAME]
            .find({"status": STATUS_PENDING_CONFIRMATION})
            .sort("created_at", -1)
        )
        results = []
        for doc in cursor:
            doc["id"] = doc["_id"]
            if doc.get("created_at"):
                doc["created_at"] = doc["created_at"].isoformat()
            if doc.get("updated_at"):
                doc["updated_at"] = doc["updated_at"].isoformat()
            results.append(doc)
        return results

    @classmethod
    def list_campaigns(
        cls,
        status: Optional[str] = None,
        target_type: Optional[str] = None,
        limit: int = 50,
        skip: int = 0,
        include_recipients: bool = False,
    ) -> List[Dict[str, Any]]:
        """List campaigns with optional filters, sorted newest first."""
        db = get_db()
        query: Dict[str, Any] = {}
        if status:
            query["status"] = status
        if target_type:
            query["target_type"] = target_type

        projection = None if include_recipients else {"recipients": 0}
        cursor = (
            db[COLLECTION_NAME]
            .find(query, projection)
            .sort("created_at", -1)
            .skip(skip)
            .limit(limit)
        )

        results = []
        for doc in cursor:
            doc["id"] = doc["_id"]
            if doc.get("created_at"):
                doc["created_at"] = doc["created_at"].isoformat()
            if doc.get("updated_at"):
                doc["updated_at"] = doc["updated_at"].isoformat()
            if doc.get("completed_at"):
                doc["completed_at"] = doc["completed_at"].isoformat()

            sub_cnt = doc.get("submitted_count", doc.get("sent_count", 0))
            fail_cnt = doc.get("failed_count", 0)
            canc_cnt = doc.get("cancelled_count", 0)
            doc["submitted_count"] = sub_cnt
            doc["sent_count"] = sub_cnt
            doc["pending_count"] = max(
                0,
                doc.get("total_recipients", 0) - sub_cnt - fail_cnt - canc_cnt,
            )
            results.append(doc)
        return results

    @classmethod
    def update_progress(
        cls,
        campaign_id: int,
        status: Optional[str] = None,
        sender_device: Optional[Dict[str, Any]] = None,
        recipient_updates: Optional[List[Dict[str, Any]]] = None,
    ) -> bool:
        """
        Update campaign status, sender device information, and individual recipient statuses.
        Accurately computes submitted_count, delivery_confirmed_count, failed_count, and cancelled_count.
        """
        db = get_db()
        campaign = cls.find_by_id(campaign_id)
        if not campaign:
            return False

        now = datetime.now(timezone.utc)
        now_iso = now.isoformat()
        update_fields: Dict[str, Any] = {"updated_at": now}

        if sender_device:
            update_fields["sender_device"] = sender_device

        # If recipient updates provided, update matching recipients in memory
        if recipient_updates:
            update_map = {}
            for u in recipient_updates:
                key = u.get("student_id")
                if key is not None and str(key) != "0":
                    update_map[str(key)] = u
                else:
                    mob_key = u.get("mobile_number")
                    if mob_key:
                        update_map[str(mob_key)] = u

            submitted_cnt = 0
            delivered_cnt = 0
            failed_cnt = 0
            cancelled_cnt = 0

            for r in campaign.recipients:
                sid_key = str(r.get("student_id")) if r.get("student_id") is not None else None
                mob_key = str(r.get("mobile_number", ""))
                u = update_map.get(sid_key) or update_map.get(mob_key)
                if u:
                    raw_st = u.get("status")
                    if raw_st and raw_st in VALID_RECIPIENT_STATUSES:
                        r["status"] = raw_st

                    err = u.get("error_reason") or u.get("error_message")
                    if err is not None:
                        r["error_reason"] = err
                        r["error_message"] = err

                    # Increment attempt count
                    if "attempt_count" in u:
                        r["attempt_count"] = int(u["attempt_count"])
                    elif r["status"] in (RECIPIENT_SUBMITTED, RECIPIENT_FAILED):
                        r["attempt_count"] = max(1, r.get("attempt_count", 0) + 1)

                    sent_t = u.get("sent_at") or u.get("dispatched_at")
                    if sent_t:
                        r["sent_at"] = sent_t
                        r["dispatched_at"] = sent_t
                    elif r["status"] in (RECIPIENT_SUBMITTED, RECIPIENT_DELIVERY_CONFIRMED) and not r.get("sent_at"):
                        r["sent_at"] = now_iso
                        r["dispatched_at"] = now_iso

                    deliv_t = u.get("delivered_at")
                    if deliv_t:
                        r["delivered_at"] = deliv_t
                    elif r["status"] == RECIPIENT_DELIVERY_CONFIRMED and not r.get("delivered_at"):
                        r["delivered_at"] = now_iso

                # Tally statuses
                st = r.get("status")
                if st in (RECIPIENT_SUBMITTED, RECIPIENT_SENT_TO_SMS_SERVICE):
                    submitted_cnt += 1
                elif st == RECIPIENT_DELIVERY_CONFIRMED:
                    submitted_cnt += 1
                    delivered_cnt += 1
                elif st == RECIPIENT_FAILED:
                    failed_cnt += 1
                elif st == RECIPIENT_CANCELLED:
                    cancelled_cnt += 1

            update_fields["recipients"] = campaign.recipients
            update_fields["submitted_count"] = submitted_cnt
            update_fields["sent_count"] = submitted_cnt
            update_fields["delivery_confirmed_count"] = delivered_cnt
            update_fields["failed_count"] = failed_cnt
            update_fields["cancelled_count"] = cancelled_cnt

            # Auto-calculate campaign status if not explicitly set to a terminal status (cancelled, paused)
            if not status or status == STATUS_SENDING:
                total_processed = submitted_cnt + failed_cnt + cancelled_cnt
                if total_processed >= campaign.total_recipients and campaign.total_recipients > 0:
                    if failed_cnt == 0 and cancelled_cnt == 0:
                        status = STATUS_COMPLETED
                    else:
                        status = STATUS_PARTIALLY_FAILED
                elif submitted_cnt > 0 or failed_cnt > 0:
                    status = STATUS_SENDING

        if status and status in VALID_CAMPAIGN_STATUSES:
            update_fields["status"] = status
            if status in (STATUS_COMPLETED, STATUS_PARTIALLY_FAILED, STATUS_CANCELLED):
                update_fields["completed_at"] = now

        db[COLLECTION_NAME].update_one({"_id": campaign_id}, {"$set": update_fields})
        return True

    @classmethod
    def retry_failed(
        cls,
        campaign_id: int,
        recipient_ids: Optional[List[int]] = None,
    ) -> Optional["SmsCampaign"]:
        """
        Reset failed/cancelled recipients back to RECIPIENT_PENDING to allow retry dispatch.
        STRICT RULE: Never re-send or modify previously successful (submitted/delivered) recipients!
        """
        db = get_db()
        campaign = cls.find_by_id(campaign_id)
        if not campaign:
            return None

        target_set = set(recipient_ids) if recipient_ids else None
        failed_found = False

        for r in campaign.recipients:
            st = r.get("status")
            sid = r.get("student_id")
            # Only retry if recipient is failed or cancelled
            if st in (RECIPIENT_FAILED, RECIPIENT_CANCELLED):
                if target_set is None or (sid is not None and sid in target_set):
                    r["status"] = RECIPIENT_PENDING
                    r["error_reason"] = None
                    r["error_message"] = None
                    failed_found = True

        if failed_found:
            # Recalculate counts
            failed_cnt = sum(1 for r in campaign.recipients if r.get("status") == RECIPIENT_FAILED)
            canc_cnt = sum(1 for r in campaign.recipients if r.get("status") == RECIPIENT_CANCELLED)
            campaign.failed_count = failed_cnt
            campaign.cancelled_count = canc_cnt
            campaign.status = STATUS_SENDING
            campaign.updated_at = datetime.now(timezone.utc)
            db[COLLECTION_NAME].update_one(
                {"_id": campaign_id},
                {
                    "$set": {
                        "recipients": campaign.recipients,
                        "failed_count": failed_cnt,
                        "cancelled_count": canc_cnt,
                        "status": STATUS_SENDING,
                        "updated_at": campaign.updated_at,
                    }
                },
            )
        return campaign

    @classmethod
    def cancel_pending(cls, campaign_id: int) -> Optional["SmsCampaign"]:
        """Cancel all currently pending or sending recipients in a campaign."""
        db = get_db()
        campaign = cls.find_by_id(campaign_id)
        if not campaign:
            return None

        cancelled_count = 0
        now = datetime.now(timezone.utc)

        for r in campaign.recipients:
            if r.get("status") in (RECIPIENT_PENDING, RECIPIENT_SENDING):
                r["status"] = RECIPIENT_CANCELLED
                r["error_reason"] = "Cancelled by administrator"
                r["error_message"] = "Cancelled by administrator"
                cancelled_count += 1

        campaign.cancelled_count = sum(1 for r in campaign.recipients if r.get("status") == RECIPIENT_CANCELLED)
        sub_cnt = campaign.submitted_count
        if sub_cnt > 0:
            campaign.status = STATUS_PARTIALLY_FAILED
        else:
            campaign.status = STATUS_CANCELLED
        campaign.completed_at = now
        campaign.updated_at = now

        db[COLLECTION_NAME].update_one(
            {"_id": campaign_id},
            {
                "$set": {
                    "recipients": campaign.recipients,
                    "cancelled_count": campaign.cancelled_count,
                    "status": campaign.status,
                    "completed_at": now,
                    "updated_at": now,
                }
            },
        )
        return campaign
