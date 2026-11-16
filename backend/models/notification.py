"""
models/notification.py — PyMongo-backed Notification document model.

Collection: notifications
Document shape:
  _id:             int
  id:              int  (mirror of _id)
  title:           str
  body:            str
  type:            str  — 'schedule_update' | 'delay' | 'route_change' | 'holiday' | 'general'
  sent_by:         int  (FK → users._id)
  sent_at:         datetime (UTC)
  recipient_count: int
"""

from datetime import datetime
from models.database import get_db, get_next_sequence


def _doc_to_obj(doc: dict) -> "Notification":
    n = Notification.__new__(Notification)
    n._doc = doc
    return n


class Notification:
    def __init__(
        self,
        title: str,
        body: str,
        sent_by: int,
        type: str = "general",
        recipient_count: int = 0,
        sent_at: datetime | None = None,
    ):
        self._doc = {
            "title": title[:200] if title else "",
            "body": body or "",
            "type": type,
            "sent_by": int(sent_by),
            "recipient_count": int(recipient_count),
            "sent_at": sent_at or datetime.utcnow(),
        }

    @property
    def id(self) -> int:
        return int(self._doc.get("_id", self._doc.get("id", 0)))

    @property
    def title(self) -> str:
        return self._doc.get("title", "")

    @title.setter
    def title(self, v: str):
        self._doc["title"] = v[:200] if v else ""

    @property
    def body(self) -> str:
        return self._doc.get("body", "")

    @body.setter
    def body(self, v: str):
        self._doc["body"] = v or ""

    @property
    def type(self) -> str:
        return self._doc.get("type", "general")

    @property
    def sent_by(self) -> int:
        return self._doc.get("sent_by", 0)

    @property
    def sent_at(self) -> datetime | None:
        return self._doc.get("sent_at")

    @property
    def recipient_count(self) -> int:
        return self._doc.get("recipient_count", 0)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "title": self.title,
            "body": self.body,
            "type": self.type,
            "sent_by": self.sent_by,
            "sent_at": self.sent_at.isoformat() if self.sent_at else None,
            "recipient_count": self.recipient_count,
        }

    def save(self) -> "Notification":
        db = get_db()
        if "_id" not in self._doc:
            new_id = get_next_sequence("notifications")
            self._doc["_id"] = new_id
            self._doc["id"] = new_id
            db["notifications"].insert_one(self._doc)
        else:
            update_fields = {k: v for k, v in self._doc.items() if k != "_id"}
            db["notifications"].update_one({"_id": self._doc["_id"]}, {"$set": update_fields})
        return self

    def delete(self) -> None:
        if "_id" in self._doc:
            get_db()["notifications"].delete_one({"_id": self._doc["_id"]})

    @classmethod
    def find_by_id(cls, notification_id: int) -> "Notification | None":
        doc = get_db()["notifications"].find_one({"_id": int(notification_id)})
        return _doc_to_obj(doc) if doc else None

    @classmethod
    def get_history(cls, limit: int = 30) -> list["Notification"]:
        docs = get_db()["notifications"].find().sort("sent_at", -1).limit(limit)
        return [_doc_to_obj(d) for d in docs]
