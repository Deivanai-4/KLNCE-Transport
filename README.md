# KLNCE Smart Transport System

A unified smart transport and college bus management platform for **K.L.N. College of Engineering** & **K.L.N. Arts & Sciences College**, Madurai, Tamil Nadu.

---

## 🌟 Key Features

1. **Automated Timetable Upload & Bilingual OCR Extraction**
   - Admin uploads printed or scanned bus schedules (JPG, PNG, PDF).
   - Python-powered OCR with mixed Tamil (`தமிழ்`) and English text extraction.
   - Interactive split-screen verification UI: original document preview alongside editable data table.
   - Guaranteed verification workflow: unapproved OCR drafts are never published to students.
2. **Student & Staff Mobile Application (Flutter)**
   - Fast boarding stop search (bilingual support: e.g. "Teppakulam" or "தெப்பக்குளம்").
   - Detailed bus routes with sequence of stops and estimated arrival times.
   - Published schedules use Indian Standard Time: "To campus" is visible from midnight until 12:00 PM, "From campus" from 12:00 PM until 9:00 PM, and no schedule is shown from 9:00 PM until the next midnight reset. Expired schedules are hidden, not deleted.
   - **Offline Access:** Timetables cached locally via SQLite (`sqflite`). Works without internet on campus.
   - Live GPS tracking of college buses on Google Maps.
3. **Admin Web Dashboard (Flutter Web)**
   - Laptop-optimized dashboard deployed on Vercel.
   - Schedule upload, verification, and 1-click publishing.
   - Manual timetable entry and route editor.
   - Push notifications to all student devices via Firebase Cloud Messaging (FCM).
   - Emergency SMS alerts via MSG91 / GSM module for students without smartphones.

---

## 🛠️ Technology Stack

| Layer | Technology | Purpose |
|:---|:---|:---|
| **Mobile & Web Frontend** | Flutter + Dart (v3.0+) | Cross-platform student mobile app & admin web dashboard |
| **Backend API** | Python 3.11 + Flask 3.0 | Business logic, Firebase token verification, and REST API |
| **Database** | MySQL 8.0 (UTF8MB4) | Relational storage for users, schedules, routes, stops, and GPS logs |
| **Authentication** | Firebase Authentication | Email/password sign-in and Firebase ID tokens |
| **Mobile Offline Cache** | SQLite (`sqflite`) | Offline timetable search and viewing on mobile devices |
| **OCR Engine** | PaddleOCR & OpenCV / Tesseract | Bilingual Tamil + English table text extraction |
| **Push Notifications** | Firebase Cloud Messaging (FCM) | Real-time push alerts to mobile phones |
| **SMS Gateway** | MSG91 / GSM SIM Module | Direct cellular SMS for offline alerts |
| **Live Maps & GPS** | Google Maps SDK + Geolocator | Real-time college bus location tracking |

---

## 🚀 Quick Start Guide

### 1. Database Setup
```bash
# Create database and tables
mysql -u root -p < database/schema.sql

# Existing installations must also apply the Firebase auth schema migration:
mysql -u root -p klnce_transport < database/migrations/20261115_firebase_auth.sql

# Seed catalog of 48 stops and Nov 10 bus schedule
mysql -u root -p klnce_transport < database/seed_data.sql
```

### 2. Backend Setup (Python + Flask)
```bash
cd backend

# Create and activate virtual environment
python -m venv venv
# On Windows:
.\venv\Scripts\activate
# On Linux/macOS:
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Copy environment variables
cp .env.example .env
# Edit .env with your MySQL credentials
# Set FIREBASE_CREDENTIALS to the Firebase service-account JSON for this project

# Run development server
python app.py
# Server runs on http://localhost:5000
```

### 3. Frontend Setup (Flutter)
Enable Email/Password sign-in in Firebase Authentication and register Android
and Web apps in the Firebase project. Configure the app's public Firebase values
(`FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`,
`FIREBASE_PROJECT_ID`, and `FIREBASE_AUTH_DOMAIN` for Web) as build-time Dart
defines. These are Firebase client configuration values, not service-account
secrets.

The backend verifies ID tokens using the Firebase service-account JSON in
`FIREBASE_CREDENTIALS`. Transport users must have an active row in the `users`
table whose email exactly matches their verified Firebase email; the database
role remains authoritative. Create Firebase accounts and verify their email
before linking profiles. Use `backend/set_admin_profile.py` for administrator
profiles.

```bash
cd frontend

# Install Flutter dependencies
flutter pub get

# Run on Chrome (Admin Web Dashboard)
flutter run -d chrome --dart-define=API_BASE_URL=https://YOUR_BACKEND_HOST/api --dart-define=FIREBASE_API_KEY=YOUR_API_KEY --dart-define=FIREBASE_APP_ID=YOUR_WEB_APP_ID --dart-define=FIREBASE_MESSAGING_SENDER_ID=YOUR_SENDER_ID --dart-define=FIREBASE_PROJECT_ID=YOUR_PROJECT_ID --dart-define=FIREBASE_AUTH_DOMAIN=YOUR_PROJECT_ID.firebaseapp.com

# Run on an Android emulator (Student App)
flutter run -d <emulator-device-id> --dart-define=API_BASE_URL=http://10.0.2.2:5000/api --dart-define=FIREBASE_API_KEY=YOUR_API_KEY --dart-define=FIREBASE_APP_ID=YOUR_ANDROID_APP_ID --dart-define=FIREBASE_MESSAGING_SENDER_ID=YOUR_SENDER_ID --dart-define=FIREBASE_PROJECT_ID=YOUR_PROJECT_ID
```

### Mobile Network / Production API
For cellular-data sign-in, the API must be publicly reachable over HTTPS; a
laptop's local IP address only works on its local network. A practical setup
for this project is a Railway Flask web service plus a Railway MySQL service,
with Vercel continuing to host the Flutter web dashboard.

1. In Railway, create a project with a MySQL service.
2. Deploy the `backend` directory as a web service. Its `Procfile` starts
   Gunicorn and binds to Railway's assigned port.
3. Set the web service variables `FLASK_ENV=production`, `DB_HOST`, `DB_PORT`,
   `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `SECRET_KEY`, and `FIREBASE_CREDENTIALS`
   using values from your MySQL service. Keep secrets in Railway's environment
   settings; do not commit them.
4. Load `database/schema.sql` and `database/seed_data.sql` into the hosted
   database, then enable a public HTTPS domain for the API.
5. Verify the API health endpoint:

```text
https://YOUR_BACKEND_HOST/api/health
```

Set the Vercel project environment variable `API_BASE_URL` to
`https://YOUR_BACKEND_HOST/api` and set the Firebase client configuration
variables documented above for every environment you deploy. The Vercel build
passes these values into Flutter and fails clearly if a required value is
missing.

For Android, provide the same API base URL (including `/api`) when running or
building the app:

```bash
cd frontend
flutter run -d <device-id> --dart-define=API_BASE_URL=https://YOUR_BACKEND_HOST/api --dart-define=FIREBASE_API_KEY=YOUR_API_KEY --dart-define=FIREBASE_APP_ID=YOUR_ANDROID_APP_ID --dart-define=FIREBASE_MESSAGING_SENDER_ID=YOUR_SENDER_ID --dart-define=FIREBASE_PROJECT_ID=YOUR_PROJECT_ID
flutter build apk --release --dart-define=API_BASE_URL=https://YOUR_BACKEND_HOST/api --dart-define=FIREBASE_API_KEY=YOUR_API_KEY --dart-define=FIREBASE_APP_ID=YOUR_ANDROID_APP_ID --dart-define=FIREBASE_MESSAGING_SENDER_ID=YOUR_SENDER_ID --dart-define=FIREBASE_PROJECT_ID=YOUR_PROJECT_ID
```

Flutter web debug defaults to the local backend. Android builds require an
explicit `API_BASE_URL`, because emulator and physical-phone addresses differ.
For a physical phone on the same Wi-Fi as the computer running Flask, use:

```bash
cd frontend
flutter run -d <phone-device-id> --dart-define=API_BASE_URL=http://<COMPUTER-LAN-IP>:5000/api
```

Keep Flask running and allow port 5000 through the computer's firewall. This
local address works only on the same network; cellular data requires the public
HTTPS backend URL. Release builds require HTTPS and show an explicit
configuration error if `API_BASE_URL` is missing.

---

### Daily Bus Schedule Management (Stage 3)
Allows administrators to manage date-specific bus numbers, routes, and individual stop timings for each day and session (Morning / Afternoon).
- `GET /api/daily-schedules?date=YYYY-MM-DD&session=morning|afternoon`: Fetch daily schedules (students see published only; admins see drafts & published)
- `GET /api/daily-schedules/<id>`: Fetch single schedule detail
- `POST /api/daily-schedules`: (Admin) Create daily schedule (Draft / Published) with multiple buses & stops
- `PUT /api/daily-schedules/<id>`: (Admin) Update daily schedule (auto-marks `is_updated = True` if already published)
- `POST /api/daily-schedules/<id>/publish`: (Admin) Publish schedule to students
- `DELETE /api/daily-schedules/<id>`: (Admin) Delete draft or published schedule

---

### SMS Confirmation, Bulk Sending & Status Tracking (Stage 7)
Allows the transport administrator to compose SMS alerts, preview and validate recipients, confirm dispatch parameters, send bulk messages sequentially from their phone SIM, and track the live status of every single message.

#### 1. SMS Composer
- **Multi-Targeting Modes:**
  - All active transport students
  - Particular bus route (with dropdown)
  - Particular regular bus (with dropdown)
  - Individual students (searchable multi-select picker with name, register number, and route filters)
- **Live Character & Segment Counter:**
  - Automatic detection of **GSM-7** (160 chars single / 153 chars multi-segment) vs **Unicode UCS-2** (70 chars single / 67 chars multi-segment for bilingual Tamil `தமிழ்` text or emojis).
  - Real-time remaining characters counter and total SMS credits indicator.
- **Message Preview:** Interactive phone handset mockup rendering header, timestamps, and message bubble.
- **Quick Templates:** Delay notices, schedule publication alerts, route change notices, bilingual Tamil alerts.

#### 2. Recipient Preview & Safeguards
- **Recipient Analytics Display:**
  - Recipient category & Route / Bus selection
  - Total selected students
  - Valid mobile numbers count
  - Invalid mobile numbers count (with specific rejection reasons)
  - Duplicate mobile numbers count (grouped by shared numbers)
- **Duplicate Prevention:**
  - Enabled by default to prevent sending duplicate messages to the same mobile number (e.g. siblings sharing parent phone).
  - Explicit approval switch: allows administrator to override and send duplicates if required.
- **Privacy Protection:**
  - Complete phone numbers are masked (`+91 98*** **210`) across preview lists, confirmation summaries, and status tracking tables.

#### 3. Confirmation Screen
- Pre-dispatch verification showing:
  - Full message content & character audit
  - Recipient category & effective student count
  - Estimated SMS segments per student & total SMS credits
  - Selected physical SIM (carrier, slot index, display name, subscription ID)
  - Sending Android device model, OS version, and telephony status
  - Pre-flight checklist for cellular signal and carrier balance

#### 4. Bulk Sending & Message Status Tracking
- **Sequential Dispatch Engine:**
  - Transmits messages one-by-one via Android `SmsManager` with inter-message delays (default 750ms) to avoid carrier network congestion.
  - Live progress modal with progress bar, percentage, Submitted (Green), Failed (Red), Remaining (Grey) counters, and live event log.
  - Pause & Resume dispatch controls.
- **Message-by-Message Audit & Tracking:**
  - Detailed campaign screen monitoring every message's exact delivery state:
    - `sent_to_sms_service` (submitted to Android telephony modem)
    - `failed` (with carrier error diagnosis: `NO_SERVICE`, `RADIO_OFF`, `GENERIC_FAILURE`, etc.)
    - `pending` / `sending`
  - Status filter chips (All, Submitted, Failed, Pending) and search by student name or register number.
  - **1-Click Retry Failed:** Resets failed recipients to pending and allows immediate re-dispatch of failed messages.

#### SMS API Endpoints
- `GET /api/sms/recipients`: Query eligible recipients with validation preview, duplicate detection, and masking.
- `POST /api/sms/calculate-segments`: Calculate SMS character count, encoding, and segments.
- `POST /api/sms/campaigns`: Create an SMS broadcast campaign session with duplicate prevention.
- `PUT /api/sms/campaigns/<id>/status`: Update dispatch progress and individual recipient status from Android device.
- `GET /api/sms/campaigns`: List campaign history with summaries.
- `GET /api/sms/campaigns/<id>`: Get campaign details with status filtering and recipient search.
- `POST /api/sms/campaigns/<id>/retry-failed`: Reset failed messages in a campaign for retry dispatch.

---


