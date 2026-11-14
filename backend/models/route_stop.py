"""
RouteStop model representing sequential stops along a bus route.
"""

from models import db


class RouteStop(db.Model):
    __tablename__ = 'route_stops'

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    bus_route_id = db.Column(db.Integer, db.ForeignKey('bus_routes.id', ondelete='CASCADE'), nullable=False, index=True)
    stop_order = db.Column(db.Integer, nullable=False)
    stop_name_en = db.Column(db.String(200), nullable=False, index=True)
    stop_name_ta = db.Column(db.String(200), nullable=True, index=True)
    estimated_arrival_time = db.Column(db.String(10), nullable=True)
    master_stop_id = db.Column(db.Integer, db.ForeignKey('master_stops.id', ondelete='SET NULL'), nullable=True)

    def to_dict(self) -> dict:
        return {
            'id': self.id,
            'bus_route_id': self.bus_route_id,
            'stop_order': self.stop_order,
            'stop_name_en': self.stop_name_en,
            'stop_name_ta': self.stop_name_ta,
            'estimated_arrival_time': self.estimated_arrival_time,
            'master_stop_id': self.master_stop_id
        }

