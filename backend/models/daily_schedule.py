"""
models/daily_schedule.py — PyMongo-backed DailySchedule document model.

Collection: daily_schedules
Document shape:
  _id:            int
  id:             int (mirror of _id)
  date:           str ('YYYY-MM-DD')
  session:        str ('morning' | 'afternoon')
  status:         str ('draft' | 'published')
  is_updated:     bool (indicates whether schedule was edited after publishing)
  version:        int (increments on publication revisions)
  created_by:     int (FK -> users._id)
  buses:          list of bus records:
    [
      {
        "bus_number": "S1",
        "route_id": 1,
        "route_name": "Route A",
        "departure_time": "07:00 AM",
        "stops": [
          {"stop_order": 1, "stop_name": "Arapalayam", "arrival_time": "07:00 AM"},
          {"stop_order": 2, "stop_name": "Periyar", "arrival_time": "07:15 AM"}
        ]
      }
    ]
  created_at:     datetime (UTC)
  updated_at:     datetime (UTC)
  published_at:   datetime | None (UTC)
"""

from datetime import datetime, date
from models.database import get_db, get_next_sequence


def _format_date(val) -> str:
    if isinstance(val, (datetime, date)):
        return val.strftime("%Y-%m-%d")
    return str(val).strip()


def _doc_to_obj(doc: dict) -> "DailySchedule":
    ds = DailySchedule.__new__(DailySchedule)
    ds._doc = doc
    return ds


class DailySchedule:
    def __init__(
        self,
        date: str | date | datetime,
        session: str = "morning",
        status: str = "draft",
        is_updated: bool = False,
        version: int = 1,
        created_by: int = 1,
        buses: list | None = None,
        created_at: datetime | None = None,
        updated_at: datetime | None = None,
        published_at: datetime | None = None,
    ):
        now_utc = datetime.utcnow()
        self._doc = {
            "date": _format_date(date),
            "session": session.lower().strip() if isinstance(session, str) else "morning",
            "status": status.lower().strip() if isinstance(status, str) else "draft",
            "is_updated": bool(is_updated),
            "version": int(version),
            "created_by": int(created_by),
            "buses": buses or [],
            "update_summary": "",
            "pending_sms_alert": False,
            "created_at": created_at or now_utc,
            "updated_at": updated_at or now_utc,
            "published_at": published_at,
        }

    @property
    def id(self) -> int:
        return int(self._doc.get("_id", self._doc.get("id", 0)))

    @property
    def date(self) -> str:
        return self._doc.get("date", "")

    @date.setter
    def date(self, v):
        self._doc["date"] = _format_date(v)

    @property
    def session(self) -> str:
        return self._doc.get("session", "morning")

    @session.setter
    def session(self, v: str):
        self._doc["session"] = v.lower().strip()

    @property
    def status(self) -> str:
        return self._doc.get("status", "draft")

    @status.setter
    def status(self, v: str):
        self._doc["status"] = v.lower().strip()

    @property
    def is_updated(self) -> bool:
        return bool(self._doc.get("is_updated", False))

    @is_updated.setter
    def is_updated(self, v: bool):
        self._doc["is_updated"] = bool(v)

    @property
    def version(self) -> int:
        return int(self._doc.get("version", 1))

    @version.setter
    def version(self, v: int):
        self._doc["version"] = int(v)

    @property
    def created_by(self) -> int:
        return int(self._doc.get("created_by", 0))

    @property
    def buses(self) -> list:
        return self._doc.get("buses", [])

    @buses.setter
    def buses(self, v: list):
        self._doc["buses"] = v or []

    @property
    def created_at(self) -> datetime | None:
        return self._doc.get("created_at")

    @property
    def updated_at(self) -> datetime | None:
        return self._doc.get("updated_at")

    @updated_at.setter
    def updated_at(self, v: datetime | None):
        self._doc["updated_at"] = v

    @property
    def published_at(self) -> datetime | None:
        return self._doc.get("published_at")

    @published_at.setter
    def published_at(self, v: datetime | None):
        self._doc["published_at"] = v

    @property
    def update_summary(self) -> str:
        return self._doc.get("update_summary", "")

    @update_summary.setter
    def update_summary(self, v: str):
        self._doc["update_summary"] = str(v) if v else ""

    @property
    def pending_sms_alert(self) -> bool:
        return bool(self._doc.get("pending_sms_alert", False))

    @pending_sms_alert.setter
    def pending_sms_alert(self, v: bool):
        self._doc["pending_sms_alert"] = bool(v)

    def to_dict(self) -> dict:
        created_str = self.created_at.isoformat() if isinstance(self.created_at, datetime) else self.created_at
        updated_str = self.updated_at.isoformat() if isinstance(self.updated_at, datetime) else self.updated_at
        published_str = self.published_at.isoformat() if isinstance(self.published_at, datetime) else self.published_at

        return {
            "id": self.id,
            "date": self.date,
            "session": self.session,
            "status": self.status,
            "is_updated": self.is_updated,
            "version": self.version,
            "created_by": self.created_by,
            "buses": self.buses,
            "buses_count": len(self.buses),
            "update_summary": self.update_summary,
            "pending_sms_alert": self.pending_sms_alert,
            "created_at": created_str,
            "updated_at": updated_str,
            "published_at": published_str,
        }

    def save(self) -> "DailySchedule":
        db = get_db()
        self._doc["updated_at"] = datetime.utcnow()
        if "_id" not in self._doc:
            new_id = get_next_sequence("daily_schedules")
            self._doc["_id"] = new_id
            self._doc["id"] = new_id
            db["daily_schedules"].insert_one(self._doc)
        else:
            update_fields = {k: v for k, v in self._doc.items() if k != "_id"}
            db["daily_schedules"].update_one({"_id": self._doc["_id"]}, {"$set": update_fields})
        return self

    def delete(self) -> None:
        db = get_db()
        if "_id" in self._doc:
            db["daily_schedules"].delete_one({"_id": self._doc["_id"]})

    @classmethod
    def find_by_id(cls, schedule_id: int) -> "DailySchedule | None":
        doc = get_db()["daily_schedules"].find_one({"_id": int(schedule_id)})
        return _doc_to_obj(doc) if doc else None

    @classmethod
    def find_by_date_and_session(cls, date_str: str, session: str) -> "DailySchedule | None":
        doc = get_db()["daily_schedules"].find_one({
            "date": _format_date(date_str),
            "session": session.lower().strip()
        })
        return _doc_to_obj(doc) if doc else None

    @classmethod
    def list_schedules(
        cls,
        date_str: str | None = None,
        session: str | None = None,
        status: str | None = None,
        bus_number: str | None = None,
        limit: int = 50
    ) -> list["DailySchedule"]:
        query = {}
        if date_str:
            query["date"] = _format_date(date_str)
        if session:
            query["session"] = session.lower().strip()
        if status:
            query["status"] = status.lower().strip()
        if bus_number:
            query["buses.bus_number"] = bus_number.strip().upper()

        docs = get_db()["daily_schedules"].find(query).sort([("date", -1), ("session", 1)]).limit(limit)
        return [_doc_to_obj(d) for d in docs]
