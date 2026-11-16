import os
import pymysql
from pymongo import MongoClient
from dotenv import load_dotenv

load_dotenv()

# Test MySQL connection
try:
    mysql_conn = pymysql.connect(
        host=os.getenv("MYSQL_HOST"),
        port=int(os.getenv("MYSQL_PORT", 3306)),
        user=os.getenv("MYSQL_USER"),
        password=os.getenv("MYSQL_PASSWORD"),
        database=os.getenv("MYSQL_DATABASE")
    )
    print("SUCCESS: MySQL connected!")
    mysql_conn.close()

except Exception as e:
    print("MySQL connection failed:", e)


# Test MongoDB connection
try:
    client = MongoClient(
        os.getenv("MONGODB_URI"),
        serverSelectionTimeoutMS=10000
    )

    client.admin.command("ping")
    print("SUCCESS: MongoDB Atlas connected!")

    client.close()

except Exception as e:
    print("MongoDB connection failed:", e)
