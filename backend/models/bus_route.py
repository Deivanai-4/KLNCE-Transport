"""
BusRoute model representing individual college bus routes (e.g. Bus K, Bus IT9).
"""

from datetime import datetime
from models import db


class BusRoute(db.Model):
    __tablename__ = 'bus_routes'

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    schedule_id = db.Column(db.Integer, db.ForeignKey('schedule_documents.id', ondelete='CASCADE'), nullable=False, index=True)
    bus_code = db.Column(db.String(10), nullable=False, index=True)
    route_display_name = db.Column(db.String(200), nullable=True)
    departure_time = db.Column(db.String(10), nullable=True)
    college = db.Column(db.Enum('engineering', 'arts_science', 'both', name='bus_colleges'), nullable=False, default='engineering')
    display_order = db.Column(db.Integer, nullable=False, default=0)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    # Relationship to stops
    stops = db.relationship('RouteStop', backref='route', lazy='dynamic', cascade='all, delete-orphan')

    def to_dict(self, include_stops: bool = True) -> dict:
        data = {
            'id': self.id,
            'schedule_id': self.schedule_id,
            'bus_code': self.bus_code,
            'route_display_name': self.route_display_name,
            'departure_time': self.departure_time,
            'college': self.college,
            'display_order': self.display_order,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }
        if include_stops:
            from models.route_stop import RouteStop
            data['stops'] = [s.to_dict() for s in self.stops.order_by(RouteStop.stop_order.asc()).all()]
        return data

