# KLNCE Smart Transport System — Database Setup Guide

This directory contains the MySQL relational database schema and initial seed data for the KLNCE Smart Transport System.

---

## Prerequisites
- **MySQL 8.0+** or **MariaDB 10.5+** installed locally or running via Docker/Railway/TiDB.
- Character set must be `utf8mb4` to support bilingual Tamil (`தமிழ்`) and English text correctly.

---

## Quick Setup Steps

### 1. Local MySQL Setup (Terminal / PowerShell)

```bash
# Log in to MySQL as root
mysql -u root -p

# Inside MySQL prompt:
CREATE DATABASE IF NOT EXISTS klnce_transport
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
exit;
```

### 2. Import Schema and Seed Data

```bash
# Import table definitions
mysql -u root -p klnce_transport < database/schema.sql

# Import stops catalog and published schedule data
mysql -u root -p klnce_transport < database/seed_data.sql
```

### 3. Verify Database Tables

```sql
USE klnce_transport;
SHOW TABLES;

-- Should show:
-- bus_routes
-- gps_locations
-- master_stops
-- notifications
-- route_stops
-- schedule_documents
-- users
```

---

## Administrator Account

Seed data does not create accounts with shared demo credentials. After
configuring `backend/.env` and installing the backend dependencies, create or
update the administrator securely; the password is requested without echo and
stored as a bcrypt hash:

```bash
cd backend
python set_admin_credentials.py --email klnce@transport
```

If the database has multiple administrators, select the one to update with
`--current-email existing-admin@example.com`. The script verifies login through
the authentication API before reporting success.

---

## Production / Cloud Setup (Railway or TiDB)

### Using Railway MySQL Plugin
1. In your Railway project, click **New** -> **Database** -> **MySQL**.
2. Copy the `MYSQL_URL` connection string provided by Railway.
3. Import the files using your MySQL client:
   ```bash
   mysql -h <RAILWAY_HOST> -P <PORT> -u <USER> -p<PASSWORD> <DB_NAME> < database/schema.sql
   mysql -h <RAILWAY_HOST> -P <PORT> -u <USER> -p<PASSWORD> <DB_NAME> < database/seed_data.sql
   ```

### Using TiDB Serverless (Free 25 GB MySQL Cloud DB)
1. Sign up at [tidbcloud.com](https://tidbcloud.com) and create a free serverless cluster.
2. In the TiDB SQL Editor, copy and execute the contents of `schema.sql`, followed by `seed_data.sql`.
3. Set your backend `.env` variables (`DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `DB_PORT=4000`).

