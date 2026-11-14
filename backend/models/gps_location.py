"""
GpsLocation model representing live tracking coordinates emitted by driver devices.
"""

from datetime import datetime
from models import db


class GpsLocation(db.Model):
    __tablename__ = 'gps_locations'

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    bus_code = db.Column(db.String(10), nullable=False, index=True)
    driver_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    latitude = db.Column(db.Numeric(10, 8), nullable=False)
    longitude = db.Column(db.Numeric(11, 8), nullable=False)
    speed_kmh = db.Column(db.Numeric(5, 2), nullable=True)
    is_active_trip = db.Column(db.Boolean, nullable=False, default=True, index=True)
    recorded_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, index=True)

    def to_dict(self) -> dict:
        return {
            'id': self.id,
            'bus_code': self.bus_code,
            'driver_id': self.driver_id,
            'latitude': float(self.latitude) if self.latitude is not None else None,
            'longitude': float(self.longitude) if self.longitude is not None else None,
            'speed_kmh': float(self.speed_kmh) if self.speed_kmh is not None else None,
            'is_active_trip': self.is_active_trip,
            'recorded_at': self.recorded_at.isoformat() if self.recorded_at else None
        }

    @classmethod
    def get_latest_for_bus(cls, bus_code: str):
        return cls.query.filter_by(bus_code=bus_code, is_active_trip=True).order_by(cls.recorded_at.desc()).first()

    @classmethod
    def get_active_buses(cls):
        """Returns the most recent active location for each active bus."""
        subquery = db.session.query(
            cls.bus_code,
            db.func.max(cls.recorded_at).label('max_time')
        ).filter_by(is_active_trip=True).group_by(cls.bus_code).subquery()

        return cls.query.join(
            subquery,
            db.and_(
                cls.bus_code == subquery.c.bus_code,
                cls.recorded_at == subquery.c.max_time
            )
        ).all()

