"""
models/__init__.py — PyMongo database exports.

Exports:
  - init_db
  - get_db
  - get_mongo_client
  - get_next_sequence
  - db (lazy attribute resolving to get_db())
"""

from models.database import (
    init_db,
    get_db,
    get_mongo_client,
    get_next_sequence,
)


def __getattr__(name):
    if name == 'db':
        return get_db()
    raise AttributeError(f"module '{__name__}' has no attribute '{name}'")
