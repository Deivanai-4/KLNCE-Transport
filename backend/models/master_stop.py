# -*- coding: utf-8 -*-
"""
MasterStop model representing normalized bus stop landmarks with Tamil/English names and GPS coords.
"""

from datetime import datetime
import json
from models import db


class MasterStop(db.Model):
    __tablename__ = 'master_stops'

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    standard_name_en = db.Column(db.String(200), nullable=False, index=True)
    standard_name_ta = db.Column(db.String(200), nullable=True)
    aliases = db.Column(db.Text, nullable=True)  # JSON string array
    latitude = db.Column(db.Numeric(10, 8), nullable=True)
    longitude = db.Column(db.Numeric(11, 8), nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    def to_dict(self) -> dict:
        aliases_list = []
        if self.aliases:
            try:
                aliases_list = json.loads(self.aliases)
            except Exception:
                aliases_list = [self.aliases]
        return {
            'id': self.id,
            'standard_name_en': self.standard_name_en,
            'standard_name_ta': self.standard_name_ta,
            'aliases': aliases_list,
            'latitude': float(self.latitude) if self.latitude is not None else None,
            'longitude': float(self.longitude) if self.longitude is not None else None,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }

    @classmethod
    def search(cls, query_str: str, limit: int = 15):
        """Bilingual search across English and Tamil names and JSON aliases."""
        term = f"%{query_str.strip()}%"
        return cls.query.filter(
            db.or_(
                cls.standard_name_en.ilike(term),
                cls.standard_name_ta.ilike(term),
                cls.aliases.ilike(term)
            )
        ).limit(limit).all()
