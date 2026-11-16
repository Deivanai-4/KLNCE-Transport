import os
from pathlib import Path
import pymysql
from pymongo import MongoClient
from dotenv import load_dotenv

# Load migration/.env or root .env
env_path = Path(__file__).with_name(".env")
if not env_path.exists():
    env_path = Path(__file__).parent.parent / ".env"
load_dotenv(env_path)

TABLES = [
    "users",
    "bus_routes",
    "master_stops",
    "route_stops",
    "gps_locations",
    "notifications",
    "schedule_documents"
]

mysql = None
mongo_client = None

try:
    print("=" * 65)
    print("       KLNCE TRANSPORT - DATABASE MIGRATION PREVIEW")
    print("=" * 65)

    # Connect to MySQL
    print("\nConnecting to MySQL...")
    mysql = pymysql.connect(
        host=os.getenv("MYSQL_HOST", "127.0.0.1"),
        port=int(os.getenv("MYSQL_PORT", 3306)),
        user=os.getenv("MYSQL_USER", "root"),
        password=os.getenv("MYSQL_PASSWORD"),
        database=os.getenv("MYSQL_DATABASE", "klnce_transport"),
        cursorclass=pymysql.cursors.DictCursor
    )
    print(f"Connected to MySQL: {os.getenv('MYSQL_DATABASE', 'klnce_transport')}")

    # Connect to MongoDB Atlas
    print("\nConnecting to MongoDB Atlas...")
    mongo_client = MongoClient(
        os.getenv("MONGODB_URI"),
        serverSelectionTimeoutMS=10000
    )
    mongo_client.admin.command("ping")
    db_name = os.getenv("MONGODB_DATABASE", "klnce_admin")
    mongo_db = mongo_client[db_name]
    print(f"Connected to MongoDB Atlas: {db_name}")

    print("\n" + "=" * 65)
    print(f"{'Table / Collection':<22} | {'MySQL Rows':>10} | {'MongoDB Docs':>12} | {'Status'}")
    print("-" * 65)

    total_mysql_records = 0
    total_mongo_records = 0

    with mysql.cursor() as cursor:
        for table in TABLES:
            # Query MySQL count
            try:
                cursor.execute(f"SELECT COUNT(*) AS total FROM `{table}`")
                res = cursor.fetchone()
                mysql_count = res["total"] if res else 0
            except Exception as e:
                mysql_count = f"Error"

            # Query MongoDB count
            try:
                mongo_count = mongo_db[table].count_documents({})
            except Exception:
                mongo_count = 0

            if isinstance(mysql_count, int):
                total_mysql_records += mysql_count
            if isinstance(mongo_count, int):
                total_mongo_records += mongo_count

            status = "Ready to migrate" if (isinstance(mysql_count, int) and mysql_count > 0 and mongo_count == 0) else (
                "Migrated" if (isinstance(mysql_count, int) and mysql_count > 0 and mongo_count >= mysql_count) else "Empty"
            )

            print(f"{table:<22} | {str(mysql_count):>10} | {str(mongo_count):>12} | {status}")

    print("=" * 65)
    print(f"{'TOTALS':<22} | {total_mysql_records:>10} | {total_mongo_records:>12} |")
    print("=" * 65)

    print(f"\nMigration Summary:")
    print(f"  • Source Database : MySQL ({os.getenv('MYSQL_DATABASE', 'klnce_transport')})")
    print(f"  • Target Database : MongoDB Atlas ({db_name})")
    print(f"  • Records to Sync : {total_mysql_records} records across {len(TABLES)} tables")
    print(f"  • Status          : Ready for migration.\n")

except Exception as e:
    print(f"\nMigration preview failed: {e}")

finally:
    if mysql:
        mysql.close()
    if mongo_client:
        mongo_client.close()
