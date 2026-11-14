"""
ScheduleDocument model representing uploaded schedule files and verification status.
"""

from datetime import datetime
from models import db
from services.schedule_visibility import active_trip_at


class ScheduleDocument(db.Model):
    __tablename__ = 'schedule_documents'

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    title = db.Column(db.String(200), nullable=False)
    file_url = db.Column(db.Text, nullable=False)
    file_type = db.Column(db.Enum('image', 'pdf', name='file_types'), nullable=False)
    trip_direction = db.Column(db.Enum('incoming', 'outgoing', name='trip_directions'), nullable=False, default='incoming', index=True)
    college = db.Column(db.Enum('engineering', 'arts_science', 'both', name='college_types'), nullable=False, default='both')
    effective_date = db.Column(db.Date, nullable=False, index=True)
    status = db.Column(db.Enum('draft', 'verified', 'published', 'archived', name='schedule_statuses'), nullable=False, default='draft', index=True)
    
    created_by = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    verified_by = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=True)
    verified_at = db.Column(db.DateTime, nullable=True)
    published_at = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    # Relationships
    bus_routes = db.relationship('BusRoute', backref='schedule', lazy='dynamic', cascade='all, delete-orphan')

    def to_dict(self, include_routes: bool = False) -> dict:
        data = {
            'id': self.id,
            'title': self.title,
            'file_url': self.file_url,
            'file_type': self.file_type,
            'trip_direction': self.trip_direction,
            'college': self.college,
            'effective_date': self.effective_date.isoformat() if self.effective_date else None,
            'status': self.status,
            'created_by': self.created_by,
            'verified_by': self.verified_by,
            'verified_at': self.verified_at.isoformat() if self.verified_at else None,
            'published_at': self.published_at.isoformat() if self.published_at else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'routes_count': self.bus_routes.count()
        }
        if include_routes:
            from models.bus_route import BusRoute
            data['bus_routes'] = [r.to_dict(include_stops=True) for r in self.bus_routes.order_by(BusRoute.display_order.asc()).all()]
        return data

    @classmethod
    def get_published(
        cls,
        trip_direction: str = None,
        college: str = None,
        now: datetime = None,
    ):
        active_trip = active_trip_at(now)
        if active_trip is None:
            return None
        if trip_direction is None:
            trip_direction = active_trip
        elif trip_direction != active_trip:
            return None

        q = cls.query.filter_by(status='published')
        q = q.filter_by(trip_direction=trip_direction)
        if college and college != 'both':
            q = q.filter(cls.college.in_([college, 'both']))
        return q.order_by(cls.effective_date.desc()).first()

    @classmethod
    def get_drafts(cls):
        return cls.query.filter(cls.status.in_(['draft', 'verified'])).order_by(cls.created_at.desc()).all()

    @classmethod
    def find_by_id(cls, schedule_id: int):
        return cls.query.get(schedule_id)

