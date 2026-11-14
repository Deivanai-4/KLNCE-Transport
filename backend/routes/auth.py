"""
Authentication and User Profile Endpoints.
Supports JWT tokens, role-based authorization, and FCM registration.
"""

from functools import wraps
from flask import Blueprint, request, jsonify
from flask_jwt_extended import (
    create_access_token,
    jwt_required,
    get_jwt_identity,
    get_jwt
)
from models import db
from models.user import User

auth_bp = Blueprint('auth_bp', __name__, url_prefix='/api/auth')


def admin_required(fn):
    """Decorator ensuring that only users with role='admin' can access the route."""
    @wraps(fn)
    @jwt_required()
    def wrapper(*args, **kwargs):
        claims = get_jwt()
        if claims.get('role') != 'admin':
            return jsonify({'error': 'Forbidden: Admin access required'}), 403
        return fn(*args, **kwargs)
    return wrapper


def driver_or_admin_required(fn):
    """Decorator for driver GPS updates."""
    @wraps(fn)
    @jwt_required()
    def wrapper(*args, **kwargs):
        claims = get_jwt()
        if claims.get('role') not in ['driver', 'admin']:
            return jsonify({'error': 'Forbidden: Driver or Admin access required'}), 403
        return fn(*args, **kwargs)
    return wrapper


@auth_bp.route('/login', methods=['POST'])
def login():
    """Login with email and password -> returns JWT access token and user profile."""
    data = request.get_json(silent=True) or {}
    email = data.get('email', '').strip().lower()
    password = data.get('password', '')

    if not email or not password:
        return jsonify({'error': 'Email and password are required'}), 400

    try:
        user = User.find_by_email(email)
    except Exception as e:
        return jsonify({
            'error': f'Database connection failed: {str(e)}. Please check DB_PASSWORD in backend/.env'
        }), 500

    if not user or not user.check_password(password):
        return jsonify({'error': 'Invalid email or password'}), 401

    if not user.is_active:
        return jsonify({'error': 'Account is deactivated. Contact transport admin.'}), 403

    # Generate JWT with user id as identity and role in claims
    additional_claims = {
        'role': user.role,
        'college': user.college,
        'name': user.name
    }
    access_token = create_access_token(identity=str(user.id), additional_claims=additional_claims)

    return jsonify({
        'message': 'Login successful',
        'token': access_token,
        'user': user.to_dict()
    }), 200


@auth_bp.route('/register', methods=['POST'])
def register():
    """Self-registration for students and faculty members."""
    data = request.get_json(silent=True) or {}
    name = data.get('name', '').strip()
    email = data.get('email', '').strip().lower()
    password = data.get('password', '')
    role = data.get('role', 'student')
    college = data.get('college', 'engineering')
    phone = data.get('phone', '')

    if not name or not email or not password:
        return jsonify({'error': 'Name, email, and password are required'}), 400

    if role not in ['student', 'staff']:
        role = 'student'

    if User.find_by_email(email):
        return jsonify({'error': 'An account with this email already exists'}), 409

    user = User(
        name=name,
        email=email,
        phone=phone,
        role=role,
        college=college
    )
    user.set_password(password)

    db.session.add(user)
    db.session.commit()

    additional_claims = {'role': user.role, 'college': user.college, 'name': user.name}
    token = create_access_token(identity=str(user.id), additional_claims=additional_claims)

    return jsonify({
        'message': 'Account registered successfully',
        'token': token,
        'user': user.to_dict()
    }), 201


@auth_bp.route('/me', methods=['GET'])
@jwt_required()
def get_current_user():
    """Returns profile information for the authenticated user."""
    user_id = int(get_jwt_identity())
    user = User.find_by_id(user_id)
    if not user:
        return jsonify({'error': 'User not found'}), 404
    return jsonify({'user': user.to_dict()}), 200


@auth_bp.route('/fcm-token', methods=['PUT'])
@jwt_required()
def update_fcm_token():
    """Registers or updates student's FCM device token for push notifications."""
    user_id = int(get_jwt_identity())
    data = request.get_json(silent=True) or {}
    fcm_token = data.get('fcm_token', '').strip()

    user = User.find_by_id(user_id)
    if not user:
        return jsonify({'error': 'User not found'}), 404

    user.fcm_token = fcm_token
    db.session.commit()
    return jsonify({'message': 'FCM token registered successfully'}), 200


@auth_bp.route('/logout', methods=['POST'])
def logout():
    """Client-side token disposal endpoint."""
    return jsonify({'message': 'Logged out successfully'}), 200

