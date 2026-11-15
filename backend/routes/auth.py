"""
Authentication Endpoints — email + password login with JWT tokens.
No Firebase Admin SDK required. Firebase on the client side is optional.
"""

from functools import wraps

import bcrypt
from flask import Blueprint, current_app, g, jsonify, request
from flask_jwt_extended import (
    create_access_token,
    decode_token,
    get_jwt_identity,
    jwt_required,
    verify_jwt_in_request,
)
from sqlalchemy.exc import SQLAlchemyError

from models import db
from models.user import User

auth_bp = Blueprint('auth_bp', __name__, url_prefix='/api/auth')


# ── Helpers ────────────────────────────────────────────────────────────────────

def _check_password(plain: str, hashed: str) -> bool:
    """Compare plain-text password against a stored bcrypt hash."""
    try:
        return bcrypt.checkpw(
            plain.encode('utf-8'),
            hashed.encode('utf-8'),
        )
    except Exception:
        return False


def jwt_auth_required(fn):
    """Decorator: verify JWT and load the matching transport user into g."""
    @wraps(fn)
    def wrapper(*args, **kwargs):
        try:
            verify_jwt_in_request()
        except Exception:
            return jsonify({'error': 'A valid Bearer token is required'}), 401

        email = get_jwt_identity()
        try:
            user = User.find_by_email(email)
        except SQLAlchemyError:
            current_app.logger.exception('DB error loading user from JWT')
            return jsonify({'error': 'Could not load user profile'}), 500

        if not user:
            return jsonify({'error': 'No transport account for this token'}), 403
        if not user.is_active:
            return jsonify({'error': 'Account is deactivated. Contact transport admin.'}), 403

        g.current_user = user
        return fn(*args, **kwargs)
    return wrapper


def get_authenticated_user() -> User:
    user = getattr(g, 'current_user', None)
    if user is None:
        raise RuntimeError('No authenticated transport user is available')
    return user


def admin_required(fn):
    @wraps(fn)
    @jwt_auth_required
    def wrapper(*args, **kwargs):
        if get_authenticated_user().role != 'admin':
            return jsonify({'error': 'Forbidden: Admin access required'}), 403
        return fn(*args, **kwargs)
    return wrapper


def driver_or_admin_required(fn):
    @wraps(fn)
    @jwt_auth_required
    def wrapper(*args, **kwargs):
        if get_authenticated_user().role not in {'driver', 'admin'}:
            return jsonify({'error': 'Forbidden: Driver or Admin access required'}), 403
        return fn(*args, **kwargs)
    return wrapper


# ── Routes ─────────────────────────────────────────────────────────────────────

@auth_bp.route('/login', methods=['POST'])
def login():
    """
    POST /api/auth/login
    Body: { "email": "...", "password": "..." }
    Returns: { "token": "<jwt>", "user": { ... } }
    """
    data = request.get_json(silent=True) or {}
    email = str(data.get('email', '')).strip().lower()
    password = str(data.get('password', ''))

    if not email or not password:
        return jsonify({'error': 'Email and password are required'}), 400

    try:
        user = User.find_by_email(email)
    except SQLAlchemyError:
        current_app.logger.exception('DB error during login')
        return jsonify({'error': 'Database error. Please try again.'}), 500

    if not user or not user.password_hash:
        return jsonify({'error': 'Email or password is incorrect.'}), 401

    if not _check_password(password, user.password_hash):
        return jsonify({'error': 'Email or password is incorrect.'}), 401

    if not user.is_active:
        return jsonify({'error': 'Account is deactivated. Contact transport admin.'}), 403

    token = create_access_token(identity=user.email)
    return jsonify({'token': token, 'user': user.to_dict()}), 200


@auth_bp.route('/me', methods=['GET'])
@jwt_auth_required
def get_current_user():
    """Return the database profile for the authenticated user."""
    return jsonify({'user': get_authenticated_user().to_dict()}), 200


@auth_bp.route('/fcm-token', methods=['PUT'])
@jwt_auth_required
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
