"""
models/master_stop.py — PyMongo-backed MasterStop document model.

Collection: master_stops
Document shape (from live Atlas inspection):
  _id:              int
  id:               int  (mirror of _id)
  standard_name_en: str
  standard_name_ta: str | None
  aliases:          str | None  (JSON string array e.g. '["Thirunagar", "திருநகர்"]')
  latitude:         Decimal128 | float | None
  longitude:        Decimal128 | float | None
  created_at:       datetime (UTC)
"""

import json
import re
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


def _doc_to_obj(doc: dict) -> "MasterStop":
    m = MasterStop.__new__(MasterStop)
    m._doc = doc
    return m


class MasterStop:
    def __init__(
        self,
        standard_name_en: str,
        standard_name_ta: str | None = None,
        aliases: str | list | None = None,
        latitude: float | None = None,
        longitude: float | None = None,
        created_at: datetime | None = None,
    ):
        if isinstance(aliases, list):
            aliases_str = json.dumps(aliases, ensure_ascii=False)
        else:
            aliases_str = aliases

        self._doc = {
            "standard_name_en": standard_name_en[:200] if standard_name_en else "",
            "standard_name_ta": standard_name_ta[:200] if standard_name_ta else None,
            "aliases": aliases_str,
            "latitude": Decimal128(str(latitude)) if latitude is not None else None,
            "longitude": Decimal128(str(longitude)) if longitude is not None else None,
            "created_at": created_at or datetime.utcnow(),
        }

    @property
    def id(self) -> int:
        return int(self._doc.get("_id", self._doc.get("id", 0)))

    @property
    def standard_name_en(self) -> str:
        return self._doc.get("standard_name_en", "")

    @property
    def standard_name_ta(self) -> str | None:
        return self._doc.get("standard_name_ta")

    @property
    def aliases(self) -> str | None:
        return self._doc.get("aliases")

    @property
    def latitude(self) -> float | None:
        return _to_float(self._doc.get("latitude"))

    @property
    def longitude(self) -> float | None:
        return _to_float(self._doc.get("longitude"))

    @property
    def created_at(self) -> datetime | None:
        return self._doc.get("created_at")

    def to_dict(self) -> dict:
        aliases_list = []
        raw_aliases = self._doc.get("aliases")
        if raw_aliases:
            if isinstance(raw_aliases, list):
                aliases_list = raw_aliases
            elif isinstance(raw_aliases, str):
                try:
                    parsed = json.loads(raw_aliases)
                    aliases_list = parsed if isinstance(parsed, list) else [raw_aliases]
                except Exception:
                    aliases_list = [raw_aliases]

        return {
            "id": self.id,
            "standard_name_en": self.standard_name_en,
            "standard_name_ta": self.standard_name_ta,
            "aliases": aliases_list,
            "latitude": self.latitude,
            "longitude": self.longitude,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }

    def save(self) -> "MasterStop":
        db = get_db()
        if "_id" not in self._doc:
            new_id = get_next_sequence("master_stops")
            self._doc["_id"] = new_id
            self._doc["id"] = new_id
            db["master_stops"].insert_one(self._doc)
        else:
            update_fields = {k: v for k, v in self._doc.items() if k != "_id"}
            db["master_stops"].update_one({"_id": self._doc["_id"]}, {"$set": update_fields})
        return self

    @classmethod
    def find_by_id(cls, stop_id: int) -> "MasterStop | None":
        doc = get_db()["master_stops"].find_one({"_id": int(stop_id)})
        return _doc_to_obj(doc) if doc else None

    @classmethod
    def search(cls, query_str: str, limit: int = 15) -> list["MasterStop"]:
        """Bilingual search across English and Tamil names and JSON aliases."""
        term = query_str.strip()
        if not term:
            docs = get_db()["master_stops"].find().sort("standard_name_en", 1).limit(limit)
            return [_doc_to_obj(d) for d in docs]

        pattern = re.compile(re.escape(term), re.IGNORECASE)
        filter_query = {
            "$or": [
                {"standard_name_en": pattern},
                {"standard_name_ta": pattern},
                {"aliases": pattern},
            ]
        }
        docs = get_db()["master_stops"].find(filter_query).sort("standard_name_en", 1).limit(limit)
        return [_doc_to_obj(d) for d in docs]
