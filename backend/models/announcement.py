# -*- coding: utf-8 -*-
"""
models/announcement.py — PyMongo-backed Announcement document model.

Collection: announcements
Document shape:
  _id:                    int (auto-increment sequence)
  id:                     int (mirror of _id)
  title:                  str (max 200 chars)
  message:                str
  category:               str (one of the 8 required categories)
  priority:               str ('low', 'normal', 'high', 'emergency')
  status:                 str ('draft', 'published', 'archived')
  target_type:            str ('all_active', 'route', 'bus', 'selected')
  target_route:           str | None
  target_bus:             str | None
  target_student_ids:     list[int]
  channels:               list[str] (['in_app', 'sms'] or subset)
  created_by:             int (FK -> users._id)
  created_by_name:        str
  created_at:             datetime (UTC)
  published_at:           datetime | None (UTC)
  updated_at:             datetime (UTC)
  recipient_count:        int
  in_app_count:           int
  sms_campaign_id:        int | None (FK -> sms_campaigns._id)
  read_by:                list[int] (user IDs of students who marked read)
  schedule_change_metadata: dict | None
"""

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
from models.database import get_db, get_next_sequence

COLLECTION_NAME = "announcements"

# Categories
CATEGORY_GENERAL = "General Transport Notice"
CATEGORY_DELAY = "Bus Delay"
CATEGORY_CANCELLATION = "Bus Cancellation"
CATEGORY_ROUTE_CHANGE = "Route Change"
CATEGORY_BUS_REPLACEMENT = "Bus Replacement"
CATEGORY_SCHEDULE_CHANGE = "Schedule Change"
CATEGORY_EMERGENCY = "Emergency Notice"
CATEGORY_HOLIDAY = "Holiday Transport Notice"

ALL_CATEGORIES = [
    CATEGORY_GENERAL,
    CATEGORY_DELAY,
    CATEGORY_CANCELLATION,
    CATEGORY_ROUTE_CHANGE,
    CATEGORY_BUS_REPLACEMENT,
    CATEGORY_SCHEDULE_CHANGE,
    CATEGORY_EMERGENCY,
    CATEGORY_HOLIDAY,
]

# Priorities
PRIORITY_LOW = "low"
PRIORITY_NORMAL = "normal"
PRIORITY_HIGH = "high"
PRIORITY_EMERGENCY = "emergency"

ALL_PRIORITIES = [PRIORITY_LOW, PRIORITY_NORMAL, PRIORITY_HIGH, PRIORITY_EMERGENCY]

# Statuses
STATUS_DRAFT = "draft"
STATUS_PUBLISHED = "published"
STATUS_ARCHIVED = "archived"

ALL_STATUSES = [STATUS_DRAFT, STATUS_PUBLISHED, STATUS_ARCHIVED]

# Target types
TARGET_ALL_ACTIVE = "all_active"
TARGET_ROUTE = "route"
TARGET_BUS = "bus"
TARGET_SELECTED = "selected"


class Announcement:
    def __init__(
        self,
        title: str,
        message: str,
        category: str = CATEGORY_GENERAL,
        priority: str = PRIORITY_NORMAL,
        status: str = STATUS_DRAFT,
        target_type: str = TARGET_ALL_ACTIVE,
        target_route: Optional[str] = None,
        target_bus: Optional[str] = None,
        target_student_ids: Optional[List[int]] = None,
        channels: Optional[List[str]] = None,
        created_by: int = 0,
        created_by_name: str = "Admin",
        created_at: Optional[datetime] = None,
        published_at: Optional[datetime] = None,
        updated_at: Optional[datetime] = None,
        recipient_count: int = 0,
        in_app_count: int = 0,
        sms_campaign_id: Optional[int] = None,
        read_by: Optional[List[int]] = None,
        schedule_change_metadata: Optional[Dict[str, Any]] = None,
        id: Optional[int] = None,
    ):
        self.id = id or 0
        self.title = (title or "").strip()[:200]
        self.message = (message or "").strip()
        self.category = category if category in ALL_CATEGORIES else CATEGORY_GENERAL
        self.priority = priority if priority in ALL_PRIORITIES else PRIORITY_NORMAL
        self.status = status if status in ALL_STATUSES else STATUS_DRAFT
        self.target_type = target_type or TARGET_ALL_ACTIVE
        self.target_route = (target_route or "").strip() if target_route else None
        self.target_bus = (target_bus or "").strip().upper() if target_bus else None
        self.target_student_ids = target_student_ids or []
        self.channels = channels or ["in_app"]
        self.created_by = int(created_by)
        self.created_by_name = (created_by_name or "Admin").strip()
        now = datetime.now(timezone.utc)
        self.created_at = created_at or now
        self.published_at = published_at
        self.updated_at = updated_at or now
        self.recipient_count = int(recipient_count)
        self.in_app_count = int(in_app_count)
        self.sms_campaign_id = sms_campaign_id
        self.read_by = read_by or []
        self.schedule_change_metadata = schedule_change_metadata or {}

    @property
    def is_emergency(self) -> bool:
        return self.priority == PRIORITY_EMERGENCY or self.category == CATEGORY_EMERGENCY

    def to_dict(self, current_user_id: Optional[int] = None) -> Dict[str, Any]:
        """Serialize announcement with optional is_read flag for a specific student."""
        is_read = False
        if current_user_id is not None:
            is_read = int(current_user_id) in self.read_by

        return {
            "id": self.id,
            "title": self.title,
            "message": self.message,
            "category": self.category,
            "priority": self.priority,
            "status": self.status,
            "target_type": self.target_type,
            "target_route": self.target_route,
            "target_bus": self.target_bus,
            "target_student_ids": self.target_student_ids,
            "channels": self.channels,
            "created_by": self.created_by,
            "created_by_name": self.created_by_name,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "published_at": self.published_at.isoformat() if self.published_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
            "recipient_count": self.recipient_count,
            "in_app_count": self.in_app_count,
            "sms_campaign_id": self.sms_campaign_id,
            "read_count": len(self.read_by),
            "is_read": is_read,
            "is_emergency": self.is_emergency,
            "schedule_change_metadata": self.schedule_change_metadata,
        }

    @classmethod
    def from_mongo(cls, doc: Dict[str, Any]) -> "Announcement":
        if not doc:
            raise ValueError("Document cannot be empty")

        def _to_utc(val: Any) -> Optional[datetime]:
            if val is None:
                return None
            if isinstance(val, datetime):
                return val if val.tzinfo else val.replace(tzinfo=timezone.utc)
            if isinstance(val, str):
                try:
                    dt = datetime.fromisoformat(val.replace("Z", "+00:00"))
                    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
                except Exception:
                    return None
            return None

        return cls(
            id=int(doc.get("_id", doc.get("id", 0))),
            title=doc.get("title", ""),
            message=doc.get("message", ""),
            category=doc.get("category", CATEGORY_GENERAL),
            priority=doc.get("priority", PRIORITY_NORMAL),
            status=doc.get("status", STATUS_DRAFT),
            target_type=doc.get("target_type", TARGET_ALL_ACTIVE),
            target_route=doc.get("target_route"),
            target_bus=doc.get("target_bus"),
            target_student_ids=doc.get("target_student_ids", []),
            channels=doc.get("channels", ["in_app"]),
            created_by=doc.get("created_by", 0),
            created_by_name=doc.get("created_by_name", "Admin"),
            created_at=_to_utc(doc.get("created_at")),
            published_at=_to_utc(doc.get("published_at")),
            updated_at=_to_utc(doc.get("updated_at")),
            recipient_count=int(doc.get("recipient_count", 0)),
            in_app_count=int(doc.get("in_app_count", 0)),
            sms_campaign_id=doc.get("sms_campaign_id"),
            read_by=doc.get("read_by", []),
            schedule_change_metadata=doc.get("schedule_change_metadata", {}),
        )

    def save(self) -> int:
        db = get_db()
        self.updated_at = datetime.now(timezone.utc)

        if not self.id:
            self.id = get_next_sequence(COLLECTION_NAME)
            if self.status == STATUS_PUBLISHED and not self.published_at:
                self.published_at = self.updated_at

            doc = {
                "_id": self.id,
                "id": self.id,
                "title": self.title,
                "message": self.message,
                "category": self.category,
                "priority": self.priority,
                "status": self.status,
                "target_type": self.target_type,
                "target_route": self.target_route,
                "target_bus": self.target_bus,
                "target_student_ids": self.target_student_ids,
                "channels": self.channels,
                "created_by": self.created_by,
                "created_by_name": self.created_by_name,
                "created_at": self.created_at,
                "published_at": self.published_at,
                "updated_at": self.updated_at,
                "recipient_count": self.recipient_count,
                "in_app_count": self.in_app_count,
                "sms_campaign_id": self.sms_campaign_id,
                "read_by": self.read_by,
                "schedule_change_metadata": self.schedule_change_metadata,
            }
            db[COLLECTION_NAME].insert_one(doc)
        else:
            if self.status == STATUS_PUBLISHED and not self.published_at:
                self.published_at = self.updated_at

            db[COLLECTION_NAME].update_one(
                {"_id": self.id},
                {
                    "$set": {
                        "title": self.title,
                        "message": self.message,
                        "category": self.category,
                        "priority": self.priority,
                        "status": self.status,
                        "target_type": self.target_type,
                        "target_route": self.target_route,
                        "target_bus": self.target_bus,
                        "target_student_ids": self.target_student_ids,
                        "channels": self.channels,
                        "created_by_name": self.created_by_name,
                        "published_at": self.published_at,
                        "updated_at": self.updated_at,
                        "recipient_count": self.recipient_count,
                        "in_app_count": self.in_app_count,
                        "sms_campaign_id": self.sms_campaign_id,
                        "read_by": self.read_by,
                        "schedule_change_metadata": self.schedule_change_metadata,
                    }
                },
            )
        return self.id

    def delete(self) -> bool:
        """Delete announcement from database."""
        if not self.id:
            return False
        db = get_db()
        res = db[COLLECTION_NAME].delete_one({"_id": self.id})
        return res.deleted_count > 0

    def mark_as_read(self, user_id: int) -> bool:
        """Mark this announcement as read for the given user/student."""
        uid = int(user_id)
        if uid in self.read_by:
            return True
        self.read_by.append(uid)
        db = get_db()
        db[COLLECTION_NAME].update_one(
            {"_id": self.id},
            {"$addToSet": {"read_by": uid}}
        )
        return True

    @classmethod
    def find_by_id(cls, announcement_id: int) -> Optional["Announcement"]:
        db = get_db()
        doc = db[COLLECTION_NAME].find_one({"_id": int(announcement_id)})
        return cls.from_mongo(doc) if doc else None

    @classmethod
    def find_all(
        cls,
        status: Optional[str] = None,
        category: Optional[str] = None,
        priority: Optional[str] = None,
        limit: int = 100,
    ) -> List["Announcement"]:
        db = get_db()
        query: Dict[str, Any] = {}
        if status and status != "all":
            query["status"] = status
        if category:
            query["category"] = category
        if priority:
            query["priority"] = priority

        docs = list(db[COLLECTION_NAME].find(query).sort("created_at", -1).limit(limit))
        return [cls.from_mongo(d) for d in docs]

    @classmethod
    def find_for_student(
        cls,
        route_name: Optional[str] = None,
        bus_number: Optional[str] = None,
        student_id: Optional[int] = None,
        limit: int = 50,
    ) -> List["Announcement"]:
        """
        Query published announcements relevant to a student:
          - target_type == 'all_active'
          - target_type == 'route' and target_route == student.route_name
          - target_type == 'bus' and target_bus == student.bus_number
          - target_type == 'selected' and student_id in target_student_ids
        Returns Emergency notices sorted first, then by published_at descending.
        """
        db = get_db()
        conditions: List[Dict[str, Any]] = [{"target_type": TARGET_ALL_ACTIVE}]

        if route_name:
            conditions.append({"target_type": TARGET_ROUTE, "target_route": route_name})
        if bus_number:
            conditions.append({"target_type": TARGET_BUS, "target_bus": bus_number.upper()})
        if student_id:
            conditions.append({"target_type": TARGET_SELECTED, "target_student_ids": int(student_id)})

        query = {
            "status": STATUS_PUBLISHED,
            "$or": conditions,
        }

        docs = list(db[COLLECTION_NAME].find(query))
        announcements = [cls.from_mongo(d) for d in docs]

        # Sort: Emergency first (True before False), then published_at descending
        def sort_key(a: "Announcement"):
            is_em = 0 if a.is_emergency else 1
            pub_ts = a.published_at.timestamp() if a.published_at else 0.0
            return (is_em, -pub_ts)

        announcements.sort(key=sort_key)
        return announcements[:limit]
