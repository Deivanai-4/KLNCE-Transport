"""
models/__init__.py — SQLAlchemy db instance.

Import `db` from here everywhere in the application.
"""

from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()
