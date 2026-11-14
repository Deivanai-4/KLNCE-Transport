"""
models/database.py — Raw MySQL connection pool for complex queries.

Provides:
  - get_db_connection() : returns a mysql-connector-python connection
  - get_db_cursor()     : context manager that auto-commits and closes
"""

import os
import logging
from contextlib import contextmanager
from typing import Generator

import mysql.connector
from mysql.connector import pooling
from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Connection pool (created once at module import)
# ---------------------------------------------------------------------------
_POOL_SIZE = int(os.environ.get("DB_POOL_SIZE", 5))

_pool: pooling.MySQLConnectionPool | None = None


def _get_pool() -> pooling.MySQLConnectionPool:
    """Return (or lazily create) the shared connection pool."""
    global _pool
    if _pool is None:
        try:
            _pool = pooling.MySQLConnectionPool(
                pool_name="klnce_pool",
                pool_size=_POOL_SIZE,
                host=os.environ.get("DB_HOST", "localhost"),
                port=int(os.environ.get("DB_PORT", 3306)),
                user=os.environ.get("DB_USER", "root"),
                password=os.environ.get("DB_PASSWORD", ""),
                database=os.environ.get("DB_NAME", "klnce_transport"),
                charset="utf8mb4",
                use_unicode=True,
                autocommit=False,
            )
            logger.info("MySQL connection pool created (size=%d).", _POOL_SIZE)
        except mysql.connector.Error as exc:
            logger.error("Failed to create MySQL pool: %s", exc)
            raise
    return _pool


def get_db_connection() -> mysql.connector.connection.MySQLConnection:
    """
    Return a connection from the pool.

    The caller is responsible for calling `.commit()` / `.rollback()`
    and `.close()` (which returns the connection to the pool).
    """
    return _get_pool().get_connection()


@contextmanager
def get_db_cursor(dictionary: bool = True, commit: bool = True) -> Generator:
    """
    Context manager that yields a cursor and handles commit/rollback/close.

    Usage::

        with get_db_cursor() as cursor:
            cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
            row = cursor.fetchone()

    Args:
        dictionary: If True the cursor returns rows as dicts (default True).
        commit:     If True auto-commit on success (default True).
    """
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=dictionary)
    try:
        yield cursor
        if commit:
            conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        cursor.close()
        conn.close()
