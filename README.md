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
| **Backend API** | Python 3.11 + Flask 3.0 | Business logic, authentication, and REST API |
| **Database** | MySQL 8.0 (UTF8MB4) | Relational storage for users, schedules, routes, stops, and GPS logs |
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

# Run development server
python app.py
# Server runs on http://localhost:5000
```

### 3. Frontend Setup (Flutter)
```bash
cd frontend

# Install Flutter dependencies
flutter pub get

# Run on Chrome (Admin Web Dashboard)
flutter run -d chrome

# Run on an Android emulator (Student App)
flutter run -d <emulator-device-id> --dart-define=API_BASE_URL=http://10.0.2.2:5000/api
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
   `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `SECRET_KEY`, and `JWT_SECRET_KEY`
   using values from your MySQL service. Keep secrets in Railway's environment
   settings; do not commit them.
4. Load `database/schema.sql` and `database/seed_data.sql` into the hosted
   database, then enable a public HTTPS domain for the API.
5. Verify the API health endpoint:

```text
https://YOUR_BACKEND_HOST/api/health
```

Set the Vercel project environment variable `API_BASE_URL` to
`https://YOUR_BACKEND_HOST/api` for every environment you deploy. The Vercel
build now passes this URL into Flutter and fails clearly if it is missing.

For Android, provide the same API base URL (including `/api`) when running or
building the app:

```bash
cd frontend
flutter run -d <device-id> --dart-define=API_BASE_URL=https://YOUR_BACKEND_HOST/api
flutter build apk --release --dart-define=API_BASE_URL=https://YOUR_BACKEND_HOST/api
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


