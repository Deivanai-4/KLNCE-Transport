"""
Comprehensive MongoDB Backend Integration Test Suite for KLNCE Transport.
Validates all routes and models using an isolated test database (mongomock).
Never runs destructive operations on production Atlas.
"""

import os
import unittest
import bcrypt
from datetime import datetime
from flask_jwt_extended import create_access_token

os.environ['FLASK_ENV'] = 'testing'

from app import create_app
from config import TestingConfig
from models.database import get_db
from models.user import User
from models.bus_route import BusRoute
from models.route_stop import RouteStop
from models.master_stop import MasterStop
from models.gps_location import GpsLocation
from models.notification import Notification
from models.schedule import ScheduleDocument


class MongoDBBackendIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app(TestingConfig)
        self.app_context = self.app.app_context()
        self.app_context.push()

        # Isolate and clear all test collections
        self.db = get_db()
        for coll in ['users', 'bus_routes', 'master_stops', 'route_stops', 'gps_locations', 'notifications', 'schedule_documents', 'counters']:
            self.db[coll].delete_many({})

        # Create seeded test users
        hashed_pw = bcrypt.hashpw('admin123'.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
        self.admin = User(
            name='Test Admin',
            email='admin@klnce.edu',
            password_hash=hashed_pw,
            role='admin',
            college='both',
            phone='9876543210',
            is_active=True
        )
        self.admin.save()

        student_pw = bcrypt.hashpw('student123'.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
        self.student = User(
            name='Test Student',
            email='student@klnce.edu',
            password_hash=student_pw,
            role='student',
            college='engineering',
            phone='9123456780',
            is_active=True
        )
        self.student.save()

        self.admin_token = create_access_token(identity=self.admin.email)
        self.student_token = create_access_token(identity=self.student.email)
        self.admin_headers = {'Authorization': f'Bearer {self.admin_token}'}
        self.student_headers = {'Authorization': f'Bearer {self.student_token}'}

        self.client = self.app.test_client()

    def tearDown(self):
        self.app_context.pop()

    # ------------------------------------------------------------------ #
    # 1. Authentication Tests                                              #
    # ------------------------------------------------------------------ #
    def test_login_success(self):
        resp = self.client.post('/api/auth/login', json={
            'email': 'admin@klnce.edu',
            'password': 'admin123'
        })
        self.assertEqual(resp.status_code, 200)
        data = resp.get_json()
        self.assertIn('token', data)
        self.assertEqual(data['user']['email'], 'admin@klnce.edu')
        self.assertEqual(data['user']['id'], self.admin.id)
        self.assertIsInstance(data['user']['id'], int)

    def test_login_invalid_password(self):
        resp = self.client.post('/api/auth/login', json={
            'email': 'admin@klnce.edu',
            'password': 'wrongpassword'
        })
        self.assertEqual(resp.status_code, 401)

    def test_auth_me(self):
        resp = self.client.get('/api/auth/me', headers=self.admin_headers)
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.get_json()['user']['email'], 'admin@klnce.edu')

    def test_update_fcm_token(self):
        resp = self.client.put('/api/auth/fcm-token', headers=self.admin_headers, json={
            'fcm_token': 'new_sample_token_xyz'
        })
        self.assertEqual(resp.status_code, 200)
        updated = User.find_by_id(self.admin.id)
        self.assertEqual(updated.fcm_token, 'new_sample_token_xyz')

    # ------------------------------------------------------------------ #
    # 2. User Stats & Management Tests                                     #
    # ------------------------------------------------------------------ #
    def test_user_stats(self):
        resp = self.client.get('/api/users/stats', headers=self.admin_headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.get_json()
        self.assertEqual(data['students_count'], 1)
        self.assertEqual(data['total_active_users'], 1)  # only student and staff counted in total_active_users logic

    def test_list_users_pagination(self):
        resp = self.client.get('/api/users?page=1&per_page=10', headers=self.admin_headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.get_json()
        self.assertEqual(data['total'], 2)
        self.assertEqual(len(data['users']), 2)

    # ------------------------------------------------------------------ #
    # 3. Schedule, Bus Routes & Stops Lifecycle Tests                     #
    # ------------------------------------------------------------------ #
    def test_create_manual_schedule_and_retrieve(self):
        payload = {
            'title': 'Even Semester Timetable',
            'trip_direction': 'incoming',
            'college': 'both',
            'effective_date': '2026-11-20',
            'routes': [
                {
                    'bus_code': 'K',
                    'route_display_name': 'Thirunagar to Campus',
                    'departure_time': '08:00',
                    'college': 'engineering',
                    'stops': [
                        {'stop_name_en': 'Thirunagar', 'stop_name_ta': 'திருநகர்'},
                        {'stop_name_en': 'Teppakulam', 'stop_name_ta': 'தெப்பக்குளம்'},
                    ]
                }
            ]
        }
        resp = self.client.post('/api/schedules/manual', headers=self.admin_headers, json=payload)
        self.assertEqual(resp.status_code, 201)
        sched_data = resp.get_json()['schedule']
        sched_id = sched_data['id']
        self.assertIsInstance(sched_id, int)
        self.assertEqual(sched_data['effective_date'], '2026-11-20')
        self.assertEqual(len(sched_data['bus_routes']), 1)
        self.assertEqual(len(sched_data['bus_routes'][0]['stops']), 2)

        # Retrieve detail
        get_resp = self.client.get(f'/api/schedules/{sched_id}', headers=self.admin_headers)
        self.assertEqual(get_resp.status_code, 200)
        self.assertEqual(get_resp.get_json()['schedule']['title'], 'Even Semester Timetable')

    def test_update_draft_routes_protected(self):
        # 1. Create schedule
        sched = ScheduleDocument(title='Draft Sched', status='draft', trip_direction='incoming')
        sched.save()

        # 2. Try invalid update -> should fail and NOT delete existing
        br = BusRoute(schedule_id=sched.id, bus_code='IT1')
        br.save()
        rs = RouteStop(bus_route_id=br.id, stop_order=1, stop_name_en='Stop 1')
        rs.save()

        bad_payload = {'routes': [{'bus_code': '', 'stops': []}]}
        bad_resp = self.client.put(f'/api/schedules/{sched.id}/routes', headers=self.admin_headers, json=bad_payload)
        self.assertEqual(bad_resp.status_code, 400)

        # Verify old route and stop still exist!
        self.assertEqual(len(BusRoute.find_by_schedule(sched.id)), 1)

        # 3. Valid update
        good_payload = {
            'routes': [
                {
                    'bus_code': 'IT1-NEW',
                    'route_display_name': 'New Route',
                    'departure_time': '08:15',
                    'college': 'engineering',
                    'stops': ['Stop A', 'Stop B']
                }
            ]
        }
        good_resp = self.client.put(f'/api/schedules/{sched.id}/routes', headers=self.admin_headers, json=good_payload)
        self.assertEqual(good_resp.status_code, 200)

        # Verify new route replaced old
        updated_routes = BusRoute.find_by_schedule(sched.id)
        self.assertEqual(len(updated_routes), 1)
        self.assertEqual(updated_routes[0].bus_code, 'IT1-NEW')

    def test_publish_and_visibility(self):
        sched = ScheduleDocument(
            title='Live Timetable',
            status='verified',
            trip_direction='incoming',
            college='both',
            effective_date='2026-11-18'
        )
        sched.save()

        br = BusRoute(schedule_id=sched.id, bus_code='M')
        br.save()
        rs = RouteStop(bus_route_id=br.id, stop_order=1, stop_name_en='Periyar', stop_name_ta='பெரியார்')
        rs.save()

        pub_resp = self.client.post(f'/api/schedules/{sched.id}/publish', headers=self.admin_headers)
        self.assertEqual(pub_resp.status_code, 200)

        updated_sched = ScheduleDocument.find_by_id(sched.id)
        self.assertEqual(updated_sched.status, 'published')

    def test_schedule_cascading_delete(self):
        sched = ScheduleDocument(title='Delete Test', status='draft')
        sched.save()
        br = BusRoute(schedule_id=sched.id, bus_code='D1')
        br.save()
        rs = RouteStop(bus_route_id=br.id, stop_order=1, stop_name_en='Stop D')
        rs.save()

        del_resp = self.client.delete(f'/api/schedules/{sched.id}', headers=self.admin_headers)
        self.assertEqual(del_resp.status_code, 200)

        self.assertIsNone(ScheduleDocument.find_by_id(sched.id))
        self.assertEqual(len(BusRoute.find_by_schedule(sched.id)), 0)
        self.assertEqual(len(RouteStop.find_by_route(br.id)), 0)

    # ------------------------------------------------------------------ #
    # 4. Bilingual Bus Search & Autocomplete Tests                         #
    # ------------------------------------------------------------------ #
    def test_bilingual_search_and_autocomplete(self):
        sched = ScheduleDocument(title='Search Sched', status='published', trip_direction='incoming', effective_date='2026-11-20')
        sched.save()

        br = BusRoute(schedule_id=sched.id, bus_code='K1')
        br.save()
        RouteStop(bus_route_id=br.id, stop_order=1, stop_name_en='Thirunagar', stop_name_ta='திருநகர்').save()

        ms = MasterStop(standard_name_en='Thirunagar', standard_name_ta='திருநகர்', aliases=['TN'])
        ms.save()

        # Autocomplete
        ac_resp = self.client.get('/api/buses/all-stops?q=Thiru')
        self.assertEqual(ac_resp.status_code, 200)
        self.assertGreaterEqual(len(ac_resp.get_json()['stops']), 1)

    # ------------------------------------------------------------------ #
    # 5. GPS Tracking Tests                                                #
    # ------------------------------------------------------------------ #
    def test_gps_flow(self):
        # Driver update
        gps_payload = {
            'bus_code': 'K',
            'latitude': 9.8762,
            'longitude': 78.0772,
            'speed_kmh': 42.0
        }
        resp = self.client.post('/api/gps/update', headers=self.admin_headers, json=gps_payload)
        self.assertEqual(resp.status_code, 200)
        loc = resp.get_json()['location']
        self.assertEqual(loc['bus_code'], 'K')
        self.assertEqual(loc['latitude'], 9.8762)

        # Student live view
        live_resp = self.client.get('/api/gps/live/K')
        self.assertEqual(live_resp.status_code, 200)
        self.assertTrue(live_resp.get_json()['is_tracking'])

        # Active buses list
        active_resp = self.client.get('/api/gps/active')
        self.assertEqual(active_resp.status_code, 200)
        self.assertEqual(active_resp.get_json()['count'], 1)

        # End trip
        end_resp = self.client.post('/api/gps/end-trip', headers=self.admin_headers, json={'bus_code': 'K'})
        self.assertEqual(end_resp.status_code, 200)

        # Verify no longer active
        active_after = self.client.get('/api/gps/active')
        self.assertEqual(active_after.get_json()['count'], 0)

    # ------------------------------------------------------------------ #
    # 6. Notifications Tests                                               #
    # ------------------------------------------------------------------ #
    def test_notifications_crud(self):
        # Send
        send_resp = self.client.post('/api/notifications/send', headers=self.admin_headers, json={
            'title': 'Test Notice',
            'body': 'This is a test broadcast',
            'type': 'general'
        })
        self.assertEqual(send_resp.status_code, 201)
        notif_id = send_resp.get_json()['notification']['id']
        self.assertIsInstance(notif_id, int)

        # History
        hist_resp = self.client.get('/api/notifications/history')
        self.assertEqual(hist_resp.status_code, 200)
        self.assertEqual(len(hist_resp.get_json()['notifications']), 1)

        # Update
        update_resp = self.client.put(f'/api/notifications/{notif_id}', headers=self.admin_headers, json={
            'title': 'Updated Title',
            'body': 'Updated message body'
        })
        self.assertEqual(update_resp.status_code, 200)
        self.assertEqual(update_resp.get_json()['notification']['title'], 'Updated Title')

        # Delete
        del_resp = self.client.delete(f'/api/notifications/{notif_id}', headers=self.admin_headers)
        self.assertEqual(del_resp.status_code, 200)
        self.assertIsNone(Notification.find_by_id(notif_id))


if __name__ == '__main__':
    unittest.main()
