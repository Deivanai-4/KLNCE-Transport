"""
models/bus_route.py — PyMongo-backed BusRoute document model.

Collection: bus_routes
Document shape (from live Atlas inspection):
  _id:                int
  id:                 int  (mirror of _id)
  schedule_id:        int  (FK → schedule_documents._id)
  bus_code:           str
  route_display_name: str | None
  departure_time:     str | None  (e.g. '08:00')
  college:            str  — 'engineering' | 'arts_science' | 'both'
  display_order:      int
  created_at:         datetime (UTC)
"""

from datetime import datetime
from models.database import get_db, get_next_sequence


def _doc_to_obj(doc: dict) -> "BusRoute":
    b = BusRoute.__new__(BusRoute)
    b._doc = doc
    return b


class BusRoute:
    def __init__(
        self,
        schedule_id: int,
        bus_code: str,
        route_display_name: str | None = None,
        departure_time: str | None = None,
        college: str = "engineering",
        display_order: int = 0,
        created_at: datetime | None = None,
    ):
        self._doc = {
            "schedule_id": schedule_id,
            "bus_code": bus_code.strip().upper() if bus_code else "",
            "route_display_name": route_display_name or None,
            "departure_time": departure_time or None,
            "college": college,
            "display_order": display_order,
            "created_at": created_at or datetime.utcnow(),
        }

    # ------------------------------------------------------------------ #
    # Properties                                                           #
    # ------------------------------------------------------------------ #
    @property
    def id(self) -> int:
        return int(self._doc.get("_id", self._doc.get("id", 0)))

    @property
    def schedule_id(self) -> int:
        return self._doc.get("schedule_id", 0)

    @property
    def bus_code(self) -> str:
        return self._doc.get("bus_code", "")

    @property
    def route_display_name(self) -> str | None:
        return self._doc.get("route_display_name")

    @property
    def departure_time(self) -> str | None:
        return self._doc.get("departure_time")

    @property
    def college(self) -> str:
        return self._doc.get("college", "engineering")

    @property
    def display_order(self) -> int:
        return self._doc.get("display_order", 0)

    @property
    def created_at(self) -> datetime | None:
        return self._doc.get("created_at")

    # ------------------------------------------------------------------ #
    # Serialisation                                                        #
    # ------------------------------------------------------------------ #
    def to_dict(self, include_stops: bool = True) -> dict:
        from models.route_stop import RouteStop
        data = {
            "id": self.id,
            "schedule_id": self.schedule_id,
            "bus_code": self.bus_code,
            "route_display_name": self.route_display_name,
            "departure_time": self.departure_time,
            "college": self.college,
            "display_order": self.display_order,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
        if include_stops:
            stops = RouteStop.find_by_route(self.id)
            data["stops"] = [s.to_dict() for s in stops]
        return data

    # ------------------------------------------------------------------ #
    # Persistence                                                          #
    # ------------------------------------------------------------------ #
    def save(self) -> "BusRoute":
        db = get_db()
        if "_id" not in self._doc:
            new_id = get_next_sequence("bus_routes")
            self._doc["_id"] = new_id
            self._doc["id"] = new_id
            db["bus_routes"].insert_one(self._doc)
        else:
            update_fields = {k: v for k, v in self._doc.items() if k != "_id"}
            db["bus_routes"].update_one({"_id": self._doc["_id"]}, {"$set": update_fields})
        return self

    # ------------------------------------------------------------------ #
    # Queries                                                              #
    # ------------------------------------------------------------------ #
    @classmethod
    def find_by_schedule(cls, schedule_id: int) -> list["BusRoute"]:
        docs = get_db()["bus_routes"].find(
            {"schedule_id": schedule_id}
        ).sort("display_order", 1)
        return [_doc_to_obj(d) for d in docs]

    @classmethod
    def find_by_code(cls, schedule_id: int, bus_code: str) -> "BusRoute | None":
        doc = get_db()["bus_routes"].find_one({
            "schedule_id": schedule_id,
            "bus_code": bus_code.strip().upper(),
        })
        return _doc_to_obj(doc) if doc else None
