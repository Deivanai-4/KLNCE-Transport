"""
models/user.py — PyMongo-backed User document model.

Collection: users
Document shape (from live Atlas inspection):
  _id:          int  (original MySQL PK, same as 'id' field)
  id:           int  (mirror of _id — preserved for frontend compatibility)
  name:         str
  email:        str  (lowercase, unique index)
  phone:        str | None
  password_hash: str | None  (bcrypt)
  role:         str  — 'student' | 'staff' | 'admin' | 'driver'
  college:      str  — 'engineering' | 'arts_science' | 'both'
  fcm_token:    str | None
  is_active:    int  (1 or 0 — cast to bool in to_dict())
  created_at:   datetime (UTC)
"""

from datetime import datetime
from models.database import get_db, get_next_sequence


def _doc_to_obj(doc: dict) -> "User":
    """Wrap a raw MongoDB document in a User instance."""
    u = User.__new__(User)
    u._doc = doc
    return u


class User:
    """Lightweight wrapper around a MongoDB user document."""

    def __init__(
        self,
        name: str,
        email: str,
        role: str = "student",
        college: str = "engineering",
        phone: str | None = None,
        password_hash: str | None = None,
        fcm_token: str | None = None,
        is_active: bool = True,
        created_at: datetime | None = None,
    ):
        self._doc = {
            "name": name,
            "email": email.strip().lower() if email else "",
            "phone": phone,
            "password_hash": password_hash,
            "role": role,
            "college": college,
            "fcm_token": fcm_token or "",
            "is_active": 1 if is_active else 0,
            "created_at": created_at or datetime.utcnow(),
        }

    # ------------------------------------------------------------------ #
    # Attribute access shims                                               #
    # ------------------------------------------------------------------ #
    @property
    def id(self) -> int:
        return int(self._doc.get("_id", self._doc.get("id", 0)))

    @property
    def name(self) -> str:
        return self._doc.get("name", "")

    @name.setter
    def name(self, v: str):
        self._doc["name"] = v

    @property
    def email(self) -> str:
        return self._doc.get("email", "")

    @email.setter
    def email(self, v: str):
        self._doc["email"] = v.strip().lower() if v else ""

    @property
    def phone(self) -> str | None:
        return self._doc.get("phone")

    @property
    def password_hash(self) -> str | None:
        return self._doc.get("password_hash")

    @password_hash.setter
    def password_hash(self, v: str | None):
        self._doc["password_hash"] = v

    @property
    def role(self) -> str:
        return self._doc.get("role", "student")

    @property
    def college(self) -> str:
        return self._doc.get("college", "engineering")

    @property
    def fcm_token(self) -> str | None:
        return self._doc.get("fcm_token")

    @fcm_token.setter
    def fcm_token(self, v: str | None):
        self._doc["fcm_token"] = v

    @property
    def is_active(self) -> bool:
        return bool(self._doc.get("is_active", 1))

    @is_active.setter
    def is_active(self, v: bool):
        self._doc["is_active"] = 1 if v else 0

    @property
    def created_at(self) -> datetime | None:
        return self._doc.get("created_at")

    # ------------------------------------------------------------------ #
    # Serialisation                                                        #
    # ------------------------------------------------------------------ #
    def to_dict(self) -> dict:
        """Return safe dict representation — identical shape to old SQLAlchemy model."""
        return {
            "id": self.id,
            "name": self.name,
            "email": self.email,
            "phone": self.phone,
            "role": self.role,
            "college": self.college,
            "fcm_token": self.fcm_token,
            "is_active": self.is_active,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }

    # ------------------------------------------------------------------ #
    # Persistence                                                          #
    # ------------------------------------------------------------------ #
    def save(self) -> "User":
        """Insert (new) or update (existing) user document."""
        db = get_db()
        if "_id" not in self._doc:
            new_id = get_next_sequence("users")
            self._doc["_id"] = new_id
            self._doc["id"] = new_id
            db["users"].insert_one(self._doc)
        else:
            update_fields = {k: v for k, v in self._doc.items() if k != "_id"}
            db["users"].update_one({"_id": self._doc["_id"]}, {"$set": update_fields})
        return self

    # ------------------------------------------------------------------ #
    # Class-level query helpers                                            #
    # ------------------------------------------------------------------ #
    @classmethod
    def find_by_email(cls, email: str) -> "User | None":
        doc = get_db()["users"].find_one({"email": email.strip().lower()})
        return _doc_to_obj(doc) if doc else None

    @classmethod
    def find_by_id(cls, user_id: int) -> "User | None":
        doc = get_db()["users"].find_one({"_id": int(user_id)})
        return _doc_to_obj(doc) if doc else None
