"""
User model representing students, staff, admins, and drivers.
"""

from datetime import datetime
from models import db


class User(db.Model):
    __tablename__ = 'users'

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    name = db.Column(db.String(100), nullable=False)
    email = db.Column(db.String(100), unique=True, nullable=False, index=True)
    phone = db.Column(db.String(15), nullable=True)
    password_hash = db.Column(db.String(255), nullable=True)
    role = db.Column(db.Enum('student', 'staff', 'admin', 'driver', name='user_roles'), nullable=False, default='student', index=True)
    college = db.Column(db.Enum('engineering', 'arts_science', 'both', name='college_types'), nullable=False, default='engineering')
    fcm_token = db.Column(db.String(255), nullable=True)
    is_active = db.Column(db.Boolean, nullable=False, default=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    def to_dict(self) -> dict:
        """Return safe dictionary representation without password hash."""
        return {
            'id': self.id,
            'name': self.name,
            'email': self.email,
            'phone': self.phone,
            'role': self.role,
            'college': self.college,
            'fcm_token': self.fcm_token,
            'is_active': self.is_active,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }

    @classmethod
    def find_by_email(cls, email: str):
        return cls.query.filter_by(email=email).first()

    @classmethod
    def find_by_id(cls, user_id: int):
        return cls.query.get(user_id)

