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

# Existing database: allow Firebase-only profiles without a local password.
mysql -u root -p klnce_transport < database/migrations/20261115_firebase_auth.sql

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

Create and verify the administrator account in Firebase Authentication first.
Configure `FIREBASE_CREDENTIALS` in `backend/.env`, install the backend
dependencies, and run the profile-linking script:

```bash
cd backend
python set_admin_profile.py --email admin@example.com
```

The Firebase account's verified email must match the email supplied here.
If the database has multiple administrators, select the profile to update with
`--current-email existing-admin@example.com`. Other student, staff, and driver
profiles must likewise use the corresponding verified Firebase email.
The existing-database migration clears legacy bcrypt password hashes because
passwords are now handled exclusively by Firebase Authentication.

---

## Production / Cloud Setup (Railway or TiDB)

### Using Railway MySQL Plugin
1. In your Railway project, click **New** -> **Database** -> **MySQL**.
2. Copy the `MYSQL_URL` connection string provided by Railway.
3. Import the files using your MySQL client:
   ```bash
   mysql -h <RAILWAY_HOST> -P <PORT> -u <USER> -p<PASSWORD> <DB_NAME> < database/schema.sql
   mysql -h <RAILWAY_HOST> -P <PORT> -u <USER> -p<PASSWORD> <DB_NAME> < database/migrations/20261115_firebase_auth.sql
   mysql -h <RAILWAY_HOST> -P <PORT> -u <USER> -p<PASSWORD> <DB_NAME> < database/seed_data.sql
   ```

### Using TiDB Serverless (Free 25 GB MySQL Cloud DB)
1. Sign up at [tidbcloud.com](https://tidbcloud.com) and create a free serverless cluster.
2. In the TiDB SQL Editor, copy and execute the contents of `schema.sql`, followed by `seed_data.sql`.
3. Set your backend `.env` variables (`DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `DB_PORT=4000`).

