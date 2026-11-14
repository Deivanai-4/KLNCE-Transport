"""
Notification model for recording FCM and SMS notification history.
"""

from datetime import datetime
from models import db


class Notification(db.Model):
    __tablename__ = 'notifications'

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    title = db.Column(db.String(200), nullable=False)
    body = db.Column(db.Text, nullable=False)
    type = db.Column(db.Enum('schedule_update', 'delay', 'route_change', 'holiday', 'general', name='notification_types'), nullable=False, default='general')
    sent_by = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    sent_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, index=True)
    recipient_count = db.Column(db.Integer, nullable=False, default=0)

    def to_dict(self) -> dict:
        return {
            'id': self.id,
            'title': self.title,
            'body': self.body,
            'type': self.type,
            'sent_by': self.sent_by,
            'sent_at': self.sent_at.isoformat() if self.sent_at else None,
            'recipient_count': self.recipient_count
        }

