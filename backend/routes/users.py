"""
User management and metrics endpoints for transport administrator.
PyMongo / MongoDB Atlas backed.
"""

from flask import Blueprint, request, jsonify
from models.database import get_db
from models.user import User, _doc_to_obj
from routes.auth import admin_required

users_bp = Blueprint('users_bp', __name__, url_prefix='/api/users')


@users_bp.route('', methods=['GET'])
@admin_required
def list_users():
    """Lists registered students, faculty, drivers, and admins."""
    role = request.args.get('role')
    page = int(request.args.get('page', 1))
    per_page = int(request.args.get('per_page', 20))

    db = get_db()
    filter_query = {}
    if role:
        filter_query['role'] = role

    total = db['users'].count_documents(filter_query)
    skip = (page - 1) * per_page
    docs = db['users'].find(filter_query).sort('created_at', -1).skip(skip).limit(per_page)

    users_list = [_doc_to_obj(d).to_dict() for d in docs]

    return jsonify({
        'total': total,
        'page': page,
        'per_page': per_page,
        'users': users_list
    }), 200


@users_bp.route('/stats', methods=['GET'])
@admin_required
def get_user_stats():
    """Returns overview counts of active students, faculty, and drivers."""
    db = get_db()
    active_condition = {'$in': [1, True]}
    total_students = db['users'].count_documents({'role': 'student', 'is_active': active_condition})
    total_staff = db['users'].count_documents({'role': 'staff', 'is_active': active_condition})
    total_drivers = db['users'].count_documents({'role': 'driver', 'is_active': active_condition})

    return jsonify({
        'students_count': total_students,
        'staff_count': total_staff,
        'drivers_count': total_drivers,
        'total_active_users': total_students + total_staff + total_drivers
    }), 200
