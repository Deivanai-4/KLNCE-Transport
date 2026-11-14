"""
User management and metrics endpoints for transport administrator.
"""

from flask import Blueprint, request, jsonify
from models import db
from models.user import User
from routes.auth import admin_required

users_bp = Blueprint('users_bp', __name__, url_prefix='/api/users')


@users_bp.route('', methods=['GET'])
@admin_required
def list_users():
    """Lists registered students, faculty, drivers, and admins."""
    role = request.args.get('role')
    page = int(request.args.get('page', 1))
    per_page = int(request.args.get('per_page', 20))

    query = User.query
    if role:
        query = query.filter_by(role=role)

    paginated = query.order_by(User.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)

    return jsonify({
        'total': paginated.total,
        'page': page,
        'per_page': per_page,
        'users': [u.to_dict() for u in paginated.items]
    }), 200


@users_bp.route('/stats', methods=['GET'])
@admin_required
def get_user_stats():
    """Returns overview counts of active students, faculty, and drivers."""
    total_students = User.query.filter_by(role='student', is_active=True).count()
    total_staff = User.query.filter_by(role='staff', is_active=True).count()
    total_drivers = User.query.filter_by(role='driver', is_active=True).count()

    return jsonify({
        'students_count': total_students,
        'staff_count': total_staff,
        'drivers_count': total_drivers,
        'total_active_users': total_students + total_staff + total_drivers
    }), 200

