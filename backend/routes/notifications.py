"""
Notification broadcasting routes for FCM push alerts and SMS dispatches.
PyMongo / MongoDB Atlas backed.
"""

from datetime import datetime
from flask import Blueprint, current_app, request, jsonify
from models.database import get_db
from models.user import User, _doc_to_obj as _user_to_obj
from models.notification import Notification
from routes.auth import admin_required, get_authenticated_user
from services.firebase_service import send_notification_to_all
from services.sms_service import send_bulk_sms

notifications_bp = Blueprint('notifications_bp', __name__, url_prefix='/api/notifications')


@notifications_bp.route('/send', methods=['POST'])
@admin_required
def send_notification():
    """
    Admin sends push notification and optional SMS for schedule changes or delays.
    Body:
        {
            "title": "Bus Delay Alert",
            "body": "Bus K is delayed by 15 mins due to road repairs at Thirunagar.",
            "type": "delay",
            "send_sms": false
        }
    """
    data = request.get_json(silent=True) or {}
    title = data.get('title', '').strip()
    body = data.get('body', '').strip()
    notif_type = data.get('type', 'general')
    also_send_sms = data.get('send_sms', False)

    if not title or not body:
        return jsonify({'error': 'Title and body are required'}), 400

    admin_id = get_authenticated_user().id

    # 1. Send FCM Broadcast
    fcm_recipients = send_notification_to_all(title=title, body=body, data={'type': notif_type})

    # 2. Optionally send SMS via MSG91
    sms_count = 0
    if also_send_sms:
        db = get_db()
        users_with_phone = list(db['users'].find({
            'phone': {'$exists': True, '$ne': None, '$nin': ['', 'null']}
        }))
        phones = [u['phone'] for u in users_with_phone if u.get('phone')]
        if phones:
            sms_count = send_bulk_sms(phones, f"KLNCE Transport: {title} - {body}")

    # Record notification in database
    notif = Notification(
        title=title,
        body=body,
        type=notif_type,
        sent_by=admin_id,
        sent_at=datetime.utcnow(),
        recipient_count=fcm_recipients + sms_count
    )
    notif.save()

    return jsonify({
        'message': 'Notification dispatched successfully',
        'notification': notif.to_dict()
    }), 201


@notifications_bp.route('', methods=['GET'])
@notifications_bp.route('/history', methods=['GET'])
def get_notification_history():
    """Returns past broadcast notifications for display in student and admin notification centers."""
    limit = min(int(request.args.get('limit', 30)), 100)
    notifications = Notification.get_history(limit=limit)
    notif_list = [n.to_dict() for n in notifications]
    return jsonify({'notifications': notif_list, 'total': len(notif_list)}), 200


@notifications_bp.route('/<int:notification_id>', methods=['PUT'])
@admin_required
def update_notification(notification_id):
    """Updates the public alert history without re-sending its push or SMS."""
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({'error': 'Alert details must be sent as an object'}), 400

    raw_title = data.get('title')
    raw_body = data.get('body')
    if not isinstance(raw_title, str) or not isinstance(raw_body, str):
        return jsonify({'error': 'Title and message are required'}), 400

    title = raw_title.strip()
    body = raw_body.strip()
    if not title or not body:
        return jsonify({'error': 'Title and message are required'}), 400
    if len(title) > 200:
        return jsonify({'error': 'Title must be 200 characters or fewer'}), 400

    notification = Notification.find_by_id(notification_id)
    if notification is None:
        return jsonify({'error': 'Alert not found'}), 404

    notification.title = title
    notification.body = body
    try:
        notification.save()
    except Exception:
        current_app.logger.exception('Failed to update broadcast alert %s', notification_id)
        return jsonify({'error': 'Could not update the alert'}), 500

    return jsonify({
        'message': 'Alert updated successfully',
        'notification': notification.to_dict(),
    }), 200


@notifications_bp.route('/<int:notification_id>', methods=['DELETE'])
@admin_required
def delete_notification(notification_id):
    """Removes an alert from app history; already sent messages cannot be recalled."""
    notification = Notification.find_by_id(notification_id)
    if notification is None:
        return jsonify({'error': 'Alert not found'}), 404

    try:
        notification.delete()
    except Exception:
        current_app.logger.exception('Failed to delete broadcast alert %s', notification_id)
        return jsonify({'error': 'Could not delete the alert'}), 500

    return jsonify({'message': 'Alert deleted successfully'}), 200
