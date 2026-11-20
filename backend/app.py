# -*- coding: utf-8 -*-
"""
KLNCE Smart Transport System — Main Flask Application Entry Point.
PyMongo / MongoDB Atlas backed.
"""

import os
import sys

# Ensure backend directory is in sys.path regardless of execution directory
backend_dir = os.path.dirname(os.path.abspath(__file__))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from flask import Flask, jsonify
from dotenv import load_dotenv
from flask_jwt_extended import JWTManager

load_dotenv(os.path.join(backend_dir, '.env'))

# Verify critical external packages with clear error messages
try:
    from flask_cors import CORS
except ImportError as e:
    missing_pkg = e.name
    print(f"\n[KLNCE Transport ERROR] Missing required package: '{missing_pkg}'")
    print("Please install backend dependencies with:")
    print("    pip install flask-cors pymongo dnspython\n")
    raise

from models.database import init_db, get_db
from config import get_config
from routes.auth import auth_bp
from routes.schedules import schedules_bp
from routes.daily_schedules import daily_schedules_bp
from routes.buses import buses_bp
from routes.gps import gps_bp
from routes.notifications import notifications_bp
from routes.users import users_bp
from routes.students import students_bp
from routes.sms import sms_bp
from routes.sms_auto import sms_auto_bp
from routes.announcements import announcements_bp


def create_app(config_class=None):
    app = Flask(__name__)

    # Load configuration
    if config_class is None:
        config_class = get_config()
    app.config.from_object(config_class)

    # JWT configuration (uses SECRET_KEY from config, or fallback)
    app.config.setdefault(
        'JWT_SECRET_KEY',
        os.environ.get('JWT_SECRET_KEY', 'klnce-jwt-secret-key-2026-production-change')
    )
    # Token expiry: 30 days. Override via JWT_ACCESS_TOKEN_EXPIRES_DAYS env var.
    # Set to 0 in env to disable expiry (not recommended for production).
    _expiry_days = int(os.environ.get('JWT_ACCESS_TOKEN_EXPIRES_DAYS', '30'))
    if _expiry_days > 0:
        from datetime import timedelta
        app.config['JWT_ACCESS_TOKEN_EXPIRES'] = timedelta(days=_expiry_days)
    else:
        app.config['JWT_ACCESS_TOKEN_EXPIRES'] = False  # disabled (dev only)

    # Initialise MongoDB Connection & Seed Concurrency-Safe ID Counters
    init_db(app)

    JWTManager(app)

    # CORS configuration for Flutter Mobile & Web
    CORS(
        app,
        resources={r"/*": {"origins": "*"}},
        allow_headers=["*"],
        methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    )

    @app.before_request
    def handle_preflight():
        from flask import request
        if request.method == "OPTIONS":
            response = app.make_default_options_response()
            response.headers['Access-Control-Allow-Origin'] = '*'
            response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, Accept, Origin, X-Requested-With, bypass-tunnel-reminder, *'
            response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
            return response

    @app.after_request
    def after_request_cors(response):
        response.headers['Access-Control-Allow-Origin'] = '*'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, Accept, Origin, X-Requested-With, bypass-tunnel-reminder, *'
        response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
        return response

    # Register Blueprints
    app.register_blueprint(auth_bp)
    app.register_blueprint(schedules_bp)
    app.register_blueprint(daily_schedules_bp)
    app.register_blueprint(buses_bp)
    app.register_blueprint(gps_bp)
    app.register_blueprint(notifications_bp)
    app.register_blueprint(users_bp)
    app.register_blueprint(students_bp)
    app.register_blueprint(sms_bp)
    app.register_blueprint(sms_auto_bp)
    app.register_blueprint(announcements_bp)

    # Health check & root endpoints
    @app.route('/')
    def root():
        return jsonify({
            'name': 'KLNCE Smart Transport API',
            'version': '1.0.0',
            'institution': 'K.L.N. College of Engineering & Arts and Science College',
            'status': 'online',
            'endpoints': {
                'health': '/api/health',
                'published_schedule': '/api/schedules/published',
                'search_buses': '/api/buses/search?stop=Teppakulam',
                'current_user': '/api/auth/me'
            }
        })

    @app.route('/api/health')
    @app.route('/health')
    def health():
        import logging as _log
        try:
            get_db().command('ping')
            db_status = 'connected'
            http_code = 200
        except Exception as e:
            _log.error('[KLNCE health] MongoDB ping failed: %s', e)
            db_status = f'disconnected ({type(e).__name__})'
            http_code = 503

        return jsonify({
            'status': 'healthy' if http_code == 200 else 'degraded',
            'database': db_status,
            'institution': 'KLNCE Madurai',
            'version': '1.0.0',
        }), http_code

    return app


app = create_app()

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False, use_reloader=False)
