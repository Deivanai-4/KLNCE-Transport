# -*- coding: utf-8 -*-
"""
Test Suite for Stage 8: Automatic Morning and Afternoon SMS Scheduling.
Validates:
  - Settings retrieval, updates, and emergency disable.
  - Rejection of unpublished or draft daily schedules.
  - Morning (6:30 AM) and Afternoon (2:00 PM) campaign preparation from published schedules.
  - Duplicate campaign prevention using {date}_{session}_v{version} keys.
  - Schedule update and revision campaign creation.
  - Confirmation Mode vs Automatic Mode.
  - Test trigger with single test mobile.
  - Pending confirmation retrieval and approval workflow.
"""

import os
import unittest
import bcrypt
from datetime import datetime, timezone
from flask_jwt_extended import create_access_token

os.environ["FLASK_ENV"] = "testing"

from app import create_app
from config import TestingConfig
from models.database import get_db
from models.user import User
from models.daily_schedule import DailySchedule
from models.sms_campaign import (
    SmsCampaign,
    STATUS_DRAFT,
    STATUS_PENDING_CONFIRMATION,
)
from models.sms_auto_settings import (
    SmsAutoSettings,
    POLICY_CONFIRMATION,
    POLICY_AUTOMATIC,
)


class SmsStage8Tests(unittest.TestCase):
    def setUp(self):
        self.app = create_app(TestingConfig)
        self.app_context = self.app.app_context()
        self.app_context.push()

        self.db = get_db()
        for coll in ["users", "students", "sms_campaigns", "sms_auto_settings", "daily_schedules", "counters"]:
            self.db[coll].delete_many({})

        # Admin user
        hashed_pw = bcrypt.hashpw("admin123".encode("utf-8"), bcrypt.gensalt()).decode("utf-8")
        self.admin = User(
            name="SMS Admin",
            email="smsadmin@klnce.edu",
            password_hash=hashed_pw,
            role="admin",
            college="both",
            phone="9876543210",
            is_active=True,
        )
        self.admin.save()

        self.client = self.app.test_client()
        with self.app.test_request_context():
            token = create_access_token(identity=self.admin.email)
            self.admin_headers = {"Authorization": f"Bearer {token}"}

        # Seed test students
        self.students_data = [
            {
                "_id": 1,
                "register_number": "91001",
                "name": "Kavitha S",
                "student_mobile": "9876543210",
                "route_name": "Route 4 - Tirunagar",
                "bus_number": "S1",
                "is_transport_active": True,
            },
            {
                "_id": 2,
                "register_number": "91002",
                "name": "Manojkumar P",
                "student_mobile": "9123456789",
                "route_name": "Route 2 - Anna Nagar",
                "bus_number": "S2",
                "is_transport_active": True,
            },
        ]
        self.db["students"].insert_many(self.students_data)

        self.test_date = "2026-11-20"

    def tearDown(self):
        self.app_context.pop()

    # ── 1. Settings, Confirmation Policy & Emergency Disable ─────────────────

    def test_default_settings_require_explicit_enable(self):
        res = self.client.get("/api/sms/auto-schedule/settings", headers=self.admin_headers)
        self.assertEqual(res.status_code, 200)
        data = res.get_json()["settings"]

        # Must be disabled by default until administrator explicitly enables
        self.assertFalse(data["is_enabled"])
        self.assertEqual(data["morning_time"], "06:30")
        self.assertEqual(data["afternoon_time"], "14:00")
        self.assertEqual(data["confirmation_policy"], POLICY_CONFIRMATION)
        self.assertIn("morning", data["enabled_sessions"])
        self.assertIn("afternoon", data["enabled_sessions"])

    def test_update_settings_and_policy(self):
        update_payload = {
            "is_enabled": True,
            "confirmation_policy": POLICY_CONFIRMATION,
            "morning_time": "06:30",
            "afternoon_time": "14:00",
            "test_phone": "9876543210",
        }
        res = self.client.put(
            "/api/sms/auto-schedule/settings",
            json=update_payload,
            headers=self.admin_headers,
        )
        self.assertEqual(res.status_code, 200)
        updated = res.get_json()["settings"]
        self.assertTrue(updated["is_enabled"])
        self.assertEqual(updated["test_phone"], "9876543210")

    def test_emergency_disable(self):
        # Enable first
        SmsAutoSettings(is_enabled=True).save()

        # Trigger emergency disable
        res = self.client.post("/api/sms/auto-schedule/emergency-disable", headers=self.admin_headers)
        self.assertEqual(res.status_code, 200)
        settings = res.get_json()["settings"]
        self.assertFalse(settings["is_enabled"])
        self.assertTrue(settings["emergency_disabled"])

    # ── 2. Morning & Afternoon Workflow with Schedule Validation ──────────────

    def test_prepare_rejects_unpublished_or_draft_schedule(self):
        # Explicitly enable auto SMS
        SmsAutoSettings(is_enabled=True).save()

        # 1. No schedule exists at all
        res_no_sched = self.client.post(
            "/api/sms/auto-schedule/prepare",
            json={"session": "morning", "date": self.test_date},
            headers=self.admin_headers,
        )
        self.assertEqual(res_no_sched.status_code, 400)
        self.assertIn("No daily bus schedule found", res_no_sched.get_json()["error"])

        # 2. Schedule exists but is in 'draft' status
        draft_sched = DailySchedule(
            date=self.test_date,
            session="morning",
            status="draft",
            version=1,
            buses=[{"bus_number": "S1", "route_name": "Route 4 - Tirunagar", "departure_time": "07:00 AM"}],
        )
        draft_sched.save()

        res_draft = self.client.post(
            "/api/sms/auto-schedule/prepare",
            json={"session": "morning", "date": self.test_date},
            headers=self.admin_headers,
        )
        self.assertEqual(res_draft.status_code, 400)
        self.assertIn("PUBLISHED", res_draft.get_json()["error"])

    def test_prepare_morning_published_schedule_confirmation_mode(self):
        # Enable auto SMS in Confirmation Mode
        SmsAutoSettings(is_enabled=True, confirmation_policy=POLICY_CONFIRMATION).save()

        # Create published morning schedule
        pub_sched = DailySchedule(
            date=self.test_date,
            session="morning",
            status="published",
            version=1,
            buses=[
                {
                    "bus_number": "S1",
                    "route_name": "Route 4 - Tirunagar",
                    "departure_time": "06:45 AM",
                    "stops": [{"stop_name": "Tirunagar", "arrival_time": "06:45 AM"}],
                },
                {
                    "bus_number": "S2",
                    "route_name": "Route 2 - Anna Nagar",
                    "departure_time": "07:00 AM",
                    "stops": [{"stop_name": "Anna Nagar", "arrival_time": "07:00 AM"}],
                },
            ],
        )
        pub_sched.save()

        res = self.client.post(
            "/api/sms/auto-schedule/prepare",
            json={"session": "morning", "date": self.test_date},
            headers=self.admin_headers,
        )
        self.assertEqual(res.status_code, 201)
        data = res.get_json()

        self.assertTrue(data["confirmation_required"])
        self.assertEqual(data["auto_campaign_key"], f"AUTO_{self.test_date}_morning_v1")
        campaign = data["campaign"]
        self.assertEqual(campaign["status"], STATUS_PENDING_CONFIRMATION)
        self.assertEqual(campaign["total_recipients"], 2)

    # ── 3. Duplicate Prevention & Schedule Update Revision ────────────────────

    def test_duplicate_prevention_same_version(self):
        SmsAutoSettings(is_enabled=True, confirmation_policy=POLICY_CONFIRMATION).save()

        pub_sched = DailySchedule(
            date=self.test_date,
            session="afternoon",
            status="published",
            version=1,
            buses=[{"bus_number": "S1", "route_name": "Route 4 - Tirunagar", "departure_time": "04:30 PM"}],
        )
        pub_sched.save()

        # Run 1: Prepares campaign
        res1 = self.client.post(
            "/api/sms/auto-schedule/prepare",
            json={"session": "afternoon", "date": self.test_date},
            headers=self.admin_headers,
        )
        self.assertEqual(res1.status_code, 201)

        # Run 2: Same date and version -> must prevent duplicate campaign creation
        res2 = self.client.post(
            "/api/sms/auto-schedule/prepare",
            json={"session": "afternoon", "date": self.test_date},
            headers=self.admin_headers,
        )
        self.assertEqual(res2.status_code, 200)
        self.assertTrue(res2.get_json()["duplicate_prevented"])

    def test_schedule_update_creates_version_revision_campaign(self):
        SmsAutoSettings(is_enabled=True, confirmation_policy=POLICY_CONFIRMATION).save()

        # Version 1
        pub_sched = DailySchedule(
            date=self.test_date,
            session="morning",
            status="published",
            version=1,
            buses=[{"bus_number": "S1", "route_name": "Route 4 - Tirunagar", "departure_time": "07:00 AM"}],
        )
        pub_sched.save()

        res1 = self.client.post(
            "/api/sms/auto-schedule/prepare",
            json={"session": "morning", "date": self.test_date},
            headers=self.admin_headers,
        )
        self.assertEqual(res1.status_code, 201)

        # Schedule updated to Version 2 (e.g. bus departure time updated)
        pub_sched.version = 2
        pub_sched.is_updated = True
        pub_sched.buses = [
            {"bus_number": "S1", "route_name": "Route 4 - Tirunagar", "departure_time": "07:15 AM"}
        ]
        pub_sched.save()

        # Prepare for Version 2 -> should successfully create v2 revision campaign
        res2 = self.client.post(
            "/api/sms/auto-schedule/prepare",
            json={"session": "morning", "date": self.test_date},
            headers=self.admin_headers,
        )
        self.assertEqual(res2.status_code, 201)
        self.assertEqual(res2.get_json()["auto_campaign_key"], f"AUTO_{self.test_date}_morning_v2")

    # ── 4. Confirmation Approval Workflow & Test Mode ─────────────────────────

    def test_pending_confirmation_and_approval_workflow(self):
        SmsAutoSettings(is_enabled=True, confirmation_policy=POLICY_CONFIRMATION).save()

        pub_sched = DailySchedule(
            date=self.test_date,
            session="morning",
            status="published",
            version=1,
            buses=[{"bus_number": "S1", "route_name": "Route 4 - Tirunagar", "departure_time": "07:00 AM"}],
        )
        pub_sched.save()

        # Prepare
        prep_res = self.client.post(
            "/api/sms/auto-schedule/prepare",
            json={"session": "morning", "date": self.test_date},
            headers=self.admin_headers,
        )
        c_id = prep_res.get_json()["campaign"]["id"]

        # Query pending
        pending_res = self.client.get("/api/sms/auto-schedule/pending-confirmations", headers=self.admin_headers)
        self.assertEqual(pending_res.status_code, 200)
        self.assertEqual(pending_res.get_json()["count"], 1)

        # Approve
        approve_res = self.client.post(
            f"/api/sms/auto-schedule/campaigns/{c_id}/approve",
            headers=self.admin_headers,
        )
        self.assertEqual(approve_res.status_code, 200)
        updated_c = approve_res.get_json()["campaign"]
        self.assertEqual(updated_c["status"], STATUS_DRAFT)  # Ready for phone SIM dispatch

    def test_safe_test_trigger_single_mobile(self):
        # Create published schedule
        pub_sched = DailySchedule(
            date=self.test_date,
            session="morning",
            status="published",
            version=1,
            buses=[{"bus_number": "S1", "route_name": "Route 4 - Tirunagar", "departure_time": "07:00 AM"}],
        )
        pub_sched.save()

        # Run test with test phone
        res = self.client.post(
            "/api/sms/auto-schedule/prepare",
            json={
                "session": "morning",
                "date": self.test_date,
                "force_test": True,
                "test_phone": "9876543210",
            },
            headers=self.admin_headers,
        )
        self.assertEqual(res.status_code, 201)
        campaign = res.get_json()["campaign"]
        # Only 1 recipient (the test mobile)
        self.assertEqual(campaign["total_recipients"], 1)
        self.assertEqual(campaign["recipients"][0]["register_number"], "TEST-AUTO-ADMIN")


if __name__ == "__main__":
    unittest.main()
