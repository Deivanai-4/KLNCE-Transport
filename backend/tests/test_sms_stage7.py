# -*- coding: utf-8 -*-
"""
Test Suite for Stage 7: SMS Confirmation, Bulk Sending, and Status Tracking.
Tests segment calculation, mobile masking, recipient validation, duplicate prevention,
campaign creation, live status tracking, recipient filtering, and retry of failed messages.
"""

import os
import unittest
import bcrypt
from flask_jwt_extended import create_access_token

os.environ["FLASK_ENV"] = "testing"

from app import create_app
from config import TestingConfig
from models.database import get_db
from models.user import User
from models.sms_campaign import (
    SmsCampaign,
    mask_mobile,
    STATUS_DRAFT,
    STATUS_SENDING,
    STATUS_COMPLETED,
    RECIPIENT_PENDING,
    RECIPIENT_SENT_TO_SMS_SERVICE,
    RECIPIENT_FAILED,
)
from routes.sms import calculate_sms_segments, mask_mobile_number


class SmsStage7Tests(unittest.TestCase):
    def setUp(self):
        self.app = create_app(TestingConfig)
        self.app_context = self.app.app_context()
        self.app_context.push()

        self.db = get_db()
        for coll in ["users", "students", "sms_campaigns", "counters"]:
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

        # Seed students with valid, invalid, and duplicate mobile numbers
        self.students_data = [
            {
                "_id": 1,
                "register_number": "91001",
                "name": "Aravind K",
                "student_mobile": "9876543210",  # Shared number 1
                "route_name": "Route 4 - Tirunagar",
                "bus_number": "S1",
                "is_transport_active": True,
            },
            {
                "_id": 2,
                "register_number": "91002",
                "name": "Bala M",
                "student_mobile": "9876543210",  # Duplicate of Aravind (sibling)
                "route_name": "Route 4 - Tirunagar",
                "bus_number": "S1",
                "is_transport_active": True,
            },
            {
                "_id": 3,
                "register_number": "91003",
                "name": "Chitra S",
                "student_mobile": "9123456789",  # Unique valid
                "route_name": "Route 4 - Tirunagar",
                "bus_number": "S1",
                "is_transport_active": True,
            },
            {
                "_id": 4,
                "register_number": "91004",
                "name": "Dinesh R",
                "student_mobile": "12345",  # Invalid number (too short)
                "route_name": "Route 4 - Tirunagar",
                "bus_number": "S1",
                "is_transport_active": True,
            },
            {
                "_id": 5,
                "register_number": "91005",
                "name": "Eswari T",
                "student_mobile": "",  # Missing number
                "route_name": "Route 2 - Anna Nagar",
                "bus_number": "S2",
                "is_transport_active": True,
            },
            {
                "_id": 6,
                "register_number": "91006",
                "name": "Farooq H",
                "student_mobile": "+91 9988776655",  # Valid with +91
                "route_name": "Route 2 - Anna Nagar",
                "bus_number": "S2",
                "is_transport_active": True,
            },
        ]
        self.db["students"].insert_many(self.students_data)

    def tearDown(self):
        self.app_context.pop()

    # ── 1. Test SMS Segments & Masking Calculations ──────────────────────────

    def test_calculate_sms_segments_gsm7(self):
        # Short GSM message
        short_msg = "Bus S1 is delayed by 15 mins."
        res = calculate_sms_segments(short_msg)
        self.assertEqual(res["encoding"], "GSM-7")
        self.assertFalse(res["is_unicode"])
        self.assertEqual(res["segments_per_message"], 1)

        # Long GSM message (>160 chars)
        long_msg = "A" * 170
        res_long = calculate_sms_segments(long_msg)
        self.assertEqual(res_long["encoding"], "GSM-7")
        self.assertEqual(res_long["segments_per_message"], 2)

    def test_calculate_sms_segments_unicode_tamil(self):
        # Tamil Unicode message
        tamil_msg = "பேருந்து தாமதம்: Bus S1 delayed"
        res = calculate_sms_segments(tamil_msg)
        self.assertEqual(res["encoding"], "Unicode (UCS-2)")
        self.assertTrue(res["is_unicode"])
        self.assertEqual(res["segments_per_message"], 1)

        # Long Tamil message (>70 chars)
        long_tamil = "வணக்கம் மாணவர்களே, இன்றைய பேருந்து புறப்படும் நேரம் மாற்றம் செய்யப்பட்டுள்ளது."
        res_long = calculate_sms_segments(long_tamil)
        self.assertEqual(res_long["encoding"], "Unicode (UCS-2)")
        self.assertTrue(res_long["segments_per_message"] >= 2)

    def test_mask_mobile_number(self):
        self.assertEqual(mask_mobile_number("9876543210"), "+91 98*** **210")
        self.assertEqual(mask_mobile_number("+919123456789"), "+91 91*** **789")
        self.assertEqual(mask_mobile_number(""), "N/A")
        self.assertEqual(mask_mobile_number(None), "N/A")

    # ── 2. Test Recipient Query & Validation Preview ──────────────────────────

    def test_get_recipients_route_target_duplicate_prevention(self):
        # Query Route 4 with default allow_duplicates=false
        res = self.client.get(
            "/api/sms/recipients?target=route&route_name=Route 4 - Tirunagar",
            headers=self.admin_headers,
        )
        self.assertEqual(res.status_code, 200)
        data = res.get_json()

        self.assertEqual(data["total_selected_students"], 4)
        self.assertEqual(data["valid_count"], 3)  # Aravind, Bala, Chitra
        self.assertEqual(data["invalid_count"], 1)  # Dinesh (12345)
        self.assertEqual(data["duplicate_count"], 1)  # Bala duplicates Aravind's 9876543210
        self.assertEqual(data["unique_valid_count"], 2)  # 9876543210 and 9123456789

        # By default, duplicates are prevented (only 2 unique numbers dispatched)
        self.assertEqual(data["effective_recipient_count"], 2)
        self.assertEqual(data["duplicates_prevented"], 1)
        self.assertEqual(len(data["recipients"]), 2)

        # Check masked mobile in valid recipients
        for r in data["valid_recipients"]:
            self.assertIn("masked_mobile", r)
            self.assertTrue(r["masked_mobile"].startswith("+91 "))

        # Check invalid recipient entry
        self.assertEqual(len(data["invalid_recipients"]), 1)
        self.assertEqual(data["invalid_recipients"][0]["register_number"], "91004")

        # Check duplicate groups
        self.assertEqual(len(data["duplicate_groups"]), 1)
        group = data["duplicate_groups"][0]
        self.assertEqual(group["count"], 2)
        self.assertEqual(len(group["students"]), 2)

    def test_get_recipients_with_explicit_duplicate_approval(self):
        # Query Route 4 with allow_duplicates=true
        res = self.client.get(
            "/api/sms/recipients?target=route&route_name=Route 4 - Tirunagar&allow_duplicates=true",
            headers=self.admin_headers,
        )
        self.assertEqual(res.status_code, 200)
        data = res.get_json()

        self.assertTrue(data["allow_duplicates"])
        self.assertEqual(data["duplicates_prevented"], 0)
        # With duplicates approved, all 3 valid students are included
        self.assertEqual(data["effective_recipient_count"], 3)
        self.assertEqual(len(data["recipients"]), 3)

    def test_get_recipients_by_bus(self):
        res = self.client.get(
            "/api/sms/recipients?target=bus&bus_number=S2",
            headers=self.admin_headers,
        )
        self.assertEqual(res.status_code, 200)
        data = res.get_json()
        self.assertEqual(data["total_selected_students"], 2)  # Eswari (missing), Farooq (valid)
        self.assertEqual(data["valid_count"], 1)
        self.assertEqual(data["invalid_count"], 1)

    def test_get_recipients_individual_students(self):
        res = self.client.get(
            "/api/sms/recipients?target=selected&student_ids=1,3,6",
            headers=self.admin_headers,
        )
        self.assertEqual(res.status_code, 200)
        data = res.get_json()
        self.assertEqual(data["total_selected_students"], 3)
        self.assertEqual(data["valid_count"], 3)
        self.assertEqual(data["duplicate_count"], 0)

    # ── 3. Test Campaign Creation with Duplicate Safeguard ────────────────────

    def test_create_campaign_prevents_duplicate_sms(self):
        payload = {
            "title": "Bus S1 Notice",
            "message": "Bus S1 departure at 4:30 PM",
            "target_type": "route",
            "route_name": "Route 4 - Tirunagar",
            "allow_duplicates": False,  # Default
            "sender_device": {"model": "Samsung A52", "carrier": "Airtel"},
        }
        res = self.client.post("/api/sms/campaigns", json=payload, headers=self.admin_headers)
        self.assertEqual(res.status_code, 201)
        data = res.get_json()["campaign"]

        # Only 2 SMS queued (Aravind and Chitra, duplicate for Bala prevented)
        self.assertEqual(data["total_recipients"], 2)
        self.assertEqual(data["duplicates_prevented_count"], 1)
        self.assertEqual(data["duplicate_count"], 1)
        self.assertEqual(data["invalid_count"], 1)
        self.assertFalse(data["allow_duplicates"])

    def test_create_campaign_explicitly_approved_duplicates(self):
        payload = {
            "title": "Bus S1 Notice - All",
            "message": "Bus S1 departure at 4:30 PM",
            "target_type": "route",
            "route_name": "Route 4 - Tirunagar",
            "allow_duplicates": True,  # Explicit approval
            "sender_device": {"model": "Samsung A52", "carrier": "Airtel"},
        }
        res = self.client.post("/api/sms/campaigns", json=payload, headers=self.admin_headers)
        self.assertEqual(res.status_code, 201)
        data = res.get_json()["campaign"]

        # All 3 valid queued
        self.assertEqual(data["total_recipients"], 3)
        self.assertEqual(data["duplicates_prevented_count"], 0)
        self.assertTrue(data["allow_duplicates"])

    def test_create_test_campaign(self):
        payload = {
            "title": "Admin Test",
            "message": "Testing Android SIM dispatch",
            "target_type": "test",
            "test_phone": "9876543210",
        }
        res = self.client.post("/api/sms/campaigns", json=payload, headers=self.admin_headers)
        self.assertEqual(res.status_code, 201)
        data = res.get_json()["campaign"]
        self.assertEqual(data["total_recipients"], 1)
        self.assertEqual(data["recipients"][0]["register_number"], "TEST-ADMIN")

    # ── 4. Test Dispatch Progress & Live Status Tracking ─────────────────────

    def test_update_status_and_filter_recipients(self):
        # 1. Create a campaign
        c_res = self.client.post(
            "/api/sms/campaigns",
            json={
                "title": "Emergency Alert",
                "message": "Heavy rain alert. Buses will depart early at 3:00 PM.",
                "target_type": "route",
                "route_name": "Route 4 - Tirunagar",
                "allow_duplicates": False,
            },
            headers=self.admin_headers,
        )
        c_id = c_res.get_json()["campaign"]["id"]

        # 2. Update progress: 1 sent, 1 failed
        p_res = self.client.put(
            f"/api/sms/campaigns/{c_id}/status",
            json={
                "status": "sending",
                "recipient_updates": [
                    {
                        "student_id": 1,
                        "mobile_number": "9876543210",
                        "status": "sent_to_sms_service",
                    },
                    {
                        "student_id": 3,
                        "mobile_number": "9123456789",
                        "status": "failed",
                        "error_message": "NO_SERVICE (No cellular network)",
                    },
                ],
            },
            headers=self.admin_headers,
        )
        self.assertEqual(p_res.status_code, 200)
        updated = p_res.get_json()["campaign"]
        self.assertEqual(updated["sent_count"], 1)
        self.assertEqual(updated["failed_count"], 1)
        self.assertEqual(updated["status"], "partially_failed")

        # 3. Query campaign details with status filter: failed
        failed_res = self.client.get(
            f"/api/sms/campaigns/{c_id}?status=failed",
            headers=self.admin_headers,
        )
        self.assertEqual(failed_res.status_code, 200)
        failed_data = failed_res.get_json()
        self.assertEqual(len(failed_data["recipients"]), 1)
        self.assertEqual(failed_data["recipients"][0]["status"], "failed")
        self.assertEqual(failed_data["recipients"][0]["student_id"], 3)

        # 4. Search campaign recipients by register number
        search_res = self.client.get(
            f"/api/sms/campaigns/{c_id}?search=91001",
            headers=self.admin_headers,
        )
        self.assertEqual(search_res.status_code, 200)
        search_data = search_res.get_json()
        self.assertEqual(len(search_data["recipients"]), 1)
        self.assertEqual(search_data["recipients"][0]["register_number"], "91001")

        # 5. Retry failed recipients
        retry_res = self.client.post(
            f"/api/sms/campaigns/{c_id}/retry-failed",
            headers=self.admin_headers,
        )
        self.assertEqual(retry_res.status_code, 200)
        retried_data = retry_res.get_json()["campaign"]
        self.assertEqual(retried_data["failed_count"], 0)
        self.assertEqual(retried_data["status"], "sending")
        # Check student 3 is reset to pending
        retried_st3 = next(r for r in retried_data["recipients"] if r["student_id"] == 3)
        self.assertEqual(retried_st3["status"], "pending")
        self.assertIsNone(retried_st3["error_message"])


if __name__ == "__main__":
    unittest.main()
