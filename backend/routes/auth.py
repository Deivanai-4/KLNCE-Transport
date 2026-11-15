"""
Authentication and User Profile Endpoints.
Accepts Firebase ID tokens and preserves database-backed role authorization.
"""

from functools import wraps

from flask import Blueprint, current_app, g, jsonify, request
from sqlalchemy.exc import SQLAlchemyError

from models import db
from models.user import User
from services.firebase_auth import (
    FirebaseAuthUnavailable,
    InvalidFirebaseToken,
    verify_firebase_id_token,
)

auth_bp = Blueprint('auth_bp', __name__, url_prefix='/api/auth')


def firebase_auth_required(fn):
    """Verify a Firebase ID token and load its active transport profile."""
    @wraps(fn)
    def wrapper(*args, **kwargs):
        authorization = request.headers.get('Authorization', '')
        scheme, separator, token = authorization.partition(' ')
        if not separator or scheme.lower() != 'bearer' or not token.strip():
            return jsonify({'error': 'A Firebase Bearer token is required'}), 401

        try:
            claims = verify_firebase_id_token(token.strip())
        except InvalidFirebaseToken:
            return jsonify({'error': 'Invalid or expired Firebase token'}), 401
        except FirebaseAuthUnavailable:
            current_app.logger.exception('Firebase token verification is unavailable')
            return jsonify({'error': 'Authentication service is unavailable'}), 503

        email = claims.get('email')
        if not isinstance(email, str) or claims.get('email_verified') is not True:
            return jsonify({'error': 'A verified Firebase email is required'}), 403

        try:
            user = User.find_by_email(email.strip().lower())
        except SQLAlchemyError:
            current_app.logger.exception('Failed to load the Firebase user profile')
            return jsonify({'error': 'Could not load the user profile'}), 500

        if not user:
            return jsonify({
                'error': 'No transport account is linked to this email. Contact the transport office.'
            }), 403
        if not user.is_active:
            return jsonify({
                'error': 'Account is deactivated. Contact transport admin.'
            }), 403

        g.current_user = user
        return fn(*args, **kwargs)

    return wrapper


def get_authenticated_user() -> User:
    """Return the active transport profile loaded by firebase_auth_required."""
    user = getattr(g, 'current_user', None)
    if user is None:
        raise RuntimeError('No authenticated transport user is available')
    return user


def admin_required(fn):
    """Ensure that only users with role='admin' can access the route."""
    @wraps(fn)
    @firebase_auth_required
    def wrapper(*args, **kwargs):
        if get_authenticated_user().role != 'admin':
            return jsonify({'error': 'Forbidden: Admin access required'}), 403
        return fn(*args, **kwargs)
    return wrapper


def driver_or_admin_required(fn):
    """Restrict driver GPS updates to drivers and administrators."""
    @wraps(fn)
    @firebase_auth_required
    def wrapper(*args, **kwargs):
        if get_authenticated_user().role not in {'driver', 'admin'}:
            return jsonify({
                'error': 'Forbidden: Driver or Admin access required'
            }), 403
        return fn(*args, **kwargs)
    return wrapper


@auth_bp.route('/me', methods=['GET'])
@firebase_auth_required
def get_current_user():
    """Return the database profile for the authenticated Firebase account."""
    return jsonify({'user': get_authenticated_user().to_dict()}), 200


@auth_bp.route('/fcm-token', methods=['PUT'])
@firebase_auth_required
def update_fcm_token():
    """Register or update the authenticated user's FCM device token."""
    user = get_authenticated_user()
    data = request.get_json(silent=True) or {}
    fcm_token = data.get('fcm_token', '')
    if not isinstance(fcm_token, str):
        return jsonify({'error': 'FCM token must be a string'}), 400

    user.fcm_token = fcm_token.strip()
    db.session.commit()
    return jsonify({'message': 'FCM token registered successfully'}), 200
