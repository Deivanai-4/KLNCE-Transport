"""
models/student.py — PyMongo-backed Student and Route Allocation document model.

Collection: students
Document shape:
  _id:                  int (auto-increment)
  id:                   int (mirror of _id)
  register_number:      str (unique index, uppercase, stripped)
  name:                 str
  department:           str
  year:                 str
  section:              str
  student_mobile:       str (clean 10-digit Indian mobile)
  parent_mobile:        str (optional 10-digit Indian mobile)
  route_name:           str (regular assigned route)
  bus_number:           str (regular assigned bus)
  boarding_stop:        str (boarding point)
  is_transport_active:  bool (transport registration status)
  created_at:           datetime (UTC)
  updated_at:           datetime (UTC)
"""

import re
from datetime import datetime
from models.database import get_db, get_next_sequence


def _clean_str(val) -> str:
    return str(val).strip() if val is not None else ""


def _doc_to_obj(doc: dict) -> "Student":
    s = Student.__new__(Student)
    s._doc = doc
    return s


class Student:
    """Student model representing transport-registered students."""

    def __init__(
        self,
        register_number: str,
        name: str,
        department: str,
        year: str,
        student_mobile: str,
        route_name: str,
        bus_number: str,
        boarding_stop: str,
        section: str = "",
        parent_mobile: str = "",
        is_transport_active: bool = True,
        created_at: datetime | None = None,
        updated_at: datetime | None = None,
    ):
        now_utc = datetime.utcnow()
        self._doc = {
            "register_number": _clean_str(register_number).upper(),
            "name": _clean_str(name),
            "department": _clean_str(department).upper(),
            "year": _clean_str(year).upper(),
            "section": _clean_str(section).upper(),
            "student_mobile": _clean_str(student_mobile),
            "parent_mobile": _clean_str(parent_mobile),
            "route_name": _clean_str(route_name),
            "bus_number": _clean_str(bus_number).upper(),
            "boarding_stop": _clean_str(boarding_stop),
            "is_transport_active": bool(is_transport_active),
            "created_at": created_at or now_utc,
            "updated_at": updated_at or now_utc,
        }

    # ------------------------------------------------------------------ #
    # Properties                                                         #
    # ------------------------------------------------------------------ #
    @property
    def id(self) -> int:
        return int(self._doc.get("_id", self._doc.get("id", 0)))

    @property
    def register_number(self) -> str:
        return self._doc.get("register_number", "")

    @register_number.setter
    def register_number(self, v: str):
        self._doc["register_number"] = _clean_str(v).upper()

    @property
    def name(self) -> str:
        return self._doc.get("name", "")

    @name.setter
    def name(self, v: str):
        self._doc["name"] = _clean_str(v)

    @property
    def department(self) -> str:
        return self._doc.get("department", "")

    @department.setter
    def department(self, v: str):
        self._doc["department"] = _clean_str(v).upper()

    @property
    def year(self) -> str:
        return self._doc.get("year", "")

    @year.setter
    def year(self, v: str):
        self._doc["year"] = _clean_str(v).upper()

    @property
    def section(self) -> str:
        return self._doc.get("section", "")

    @section.setter
    def section(self, v: str):
        self._doc["section"] = _clean_str(v).upper()

    @property
    def student_mobile(self) -> str:
        return self._doc.get("student_mobile", "")

    @student_mobile.setter
    def student_mobile(self, v: str):
        self._doc["student_mobile"] = _clean_str(v)

    @property
    def parent_mobile(self) -> str:
        return self._doc.get("parent_mobile", "")

    @parent_mobile.setter
    def parent_mobile(self, v: str):
        self._doc["parent_mobile"] = _clean_str(v)

    @property
    def route_name(self) -> str:
        return self._doc.get("route_name", "")

    @route_name.setter
    def route_name(self, v: str):
        self._doc["route_name"] = _clean_str(v)

    @property
    def bus_number(self) -> str:
        return self._doc.get("bus_number", "")

    @bus_number.setter
    def bus_number(self, v: str):
        self._doc["bus_number"] = _clean_str(v).upper()

    @property
    def boarding_stop(self) -> str:
        return self._doc.get("boarding_stop", "")

    @boarding_stop.setter
    def boarding_stop(self, v: str):
        self._doc["boarding_stop"] = _clean_str(v)

    @property
    def is_transport_active(self) -> bool:
        return bool(self._doc.get("is_transport_active", True))

    @is_transport_active.setter
    def is_transport_active(self, v: bool):
        self._doc["is_transport_active"] = bool(v)

    @property
    def created_at(self) -> datetime | None:
        return self._doc.get("created_at")

    @property
    def updated_at(self) -> datetime | None:
        return self._doc.get("updated_at")

    # ------------------------------------------------------------------ #
    # Serialisation                                                      #
    # ------------------------------------------------------------------ #
    def to_dict(self) -> dict:
        created_str = (
            self.created_at.isoformat()
            if isinstance(self.created_at, datetime)
            else self.created_at
        )
        updated_str = (
            self.updated_at.isoformat()
            if isinstance(self.updated_at, datetime)
            else self.updated_at
        )

        return {
            "id": self.id,
            "register_number": self.register_number,
            "name": self.name,
            "department": self.department,
            "year": self.year,
            "section": self.section,
            "student_mobile": self.student_mobile,
            "parent_mobile": self.parent_mobile,
            "route_name": self.route_name,
            "bus_number": self.bus_number,
            "boarding_stop": self.boarding_stop,
            "is_transport_active": self.is_transport_active,
            "created_at": created_str,
            "updated_at": updated_str,
        }

    # ------------------------------------------------------------------ #
    # Persistence                                                        #
    # ------------------------------------------------------------------ #
    def save(self) -> "Student":
        db = get_db()
        self._doc["updated_at"] = datetime.utcnow()
        if "_id" not in self._doc:
            new_id = get_next_sequence("students")
            self._doc["_id"] = new_id
            self._doc["id"] = new_id
            db["students"].insert_one(self._doc)
        else:
            update_fields = {k: v for k, v in self._doc.items() if k != "_id"}
            db["students"].update_one({"_id": self._doc["_id"]}, {"$set": update_fields})
        return self

    # ------------------------------------------------------------------ #
    # Class-level query helpers                                          #
    # ------------------------------------------------------------------ #
    @classmethod
    def find_by_id(cls, student_id: int) -> "Student | None":
        try:
            doc = get_db()["students"].find_one({"_id": int(student_id)})
            return _doc_to_obj(doc) if doc else None
        except (ValueError, TypeError):
            return None

    @classmethod
    def find_by_register_number(cls, reg_no: str) -> "Student | None":
        clean = _clean_str(reg_no).upper()
        if not clean:
            return None
        doc = get_db()["students"].find_one({"register_number": clean})
        return _doc_to_obj(doc) if doc else None

    @classmethod
    def list_students(
        cls,
        q: str | None = None,
        department: str | None = None,
        year: str | None = None,
        route_name: str | None = None,
        bus_number: str | None = None,
        is_transport_active: bool | None = None,
        skip: int = 0,
        limit: int = 20,
    ) -> tuple[list["Student"], int]:
        db = get_db()
        query = {}

        if is_transport_active is not None:
            query["is_transport_active"] = is_transport_active

        if department:
            query["department"] = department.strip().upper()

        if year:
            query["year"] = year.strip().upper()

        if route_name:
            query["route_name"] = {"$regex": re.escape(route_name.strip()), "$options": "i"}

        if bus_number:
            query["bus_number"] = bus_number.strip().upper()

        if q:
            term = re.escape(q.strip())
            query["$or"] = [
                {"register_number": {"$regex": term, "$options": "i"}},
                {"name": {"$regex": term, "$options": "i"}},
                {"boarding_stop": {"$regex": term, "$options": "i"}},
            ]

        total = db["students"].count_documents(query)
        cursor = db["students"].find(query).sort("register_number", 1).skip(skip).limit(limit)
        students = [_doc_to_obj(d) for d in cursor]
        return students, total

    @classmethod
    def get_route_allocations(cls) -> dict:
        """
        Aggregate route and bus allocation statistics:
        - Route-wise student counts
        - Bus-wise student counts
        """
        db = get_db()
        col = db["students"]

        # 1. Route-wise aggregation
        route_pipeline = [
            {
                "$group": {
                    "_id": "$route_name",
                    "total_students": {"$sum": 1},
                    "active_students": {
                        "$sum": {"$cond": [{"$eq": ["$is_transport_active", True]}, 1, 0]}
                    },
                    "buses": {"$addToSet": "$bus_number"},
                }
            },
            {"$sort": {"total_students": -1}},
        ]
        route_results = list(col.aggregate(route_pipeline))
        routes = [
            {
                "route_name": r["_id"] or "Unassigned Route",
                "total_students": r["total_students"],
                "active_students": r["active_students"],
                "buses": sorted([b for b in r["buses"] if b]),
            }
            for r in route_results
        ]

        # 2. Bus-wise aggregation
        bus_pipeline = [
            {
                "$group": {
                    "_id": "$bus_number",
                    "total_students": {"$sum": 1},
                    "active_students": {
                        "$sum": {"$cond": [{"$eq": ["$is_transport_active", True]}, 1, 0]}
                    },
                    "routes": {"$addToSet": "$route_name"},
                }
            },
            {"$sort": {"_id": 1}},
        ]
        bus_results = list(col.aggregate(bus_pipeline))
        buses = [
            {
                "bus_number": b["_id"] or "Unassigned Bus",
                "total_students": b["total_students"],
                "active_students": b["active_students"],
                "routes": sorted([r for r in b["routes"] if r]),
            }
            for b in bus_results
        ]

        return {
            "total_students": col.count_documents({}),
            "total_active_students": col.count_documents({"is_transport_active": True}),
            "routes": routes,
            "buses": buses,
        }
