"""
models/database.py — PyMongo connection manager and concurrency-safe ID counter.

Provides:
  - init_db(app)                : initialise the MongoDB client once per Flask app
  - get_db()                    : return the active database handle
  - get_mongo_client()          : return the raw MongoClient (for session/transaction)
  - get_next_sequence(coll)     : atomically allocate the next integer _id
  - seed_counters_if_needed(db) : seed counter collection from existing max(_id) values
                                   using $setOnInsert — never resets an existing counter
"""

import logging
import os
from contextlib import contextmanager

from dotenv import load_dotenv
from pymongo import MongoClient, ASCENDING, DESCENDING, ReturnDocument
from pymongo.collection import Collection
from pymongo.errors import PyMongoError

load_dotenv()

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Module-level singletons (populated by init_db)
# ---------------------------------------------------------------------------
_client: MongoClient | None = None
_db = None  # pymongo.database.Database

# Collections that use auto-increment integer IDs
_SEQUENCE_COLLECTIONS = [
    "users",
    "bus_routes",
    "master_stops",
    "route_stops",
    "gps_locations",
    "notifications",
    "schedule_documents",
    "daily_schedules",
    "students",
    "sms_campaigns",
    "announcements",
]


# ---------------------------------------------------------------------------
# Initialisation
# ---------------------------------------------------------------------------

def init_db(app) -> None:
    """
    Initialise the PyMongo client using MONGODB_URI / MONGODB_DATABASE
    from the Flask application configuration.
    Call once per Flask app. Idempotent if already initialized.
    """
    global _client, _db

    if _db is not None:
        return

    is_testing = app.config.get("TESTING", False) or os.environ.get("FLASK_ENV") == "testing"
    uri = app.config.get("MONGODB_URI") or os.environ.get("MONGODB_URI", "")
    db_name = app.config.get("MONGODB_DATABASE") or os.environ.get("MONGODB_DATABASE", "klnce_transport")

    if is_testing or not uri:
        logger.info("Using mongomock for test environment.")
        import mongomock
        _client = mongomock.MongoClient()
        _db = _client[db_name]
    else:
        # Production / development MongoDB Atlas connection.
        # - serverSelectionTimeoutMS: how long to wait for a server to be found
        # - connectTimeoutMS: TCP connection timeout per attempt
        # - socketTimeoutMS: how long to wait for a socket read/write
        # - maxPoolSize: connection pool for gunicorn multi-worker Render deploy
        # - retryWrites: Atlas recommended setting for resilient writes
        _client = MongoClient(
            uri,
            serverSelectionTimeoutMS=15000,
            connectTimeoutMS=10000,
            socketTimeoutMS=30000,
            maxPoolSize=10,
            retryWrites=True,
            retryReads=True,
        )
        _db = _client[db_name]

    logger.info("MongoDB connected (database: %s)", db_name)

    # Seed counters without overwriting existing values
    seed_counters_if_needed(_db)

    # Create indexes
    _create_indexes(_db)


def get_db():
    """Return the active PyMongo database handle."""
    if _db is None:
        raise RuntimeError("MongoDB not initialised. Call init_db(app) first.")
    return _db


def get_mongo_client() -> MongoClient:
    """Return the raw MongoClient (needed for session/transaction management)."""
    if _client is None:
        raise RuntimeError("MongoDB client not initialised. Call init_db(app) first.")
    return _client


# ---------------------------------------------------------------------------
# Concurrency-safe Integer ID Counter
# ---------------------------------------------------------------------------

def seed_counters_if_needed(db) -> None:
    """
    Seed the 'counters' collection from max(_id) of each data collection.
    Uses $setOnInsert — an existing counter is NEVER reset or decremented.
    Safe to call on every startup.
    """
    for coll_name in _SEQUENCE_COLLECTIONS:
        coll = db[coll_name]
        highest_doc = coll.find_one(sort=[("_id", DESCENDING)])
        max_id = 0
        if highest_doc:
            raw = highest_doc.get("_id")
            try:
                max_id = int(raw)
            except (TypeError, ValueError):
                max_id = 0

        # $setOnInsert only fires when the document is first created (upsert).
        # If the counter document already exists, the update does nothing.
        db["counters"].update_one(
            {"_id": coll_name},
            {"$setOnInsert": {"seq": max_id}},
            upsert=True,
        )
        logger.debug("Counter seeded for '%s': floor=%d", coll_name, max_id)


def get_next_sequence(collection_name: str) -> int:
    """
    Atomically increment and return the next integer ID for the given collection.
    Thread-safe and multi-process-safe via MongoDB find_one_and_update.
    Guarantees no ID collisions even if collections were pre-seeded or counters cleared.
    """
    db = get_db()

    # Ensure counter exists and is seeded from current max(_id) if missing
    counter = db["counters"].find_one({"_id": collection_name})
    if counter is None:
        highest_doc = db[collection_name].find_one(sort=[("_id", DESCENDING)])
        max_id = 0
        if highest_doc:
            raw = highest_doc.get("_id")
            try:
                max_id = int(raw)
            except (TypeError, ValueError):
                max_id = 0
        db["counters"].update_one(
            {"_id": collection_name},
            {"$setOnInsert": {"seq": max_id}},
            upsert=True,
        )

    result = db["counters"].find_one_and_update(
        {"_id": collection_name},
        {"$inc": {"seq": 1}},
        return_document=ReturnDocument.AFTER,
        upsert=True,
    )
    seq = int(result["seq"])

    # Double-check collision safety: advance if ID already occupied in collection
    while db[collection_name].find_one({"_id": seq}) is not None:
        result = db["counters"].find_one_and_update(
            {"_id": collection_name},
            {"$inc": {"seq": 1}},
            return_document=ReturnDocument.AFTER,
            upsert=True,
        )
        seq = int(result["seq"])

    return seq


# ---------------------------------------------------------------------------
# Index Creation (idempotent — safe to run on every startup)
# ---------------------------------------------------------------------------

def _create_indexes(db) -> None:
    """Create performance indexes on MongoDB collections. Idempotent."""
    try:
        db["users"].create_index("email", unique=True, name="users_email_unique")
        db["users"].create_index("role", name="users_role")
        db["users"].create_index("is_active", name="users_is_active")

        db["bus_routes"].create_index("schedule_id", name="bus_routes_schedule_id")
        db["bus_routes"].create_index("bus_code", name="bus_routes_bus_code")

        db["route_stops"].create_index("bus_route_id", name="route_stops_bus_route_id")
        db["route_stops"].create_index(
            [("bus_route_id", ASCENDING), ("stop_order", ASCENDING)],
            name="route_stops_route_order"
        )
        db["route_stops"].create_index("stop_name_en", name="route_stops_name_en")
        db["route_stops"].create_index("stop_name_ta", name="route_stops_name_ta")

        db["gps_locations"].create_index("bus_code", name="gps_bus_code")
        db["gps_locations"].create_index("is_active_trip", name="gps_is_active")
        db["gps_locations"].create_index(
            [("bus_code", ASCENDING), ("recorded_at", DESCENDING)],
            name="gps_bus_time"
        )
        # Compound index covering live-bus query (bus_code + is_active_trip + recorded_at)
        db["gps_locations"].create_index(
            [("bus_code", ASCENDING), ("is_active_trip", ASCENDING), ("recorded_at", DESCENDING)],
            name="gps_bus_active_time"
        )

        db["schedule_documents"].create_index("status", name="sched_status")
        db["schedule_documents"].create_index("trip_direction", name="sched_direction")
        db["schedule_documents"].create_index("effective_date", name="sched_eff_date")

        db["notifications"].create_index(
            [("sent_at", DESCENDING)], name="notif_sent_at"
        )
        db["master_stops"].create_index("standard_name_en", name="ms_name_en")

        # Daily Bus Schedules indexes
        db["daily_schedules"].create_index(
            [("date", ASCENDING), ("session", ASCENDING)],
            name="daily_sched_date_session"
        )
        db["daily_schedules"].create_index("status", name="daily_sched_status")

        # Student & Route Allocation indexes
        db["students"].create_index("register_number", unique=True, name="students_reg_no_unique")
        db["students"].create_index("route_name", name="students_route_name")
        db["students"].create_index("bus_number", name="students_bus_number")
        db["students"].create_index("department", name="students_department")
        db["students"].create_index("year", name="students_year")
        db["students"].create_index("is_transport_active", name="students_transport_active")
        db["students"].create_index("student_mobile", name="students_mobile")

        # SMS Campaigns indexes
        db["sms_campaigns"].create_index([("created_at", DESCENDING)], name="sms_campaigns_created_at")
        db["sms_campaigns"].create_index("status", name="sms_campaigns_status")
        db["sms_campaigns"].create_index("target_type", name="sms_campaigns_target_type")
        db["sms_campaigns"].create_index("route_name", name="sms_campaigns_route_name")
        db["sms_campaigns"].create_index("bus_number", name="sms_campaigns_bus_number")

        # Announcements indexes (Stage 9)
        db["announcements"].create_index(
            [("created_at", DESCENDING)], name="announcements_created_at"
        )
        db["announcements"].create_index("status", name="announcements_status")
        db["announcements"].create_index("category", name="announcements_category")
        db["announcements"].create_index("priority", name="announcements_priority")
        db["announcements"].create_index("target_type", name="announcements_target_type")
        db["announcements"].create_index("target_route", name="announcements_target_route")
        db["announcements"].create_index("target_bus", name="announcements_target_bus")
        db["announcements"].create_index(
            [("status", ASCENDING), ("priority", DESCENDING), ("created_at", DESCENDING)],
            name="announcements_student_feed"
        )
        # Text indexes for bilingual stop search (English-only terms benefit from text index)
        try:
            db["route_stops"].create_index(
                [("stop_name_en", "text"), ("stop_name_ta", "text")],
                name="route_stops_text_search"
            )
            db["master_stops"].create_index(
                [("standard_name_en", "text"), ("standard_name_ta", "text"), ("aliases", "text")],
                name="master_stops_text_search"
            )
        except PyMongoError as text_exc:
            logger.warning("Text index creation skipped (non-fatal): %s", text_exc)

        logger.info("MongoDB indexes created/verified.")
    except PyMongoError as exc:
        logger.warning("Index creation warning (non-fatal): %s", exc)
