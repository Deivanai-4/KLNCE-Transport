"""
models/gps_location.py — PyMongo-backed GpsLocation document model.

Collection: gps_locations
Document shape (from live Atlas inspection):
  _id:            int
  id:             int  (mirror of _id)
  bus_code:       str
  driver_id:      int  (FK → users._id)
  latitude:       Decimal128 | float
  longitude:      Decimal128 | float
  speed_kmh:      Decimal128 | float | None
  is_active_trip: int  (1 or 0)
  recorded_at:    datetime (UTC)
"""

from datetime import datetime
from bson.decimal128 import Decimal128
from models.database import get_db, get_next_sequence


def _to_float(val):
    if val is None:
        return None
    if isinstance(val, Decimal128):
        return float(val.to_decimal())
    try:
        return float(val)
    except (ValueError, TypeError):
        return None


def _doc_to_obj(doc: dict) -> "GpsLocation":
    g = GpsLocation.__new__(GpsLocation)
    g._doc = doc
    return g


class GpsLocation:
    def __init__(
        self,
        bus_code: str,
        driver_id: int,
        latitude: float,
        longitude: float,
        speed_kmh: float = 0.0,
        is_active_trip: bool = True,
        recorded_at: datetime | None = None,
    ):
        self._doc = {
            "bus_code": bus_code.strip().upper() if bus_code else "",
            "driver_id": int(driver_id),
            "latitude": Decimal128(str(latitude)) if latitude is not None else None,
            "longitude": Decimal128(str(longitude)) if longitude is not None else None,
            "speed_kmh": Decimal128(str(speed_kmh)) if speed_kmh is not None else None,
            "is_active_trip": 1 if is_active_trip else 0,
            "recorded_at": recorded_at or datetime.utcnow(),
        }

    @property
    def id(self) -> int:
        return int(self._doc.get("_id", self._doc.get("id", 0)))

    @property
    def bus_code(self) -> str:
        return self._doc.get("bus_code", "")

    @property
    def driver_id(self) -> int:
        return self._doc.get("driver_id", 0)

    @property
    def latitude(self) -> float | None:
        return _to_float(self._doc.get("latitude"))

    @property
    def longitude(self) -> float | None:
        return _to_float(self._doc.get("longitude"))

    @property
    def speed_kmh(self) -> float | None:
        return _to_float(self._doc.get("speed_kmh"))

    @property
    def is_active_trip(self) -> bool:
        return bool(self._doc.get("is_active_trip", 1))

    @is_active_trip.setter
    def is_active_trip(self, v: bool):
        self._doc["is_active_trip"] = 1 if v else 0

    @property
    def recorded_at(self) -> datetime | None:
        return self._doc.get("recorded_at")

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "bus_code": self.bus_code,
            "driver_id": self.driver_id,
            "latitude": self.latitude,
            "longitude": self.longitude,
            "speed_kmh": self.speed_kmh,
            "is_active_trip": self.is_active_trip,
            "recorded_at": self.recorded_at.isoformat() if self.recorded_at else None,
        }

    def save(self) -> "GpsLocation":
        db = get_db()
        if "_id" not in self._doc:
            new_id = get_next_sequence("gps_locations")
            self._doc["_id"] = new_id
            self._doc["id"] = new_id
            db["gps_locations"].insert_one(self._doc)
        else:
            update_fields = {k: v for k, v in self._doc.items() if k != "_id"}
            db["gps_locations"].update_one({"_id": self._doc["_id"]}, {"$set": update_fields})
        return self

    @classmethod
    def get_latest_for_bus(cls, bus_code: str) -> "GpsLocation | None":
        code = bus_code.strip().upper()
        doc = get_db()["gps_locations"].find_one(
            {"bus_code": code, "is_active_trip": {"$in": [1, True]}},
            sort=[("recorded_at", -1)]
        )
        return _doc_to_obj(doc) if doc else None

    @classmethod
    def get_active_buses(cls) -> list["GpsLocation"]:
        """Returns the most recent active location for each active bus via aggregation."""
        pipeline = [
            {"$match": {"is_active_trip": {"$in": [1, True]}}},
            {"$sort": {"recorded_at": -1}},
            {"$group": {
                "_id": "$bus_code",
                "latest_doc": {"$first": "$$ROOT"}
            }},
            {"$replaceRoot": {"newRoot": "$latest_doc"}}
        ]
        docs = list(get_db()["gps_locations"].aggregate(pipeline))
        return [_doc_to_obj(d) for d in docs]
