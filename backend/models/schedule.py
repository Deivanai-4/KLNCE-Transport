"""
models/schedule.py — PyMongo-backed ScheduleDocument document model.

Collection: schedule_documents
Document shape (from live Atlas inspection):
  _id:            int
  id:             int  (mirror of _id)
  title:          str
  file_url:       str
  file_type:      str  — 'image' | 'pdf'
  trip_direction: str  — 'incoming' | 'outgoing'
  college:        str  — 'engineering' | 'arts_science' | 'both'
  effective_date: str  — 'YYYY-MM-DD' (strictly preserved as ISO string)
  status:         str  — 'draft' | 'verified' | 'published' | 'archived'
  created_by:     int  (FK → users._id)
  verified_by:    int | None  (FK → users._id)
  verified_at:    datetime | None
  published_at:   datetime | None
  created_at:     datetime (UTC)
"""

from datetime import date, datetime
from models.database import get_db, get_next_sequence
from services.schedule_visibility import active_trip_at


def _format_date(val) -> str | None:
    if val is None:
        return None
    if isinstance(val, (datetime, date)):
        return val.strftime("%Y-%m-%d")
    return str(val)


def _doc_to_obj(doc: dict) -> "ScheduleDocument":
    s = ScheduleDocument.__new__(ScheduleDocument)
    s._doc = doc
    return s


class ScheduleDocument:
    def __init__(
        self,
        title: str,
        file_url: str = "",
        file_type: str = "image",
        trip_direction: str = "incoming",
        college: str = "both",
        effective_date: str | date | datetime | None = None,
        status: str = "draft",
        created_by: int = 1,
        verified_by: int | None = None,
        verified_at: datetime | None = None,
        published_at: datetime | None = None,
        created_at: datetime | None = None,
    ):
        self._doc = {
            "title": title[:200] if title else "",
            "file_url": file_url or "",
            "file_type": file_type,
            "trip_direction": trip_direction,
            "college": college,
            "effective_date": _format_date(effective_date) or datetime.utcnow().strftime("%Y-%m-%d"),
            "status": status,
            "created_by": int(created_by),
            "verified_by": int(verified_by) if verified_by is not None else None,
            "verified_at": verified_at,
            "published_at": published_at,
            "created_at": created_at or datetime.utcnow(),
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
    def file_url(self) -> str:
        return self._doc.get("file_url", "")

    @file_url.setter
    def file_url(self, v: str):
        self._doc["file_url"] = v or ""

    @property
    def file_type(self) -> str:
        return self._doc.get("file_type", "image")

    @property
    def trip_direction(self) -> str:
        return self._doc.get("trip_direction", "incoming")

    @trip_direction.setter
    def trip_direction(self, v: str):
        self._doc["trip_direction"] = v

    @property
    def college(self) -> str:
        return self._doc.get("college", "both")

    @college.setter
    def college(self, v: str):
        self._doc["college"] = v

    @property
    def effective_date(self) -> str:
        return _format_date(self._doc.get("effective_date")) or ""

    @effective_date.setter
    def effective_date(self, v):
        self._doc["effective_date"] = _format_date(v)

    @property
    def status(self) -> str:
        return self._doc.get("status", "draft")

    @status.setter
    def status(self, v: str):
        self._doc["status"] = v

    @property
    def created_by(self) -> int:
        return self._doc.get("created_by", 0)

    @property
    def verified_by(self) -> int | None:
        return self._doc.get("verified_by")

    @verified_by.setter
    def verified_by(self, v: int | None):
        self._doc["verified_by"] = int(v) if v is not None else None

    @property
    def verified_at(self) -> datetime | None:
        return self._doc.get("verified_at")

    @verified_at.setter
    def verified_at(self, v: datetime | None):
        self._doc["verified_at"] = v

    @property
    def published_at(self) -> datetime | None:
        return self._doc.get("published_at")

    @published_at.setter
    def published_at(self, v: datetime | None):
        self._doc["published_at"] = v

    @property
    def created_at(self) -> datetime | None:
        return self._doc.get("created_at")

    def to_dict(self, include_routes: bool = False) -> dict:
        from models.bus_route import BusRoute
        routes_count = get_db()["bus_routes"].count_documents({"schedule_id": self.id})
        data = {
            "id": self.id,
            "title": self.title,
            "file_url": self.file_url,
            "file_type": self.file_type,
            "trip_direction": self.trip_direction,
            "college": self.college,
            "effective_date": self.effective_date,
            "status": self.status,
            "created_by": self.created_by,
            "verified_by": self.verified_by,
            "verified_at": self.verified_at.isoformat() if self.verified_at else None,
            "published_at": self.published_at.isoformat() if self.published_at else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "routes_count": routes_count,
        }
        if include_routes:
            db = get_db()
            route_docs = list(db["bus_routes"].find({"schedule_id": self.id}).sort("display_order", 1))
            route_ids = [r["_id"] for r in route_docs]
            stop_docs = list(db["route_stops"].find({"bus_route_id": {"$in": route_ids}}).sort("stop_order", 1))

            from models.route_stop import _doc_to_obj as _stop_to_obj
            stops_by_route = {}
            for s in stop_docs:
                stops_by_route.setdefault(s["bus_route_id"], []).append(_stop_to_obj(s).to_dict())

            bus_routes = []
            for r in route_docs:
                r_dict = {
                    "id": r["_id"],
                    "schedule_id": r.get("schedule_id", self.id),
                    "bus_code": r.get("bus_code", ""),
                    "route_display_name": r.get("route_display_name"),
                    "departure_time": r.get("departure_time"),
                    "college": r.get("college", "engineering"),
                    "display_order": r.get("display_order", 0),
                    "created_at": r["created_at"].isoformat() if isinstance(r.get("created_at"), datetime) else str(r.get("created_at", "")),
                    "stops": stops_by_route.get(r["_id"], []),
                }
                bus_routes.append(r_dict)
            data["bus_routes"] = bus_routes
        return data

    def save(self) -> "ScheduleDocument":
        db = get_db()
        if "_id" not in self._doc:
            new_id = get_next_sequence("schedule_documents")
            self._doc["_id"] = new_id
            self._doc["id"] = new_id
            db["schedule_documents"].insert_one(self._doc)
        else:
            update_fields = {k: v for k, v in self._doc.items() if k != "_id"}
            db["schedule_documents"].update_one({"_id": self._doc["_id"]}, {"$set": update_fields})
        return self

    def delete(self) -> None:
        """Cascading delete: delete schedule, associated bus_routes and route_stops."""
        db = get_db()
        if "_id" in self._doc:
            sched_id = self._doc["_id"]
            # Find routes for this schedule
            routes = list(db["bus_routes"].find({"schedule_id": sched_id}, {"_id": 1}))
            route_ids = [r["_id"] for r in routes]
            if route_ids:
                db["route_stops"].delete_many({"bus_route_id": {"$in": route_ids}})
            db["bus_routes"].delete_many({"schedule_id": sched_id})
            db["schedule_documents"].delete_one({"_id": sched_id})

    @classmethod
    def find_by_id(cls, schedule_id: int) -> "ScheduleDocument | None":
        doc = get_db()["schedule_documents"].find_one({"_id": int(schedule_id)})
        return _doc_to_obj(doc) if doc else None

    @classmethod
    def get_published(
        cls,
        trip_direction: str = None,
        college: str = None,
        now: datetime = None,
    ) -> "ScheduleDocument | None":
        active_trip = active_trip_at(now)
        if active_trip is None:
            return None
        if trip_direction is None:
            trip_direction = active_trip
        elif trip_direction != active_trip:
            return None

        query = {
            "status": "published",
            "trip_direction": trip_direction,
        }
        if college and college != "both":
            query["college"] = {"$in": [college, "both"]}

        doc = get_db()["schedule_documents"].find_one(
            query,
            sort=[("effective_date", -1)]
        )
        return _doc_to_obj(doc) if doc else None

    @classmethod
    def get_drafts(cls) -> list["ScheduleDocument"]:
        docs = get_db()["schedule_documents"].find(
            {"status": {"$in": ["draft", "verified"]}}
        ).sort("created_at", -1)
        return [_doc_to_obj(d) for d in docs]
