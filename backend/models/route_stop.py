"""
models/route_stop.py — PyMongo-backed RouteStop document model.

Collection: route_stops
Document shape (from live Atlas inspection):
  _id:                    int
  id:                     int  (mirror of _id)
  bus_route_id:           int  (FK → bus_routes._id)
  stop_order:             int
  stop_name_en:           str
  stop_name_ta:           str | None
  estimated_arrival_time: str | None
  master_stop_id:         int | None
"""

from models.database import get_db, get_next_sequence


def _doc_to_obj(doc: dict) -> "RouteStop":
    s = RouteStop.__new__(RouteStop)
    s._doc = doc
    return s


class RouteStop:
    def __init__(
        self,
        bus_route_id: int,
        stop_order: int,
        stop_name_en: str,
        stop_name_ta: str | None = None,
        estimated_arrival_time: str | None = None,
        master_stop_id: int | None = None,
    ):
        self._doc = {
            "bus_route_id": bus_route_id,
            "stop_order": stop_order,
            "stop_name_en": stop_name_en[:200] if stop_name_en else "",
            "stop_name_ta": stop_name_ta[:200] if stop_name_ta else None,
            "estimated_arrival_time": estimated_arrival_time,
            "master_stop_id": master_stop_id,
        }

    @property
    def id(self) -> int:
        return int(self._doc.get("_id", self._doc.get("id", 0)))

    @property
    def bus_route_id(self) -> int:
        return self._doc.get("bus_route_id", 0)

    @property
    def stop_order(self) -> int:
        return self._doc.get("stop_order", 0)

    @property
    def stop_name_en(self) -> str:
        return self._doc.get("stop_name_en", "")

    @property
    def stop_name_ta(self) -> str | None:
        return self._doc.get("stop_name_ta")

    @property
    def estimated_arrival_time(self) -> str | None:
        return self._doc.get("estimated_arrival_time")

    @property
    def master_stop_id(self) -> int | None:
        return self._doc.get("master_stop_id")

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "bus_route_id": self.bus_route_id,
            "stop_order": self.stop_order,
            "stop_name_en": self.stop_name_en,
            "stop_name_ta": self.stop_name_ta,
            "estimated_arrival_time": self.estimated_arrival_time,
            "master_stop_id": self.master_stop_id,
        }

    def save(self) -> "RouteStop":
        db = get_db()
        if "_id" not in self._doc:
            new_id = get_next_sequence("route_stops")
            self._doc["_id"] = new_id
            self._doc["id"] = new_id
            db["route_stops"].insert_one(self._doc)
        else:
            update_fields = {k: v for k, v in self._doc.items() if k != "_id"}
            db["route_stops"].update_one({"_id": self._doc["_id"]}, {"$set": update_fields})
        return self

    @classmethod
    def find_by_route(cls, bus_route_id: int) -> list["RouteStop"]:
        docs = get_db()["route_stops"].find(
            {"bus_route_id": bus_route_id}
        ).sort("stop_order", 1)
        return [_doc_to_obj(d) for d in docs]
