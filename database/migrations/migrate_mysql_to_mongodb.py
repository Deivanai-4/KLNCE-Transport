import os
from pathlib import Path
from datetime import date, datetime
from decimal import Decimal

import pymysql
from pymongo import MongoClient
from bson.decimal128 import Decimal128
from dotenv import load_dotenv

# Load environment variables from migration/.env
load_dotenv(Path(__file__).with_name(".env"))

TABLES = [
    "users",
    "bus_routes",
    "master_stops",
    "route_stops",
    "gps_locations",
    "notifications",
    "schedule_documents"
]

EXPECTED_TOTAL = 1320


def convert_value(value):
    """Convert MySQL values into MongoDB-compatible values."""
    if isinstance(value, datetime):
        return value

    if isinstance(value, date):
        return value.isoformat()

    if isinstance(value, Decimal):
        return Decimal128(value)

    if isinstance(value, dict):
        return {key: convert_value(val) for key, val in value.items()}

    if isinstance(value, list):
        return [convert_value(item) for item in value]

    return value


mysql = None
mongo_client = None

try:
    print("=" * 65)
    print("KLNCE TRANSPORT - MYSQL TO MONGODB MIGRATION")
    print("=" * 65)

    # 1. Connect to MySQL
    print("\nConnecting to MySQL...")

    mysql = pymysql.connect(
        host=os.getenv("MYSQL_HOST"),
        port=int(os.getenv("MYSQL_PORT", "3306")),
        user=os.getenv("MYSQL_USER"),
        password=os.getenv("MYSQL_PASSWORD"),
        database=os.getenv("MYSQL_DATABASE"),
        cursorclass=pymysql.cursors.DictCursor
    )

    print("MySQL connected:", os.getenv("MYSQL_DATABASE"))

    # 2. Connect to MongoDB
    print("\nConnecting to MongoDB Atlas...")

    mongo_client = MongoClient(
        os.getenv("MONGODB_URI"),
        serverSelectionTimeoutMS=10000
    )

    mongo_client.admin.command("ping")

    database = mongo_client[os.getenv("MONGODB_DATABASE")]

    print("MongoDB connected:", os.getenv("MONGODB_DATABASE"))

    # 3. Read source records and primary keys
    print("\nReading MySQL tables...")

    source_data = {}
    primary_keys = {}
    total_records = 0

    with mysql.cursor() as cursor:
        for table in TABLES:

            cursor.execute(
                f"SHOW KEYS FROM `{table}` WHERE Key_name = 'PRIMARY'"
            )

            key_rows = cursor.fetchall()

            if len(key_rows) != 1:
                raise Exception(
                    f"{table} must have exactly one primary-key column."
                )

            primary_key = key_rows[0]["Column_name"]
            primary_keys[table] = primary_key

            cursor.execute(f"SELECT * FROM `{table}`")
            rows = cursor.fetchall()

            source_data[table] = rows
            total_records += len(rows)

            print(f"{table}: {len(rows)} records")

    if total_records != EXPECTED_TOTAL:
        raise Exception(
            f"Expected {EXPECTED_TOTAL} records, "
            f"but MySQL returned {total_records}. Migration stopped."
        )

    # 4. Check existing MongoDB records
    print("\nChecking MongoDB collections...")

    for table in TABLES:
        collection = database[table]
        primary_key = primary_keys[table]

        source_ids = {
            row[primary_key] for row in source_data[table]
        }

        existing_ids = {
            document["_id"]
            for document in collection.find({}, {"_id": 1})
        }

        if not existing_ids.issubset(source_ids):
            raise Exception(
                f"{table} contains documents not matching MySQL IDs. "
                "Migration stopped to protect existing MongoDB data."
            )

        print(
            f"{table}: {len(existing_ids)} existing documents "
            f"can be safely resumed."
        )

    # 5. Ask for explicit confirmation
    print("\n" + "=" * 65)
    print("SOURCE: MySQL klnce_transport")
    print("TARGET: MongoDB klnce_transport")
    print("TOTAL RECORDS:", total_records)
    print("MySQL data will NOT be deleted or modified.")
    print("=" * 65)

    confirmation = input(
        "\nType MIGRATE to begin transferring the records: "
    ).strip()

    if confirmation != "MIGRATE":
        print("\nMigration cancelled. No records were transferred.")
        raise SystemExit(0)

    # 6. Transfer records
    print("\nStarting migration...\n")

    for table in TABLES:
        collection = database[table]
        primary_key = primary_keys[table]
        rows = source_data[table]

        for row in rows:
            document = convert_value(dict(row))

            original_id = document[primary_key]

            # Keep the original MySQL primary key as MongoDB _id.
            document["_id"] = original_id

            # Exclude _id from $set because MongoDB does not allow
            # changing an existing document's _id.
            document_fields = {
                key: value
                for key, value in document.items()
                if key != "_id"
            }

            collection.update_one(
                {"_id": original_id},
                {"$set": document_fields},
                upsert=True
            )

        print(f"Completed: {table} ({len(rows)} records)")

    # 7. Verify migrated record counts
    print("\n" + "=" * 65)
    print("FINAL MIGRATION VERIFICATION")
    print("=" * 65)

    verified_total = 0

    for table in TABLES:
        mysql_count = len(source_data[table])
        mongo_count = database[table].count_documents({})

        print(
            f"{table:22} "
            f"MySQL: {mysql_count:5} | "
            f"MongoDB: {mongo_count:5}"
        )

        if mysql_count != mongo_count:
            raise Exception(
                f"Count mismatch in {table}. "
                "Do not delete or modify MySQL data."
            )

        verified_total += mongo_count

    print("-" * 65)
    print("TOTAL VERIFIED:", verified_total)

    if verified_total == EXPECTED_TOTAL:
        print("\nSUCCESS! ALL RECORD COUNTS MATCH.")
        print("MySQL source database remains unchanged.")

except SystemExit:
    pass

except Exception as error:
    print("\nMIGRATION ERROR:", error)
    print("Check the error before attempting another step.")
    print("Your original MySQL database has not been deleted.")

finally:
    if mysql:
        mysql.close()

    if mongo_client:
        mongo_client.close()

    print("\nDatabase connections closed.")
