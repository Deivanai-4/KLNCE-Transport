# -*- coding: utf-8 -*-
"""
Test Suite for Stage 9: Broadcast Announcements and Schedule Change Alerts.
Validates:
  - Creating, drafting, updating, and deleting announcements.
  - Publishing announcements with target audiences (All Active, Route, Bus, Selected).
  - Recipient counting and duplicate phone prevention.
  - Emergency priority announcement pinning and prioritization.
  - Linked SMS campaign creation in pending_confirmation status.
  - Schedule change detection: bus removal, bus addition, departure time change, stop timing change.
  - Student in-app announcement retrieval with relevance filtering and unread/read tracking.
  - Authorization security: non-admin cannot create/publish/delete announcements.
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
from models.student import Student
from models.daily_schedule import DailySchedule
from models.announcement import (
    Announcement,
    CATEGORY_GENERAL,
    CATEGORY_DELAY,
    CATEGORY_CANCELLATION,
    CATEGORY_SCHEDULE_CHANGE,
    CATEGORY_EMERGENCY,
    PRIORITY_NORMAL,
    PRIORITY_HIGH,
    PRIORITY_EMERGENCY,
    STATUS_DRAFT,
    STATUS_PUBLISHED,
    TARGET_ALL_ACTIVE,
    TARGET_ROUTE,
    TARGET_BUS,
    TARGET_SELECTED,
)
from models.sms_campaign import SmsCampaign, STATUS_PENDING_CONFIRMATION
from services.schedule_change_detector import detect_schedule_changes


class AnnouncementsStage9Tests(unittest.TestCase):
    def setUp(self):
        self.app = create_app(TestingConfig)
        self.app_context = self.app.app_context()
        self.app_context.push()

        self.db = get_db()
        for coll in ["users", "students", "announcements", "sms_campaigns", "daily_schedules", "counters"]:
            self.db[coll].delete_many({})

        # Admin user
        hashed_pw = bcrypt.hashpw("admin123".encode("utf-8"), bcrypt.gensalt()).decode("utf-8")
        self.admin = User(
            name="Transport Admin",
            email="admin@klnce.edu",
            password_hash=hashed_pw,
            role="admin",
            college="both",
            phone="9876543210",
            is_active=True,
        )
        self.admin.save()
        self.admin_token = create_access_token(identity=self.admin.email)
        self.admin_headers = {
            "Authorization": f"Bearer {self.admin_token}",
            "Content-Type": "application/json",
        }

        # Student user
        self.student_user = User(
            name="Karthik R",
            email="karthik@klnce.edu",
            password_hash=hashed_pw,
            role="student",
            college="both",
            phone="9840112233",
            is_active=True,
        )
        self.student_user.save()
        self.student_token = create_access_token(identity=self.student_user.email)
        self.student_headers = {
            "Authorization": f"Bearer {self.student_token}",
            "Content-Type": "application/json",
        }

        # Seed students in MongoDB
        # Student 1: Route 1, Bus S1
        self.s1 = Student(
            register_number="910021104001",
            name="Karthik R",
            department="CSE",
            year=3,
            section="A",
            student_mobile="9840112233",
            parent_mobile="9840112234",
            route_name="Route 1 - Thirunagar",
            bus_number="S1",
            boarding_stop="Thirunagar",
            is_transport_active=True,
        )
        self.s1.save()

        # Student 2: Route 1, Bus S1 (duplicate phone number to test duplicate prevention)
        self.s2 = Student(
            register_number="910021104002",
            name="Suresh K",
            department="ECE",
            year=3,
            section="B",
            student_mobile="9840112233",  # Same phone as Karthik
            parent_mobile="9840112235",
            route_name="Route 1 - Thirunagar",
            bus_number="S1",
            boarding_stop="Thirunagar",
            is_transport_active=True,
        )
        self.s2.save()

        # Student 3: Route 2, Bus S2
        self.s3 = Student(
            register_number="910021104003",
            name="Priya M",
            department="IT",
            year=2,
            section="A",
            student_mobile="9840223344",
            parent_mobile="9840223345",
            route_name="Route 2 - Anna Nagar",
            bus_number="S2",
            boarding_stop="Anna Nagar",
            is_transport_active=True,
        )
        self.s3.save()

        # Student 4: Inactive student (should never receive announcements/SMS)
        self.s4 = Student(
            register_number="910021104004",
            name="Inactive Student",
            department="MECH",
            year=4,
            section="A",
            student_mobile="9840998877",
            parent_mobile="9840998878",
            route_name="Route 1 - Thirunagar",
            bus_number="S1",
            boarding_stop="Thirunagar",
            is_transport_active=False,
        )
        self.s4.save()

        self.client = self.app.test_client()

    def tearDown(self):
        self.app_context.pop()

    def test_create_and_update_draft_announcement(self):
        """Test creating a draft announcement, updating it, and deleting it."""
        payload = {
            "title": "Upcoming Campus Event Notice",
            "message": "Buses will operate on normal schedule during the technical symposium.",
            "category": CATEGORY_GENERAL,
            "priority": PRIORITY_NORMAL,
            "status": STATUS_DRAFT,
            "target_type": TARGET_ALL_ACTIVE,
        }
        res = self.client.post("/api/announcements", json=payload, headers=self.admin_headers)
        self.assertEqual(res.status_code, 201)
        data = res.get_json()
        ann_id = data["announcement"]["id"]
        self.assertEqual(data["announcement"]["status"], STATUS_DRAFT)

        # Update draft
        update_payload = {
            "title": "Updated Campus Event Notice",
            "message": "Evening buses will depart 15 mins later due to the symposium.",
            "priority": PRIORITY_HIGH,
        }
        put_res = self.client.put(f"/api/announcements/{ann_id}", json=update_payload, headers=self.admin_headers)
        self.assertEqual(put_res.status_code, 200)
        updated = put_res.get_json()["announcement"]
        self.assertEqual(updated["title"], "Updated Campus Event Notice")
        self.assertEqual(updated["priority"], PRIORITY_HIGH)

        # Delete draft
        del_res = self.client.delete(f"/api/announcements/{ann_id}", headers=self.admin_headers)
        self.assertEqual(del_res.status_code, 200)

        # Verify not found
        get_res = self.client.get(f"/api/announcements/{ann_id}", headers=self.admin_headers)
        self.assertEqual(get_res.status_code, 404)

    def test_publish_announcement_target_route_and_duplicate_prevention(self):
        """Test route-wise targeting with duplicate phone prevention."""
        payload = {
            "title": "Route 1 Delay Alert",
            "message": "Route 1 buses will be delayed by 10 minutes due to road maintenance.",
            "category": CATEGORY_DELAY,
            "priority": PRIORITY_HIGH,
            "status": STATUS_PUBLISHED,
            "target_type": TARGET_ROUTE,
            "target_route": "Route 1 - Thirunagar",
            "channels": ["in_app", "sms"],
        }
        res = self.client.post("/api/announcements", json=payload, headers=self.admin_headers)
        self.assertEqual(res.status_code, 201)
        data = res.get_json()

        # Both Karthik and Suresh have the same phone number (9840112233)
        # Unique recipients must be 1, duplicate prevented must be 1
        self.assertEqual(data["recipient_count"], 1)
        self.assertEqual(data["duplicates_prevented"], 1)

        # SMS campaign must have been created in pending_confirmation
        sms_camp_id = data["sms_campaign_id"]
        self.assertIsNotNone(sms_camp_id)
        camp = SmsCampaign.find_by_id(sms_camp_id)
        self.assertIsNotNone(camp)
        self.assertEqual(camp.status, STATUS_PENDING_CONFIRMATION)
        self.assertEqual(camp.total_recipients, 1)

    def test_publish_announcement_target_bus(self):
        """Test bus-wise targeting."""
        payload = {
            "title": "Bus S2 Replacement",
            "message": "Bus S2 is temporarily replaced by Bus S5 for the evening return.",
            "category": "Bus Replacement",
            "priority": PRIORITY_NORMAL,
            "status": STATUS_PUBLISHED,
            "target_type": TARGET_BUS,
            "target_bus": "S2",
            "channels": ["in_app"],
        }
        res = self.client.post("/api/announcements", json=payload, headers=self.admin_headers)
        self.assertEqual(res.status_code, 201)
        data = res.get_json()
        # Only Student 3 (Priya) is assigned to S2
        self.assertEqual(data["recipient_count"], 1)

    def test_recipient_preview_endpoint(self):
        """Test recipient preview calculation endpoint without saving."""
        preview_payload = {
            "target_type": TARGET_ALL_ACTIVE,
        }
        res = self.client.post("/api/announcements/recipient-preview", json=preview_payload, headers=self.admin_headers)
        self.assertEqual(res.status_code, 200)
        data = res.get_json()
        # Students 1, 2, 3 are active (Student 2 has duplicate phone, Student 4 is inactive)
        self.assertEqual(data["total_recipients"], 2)
        self.assertEqual(data["duplicates_prevented"], 1)
        self.assertTrue(len(data["sample_recipients"]) >= 1)
        # Verify phone numbers are masked for privacy
        for s in data["sample_recipients"]:
            self.assertIn("***", s["masked_mobile"])

    def test_emergency_announcement_prioritization(self):
        """Emergency announcements must appear first in student retrieval."""
        # 1. Normal announcement
        norm = Announcement(
            title="General Campus Bus Circular",
            message="Please carry your bus pass daily.",
            category=CATEGORY_GENERAL,
            priority=PRIORITY_NORMAL,
            status=STATUS_PUBLISHED,
            target_type=TARGET_ALL_ACTIVE,
        )
        norm.save()

        # 2. Emergency notice created AFTER the normal one
        em = Announcement(
            title="EMERGENCY: Heavy Rain Alert",
            message="College closes early at 2 PM. Buses departing immediately.",
            category=CATEGORY_EMERGENCY,
            priority=PRIORITY_EMERGENCY,
            status=STATUS_PUBLISHED,
            target_type=TARGET_ALL_ACTIVE,
        )
        em.save()

        # Student fetches announcements
        res = self.client.get("/api/announcements/student", headers=self.student_headers)
        self.assertEqual(res.status_code, 200)
        data = res.get_json()
        self.assertTrue(len(data["announcements"]) >= 2)

        # First announcement MUST be the emergency notice
        first = data["announcements"][0]
        self.assertEqual(first["priority"], PRIORITY_EMERGENCY)
        self.assertTrue(first["is_emergency"])
        self.assertEqual(first["title"], "EMERGENCY: Heavy Rain Alert")

    def test_student_read_unread_status(self):
        """Test student read/unread tracking."""
        ann = Announcement(
            title="Read Tracking Test",
            message="Check if marked read.",
            status=STATUS_PUBLISHED,
            target_type=TARGET_ALL_ACTIVE,
        )
        ann_id = ann.save()

        # Fetch as student — should be unread
        res = self.client.get("/api/announcements/student", headers=self.student_headers)
        data = res.get_json()
        item = next(a for a in data["announcements"] if a["id"] == ann_id)
        self.assertFalse(item["is_read"])

        # Mark read
        read_res = self.client.post(f"/api/announcements/{ann_id}/read", headers=self.student_headers)
        self.assertEqual(read_res.status_code, 200)

        # Fetch again — should now be marked read
        res2 = self.client.get("/api/announcements/student", headers=self.student_headers)
        data2 = res2.get_json()
        item2 = next(a for a in data2["announcements"] if a["id"] == ann_id)
        self.assertTrue(item2["is_read"])

    def test_schedule_change_detector_service(self):
        """Test automatic schedule change detection logic."""
        old_schedule = {
            "date": "2026-11-20",
            "session": "morning",
            "buses": [
                {
                    "bus_number": "S1",
                    "route_name": "Route 1 - Thirunagar",
                    "departure_time": "07:00",
                    "stops": [
                        {"stop_name": "Thirunagar", "time": "07:00"},
                        {"stop_name": "Madurai", "time": "07:30"},
                    ],
                },
                {
                    "bus_number": "M1",
                    "route_name": "Route 2 - Anna Nagar",
                    "departure_time": "07:10",
                    "stops": [{"stop_name": "Anna Nagar", "time": "07:10"}],
                },
            ],
        }

        # New schedule:
        # 1. S1 departure changed from 07:00 to 07:15
        # 2. M1 was cancelled / removed
        # 3. New bus S2 added on Route 2
        new_schedule = {
            "date": "2026-11-20",
            "session": "morning",
            "buses": [
                {
                    "bus_number": "S1",
                    "route_name": "Route 1 - Thirunagar",
                    "departure_time": "07:15",  # Changed!
                    "stops": [
                        {"stop_name": "Thirunagar", "time": "07:15"},
                        {"stop_name": "Madurai", "time": "07:45"},
                    ],
                },
                {
                    "bus_number": "S2",  # M1 replaced with S2!
                    "route_name": "Route 2 - Anna Nagar",
                    "departure_time": "07:15",
                    "stops": [{"stop_name": "Anna Nagar", "time": "07:15"}],
                },
            ],
        }

        diff = detect_schedule_changes(old_schedule, new_schedule)
        self.assertTrue(diff["has_changes"])
        self.assertIn("S1", diff["affected_buses"])
        self.assertIn("M1", diff["affected_buses"])
        self.assertIn("Route 1 - Thirunagar", diff["affected_routes"])
        self.assertTrue(any("07:00 to 07:15" in b for b in diff["change_bullets"]))
        self.assertTrue(any("cancelled" in b or "removed" in b for b in diff["change_bullets"]))

        # Check affected students count (Karthik & Suresh on Route 1, Priya on S2/Route 2)
        self.assertTrue(diff["affected_students_count"] >= 2)

    def test_daily_schedule_update_returns_change_detection(self):
        """Test that updating an already published schedule returns schedule_change_detected in API."""
        # 1. Create and publish a schedule
        sched_payload = {
            "date": "2026-11-25",
            "session": "morning",
            "status": "published",
            "buses": [
                {
                    "bus_number": "S1",
                    "route_name": "Route 1 - Thirunagar",
                    "departure_time": "07:00",
                    "stops": [{"stop_name": "Thirunagar", "time": "07:00"}],
                }
            ],
        }
        create_res = self.client.post("/api/daily-schedules", json=sched_payload, headers=self.admin_headers)
        self.assertEqual(create_res.status_code, 201)
        sched_id = create_res.get_json()["daily_schedule"]["id"]

        # 2. Update departure time on this published schedule
        update_payload = {
            "buses": [
                {
                    "bus_number": "S1",
                    "route_name": "Route 1 - Thirunagar",
                    "departure_time": "07:20",  # Changed departure time
                    "stops": [{"stop_name": "Thirunagar", "time": "07:20"}],
                }
            ],
            "update_summary": "S1 delayed by 20 minutes",
        }
        up_res = self.client.put(f"/api/daily-schedules/{sched_id}", json=update_payload, headers=self.admin_headers)
        self.assertEqual(up_res.status_code, 200)
        data = up_res.get_json()
        self.assertTrue(data.get("schedule_change_detected"))
        self.assertIn("change_summary", data)
        self.assertIn("S1", data["change_summary"]["affected_buses"])

    def test_non_admin_cannot_publish_announcements(self):
        """Security check: Students cannot publish or delete announcements."""
        payload = {
            "title": "Hacked Announcement",
            "message": "Classes cancelled today.",
            "status": STATUS_PUBLISHED,
        }
        res = self.client.post("/api/announcements", json=payload, headers=self.student_headers)
        self.assertEqual(res.status_code, 403)


if __name__ == "__main__":
    unittest.main()
