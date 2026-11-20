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
        for coll in ['users', 'students', 'sms_campaigns', 'bus_routes', 'master_stops', 'route_stops', 'gps_locations', 'notifications', 'schedule_documents', 'daily_schedules', 'counters']:
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

    # ------------------------------------------------------------------ #
    # 7. Daily Schedule Tests                                              #
    # ------------------------------------------------------------------ #
    def test_daily_schedule_crud_and_publish_flow(self):
        # 1. Admin creates a draft daily schedule for 2026-11-20 Morning
        create_resp = self.client.post('/api/daily-schedules', headers=self.admin_headers, json={
            'date': '2026-11-20',
            'session': 'morning',
            'status': 'draft',
            'buses': [
                {
                    'bus_number': 'S1',
                    'route_name': 'Route A',
                    'departure_time': '07:00 AM',
                    'stops': [
                        {'stop_order': 1, 'stop_name': 'Arapalayam', 'arrival_time': '07:00 AM'},
                        {'stop_order': 2, 'stop_name': 'Periyar', 'arrival_time': '07:15 AM'},
                    ]
                },
                {
                    'bus_number': 'S2',
                    'route_name': 'Route B',
                    'departure_time': '07:15 AM',
                    'stops': [
                        {'stop_order': 1, 'stop_name': 'Thirunagar', 'arrival_time': '07:15 AM'},
                    ]
                },
                {
                    'bus_number': 'M1',
                    'route_name': 'Route C',
                    'departure_time': '07:30 AM',
                    'stops': [
                        {'stop_order': 1, 'stop_name': 'Mattuthavani', 'arrival_time': '07:30 AM'},
                    ]
                }
            ]
        })
        self.assertEqual(create_resp.status_code, 201)
        sched_data = create_resp.get_json()['daily_schedule']
        sched_id = sched_data['id']
        self.assertEqual(sched_data['buses_count'], 3)
        self.assertEqual(sched_data['status'], 'draft')
        self.assertFalse(sched_data['is_updated'])

        # 2. Student views daily schedules — draft must NOT be returned to student
        student_resp = self.client.get('/api/daily-schedules?date=2026-11-20')
        self.assertEqual(student_resp.status_code, 200)
        self.assertEqual(student_resp.get_json()['count'], 0)

        # 3. Admin views daily schedules — draft IS visible to admin
        admin_list = self.client.get('/api/daily-schedules?date=2026-11-20', headers=self.admin_headers)
        self.assertEqual(admin_list.status_code, 200)
        self.assertEqual(admin_list.get_json()['count'], 1)

        # 4. Admin publishes the schedule
        pub_resp = self.client.post(f'/api/daily-schedules/{sched_id}/publish', headers=self.admin_headers)
        self.assertEqual(pub_resp.status_code, 200)
        self.assertEqual(pub_resp.get_json()['daily_schedule']['status'], 'published')

        # 5. Student can now see published schedule
        student_resp2 = self.client.get('/api/daily-schedules?date=2026-11-20')
        self.assertEqual(student_resp2.status_code, 200)
        self.assertEqual(student_resp2.get_json()['count'], 1)

        # 6. Admin updates published schedule — should mark is_updated=True
        update_resp = self.client.put(f'/api/daily-schedules/{sched_id}', headers=self.admin_headers, json={
            'buses': [
                {
                    'bus_number': 'S1',
                    'route_name': 'Route A Revised',
                    'departure_time': '07:05 AM',
                    'stops': [
                        {'stop_order': 1, 'stop_name': 'Arapalayam', 'arrival_time': '07:05 AM'},
                    ]
                }
            ]
        })
        self.assertEqual(update_resp.status_code, 200)
        updated_data = update_resp.get_json()['daily_schedule']
        self.assertTrue(updated_data['is_updated'])
        self.assertGreaterEqual(updated_data['version'], 2)

        # 7. Admin deletes schedule
        del_resp = self.client.delete(f'/api/daily-schedules/{sched_id}', headers=self.admin_headers)
        self.assertEqual(del_resp.status_code, 200)

    def test_daily_schedule_validation(self):
        # Invalid date
        bad_date = self.client.post('/api/daily-schedules', headers=self.admin_headers, json={
            'date': 'not-a-date',
            'session': 'morning',
            'buses': [{'bus_number': 'S1', 'route_name': 'A', 'stops': [{'stop_name': 'X', 'arrival_time': '07:00 AM'}]}]
        })
        self.assertEqual(bad_date.status_code, 400)

        # Invalid session
        bad_session = self.client.post('/api/daily-schedules', headers=self.admin_headers, json={
            'date': '2026-11-20',
            'session': 'evening',
            'buses': [{'bus_number': 'S1', 'route_name': 'A', 'stops': [{'stop_name': 'X', 'arrival_time': '07:00 AM'}]}]
        })
        self.assertEqual(bad_session.status_code, 400)

        # Empty buses
        empty_buses = self.client.post('/api/daily-schedules', headers=self.admin_headers, json={
            'date': '2026-11-20',
            'session': 'morning',
            'buses': []
        })
        self.assertEqual(empty_buses.status_code, 400)

        # Duplicate bus number in same schedule
        dup_bus = self.client.post('/api/daily-schedules', headers=self.admin_headers, json={
            'date': '2026-11-20',
            'session': 'morning',
            'buses': [
                {'bus_number': 'S1', 'route_name': 'A', 'stops': [{'stop_name': 'X', 'arrival_time': '07:00 AM'}]},
                {'bus_number': 'S1', 'route_name': 'B', 'stops': [{'stop_name': 'Y', 'arrival_time': '07:15 AM'}]},
            ]
        })
        self.assertEqual(dup_bus.status_code, 400)

    def test_daily_schedule_november_20_example(self):
        """Test the exact Nov 20, 2026 demonstration schedule specified in Stage 3."""
        # 1. Morning Schedule
        morning_resp = self.client.post('/api/daily-schedules', headers=self.admin_headers, json={
            'date': '2026-11-20',
            'session': 'morning',
            'status': 'published',
            'buses': [
                {
                    'bus_number': 'S1',
                    'route_name': 'Route A',
                    'departure_time': '7:00 AM',
                    'stops': [{'stop_name': 'Origin A', 'arrival_time': '7:00 AM'}, {'stop_name': 'KLNCE', 'arrival_time': '7:45 AM'}]
                },
                {
                    'bus_number': 'S2',
                    'route_name': 'Route B',
                    'departure_time': '7:15 AM',
                    'stops': [{'stop_name': 'Origin B', 'arrival_time': '7:15 AM'}, {'stop_name': 'KLNCE', 'arrival_time': '7:50 AM'}]
                },
                {
                    'bus_number': 'M1',
                    'route_name': 'Route C',
                    'departure_time': '7:30 AM',
                    'stops': [{'stop_name': 'Origin C', 'arrival_time': '7:30 AM'}, {'stop_name': 'KLNCE', 'arrival_time': '8:00 AM'}]
                }
            ]
        })
        self.assertEqual(morning_resp.status_code, 201)

        # 2. Afternoon Schedule
        afternoon_resp = self.client.post('/api/daily-schedules', headers=self.admin_headers, json={
            'date': '2026-11-20',
            'session': 'afternoon',
            'status': 'published',
            'buses': [
                {
                    'bus_number': 'S1',
                    'route_name': 'Route A',
                    'departure_time': '4:00 PM',
                    'stops': [{'stop_name': 'KLNCE', 'arrival_time': '4:00 PM'}, {'stop_name': 'Dest A', 'arrival_time': '4:45 PM'}]
                },
                {
                    'bus_number': 'S2',
                    'route_name': 'Route B',
                    'departure_time': '4:15 PM',
                    'stops': [{'stop_name': 'KLNCE', 'arrival_time': '4:15 PM'}, {'stop_name': 'Dest B', 'arrival_time': '4:50 PM'}]
                },
                {
                    'bus_number': 'M1',
                    'route_name': 'Route C',
                    'departure_time': '4:30 PM',
                    'stops': [{'stop_name': 'KLNCE', 'arrival_time': '4:30 PM'}, {'stop_name': 'Dest C', 'arrival_time': '5:00 PM'}]
                }
            ]
        })
        self.assertEqual(afternoon_resp.status_code, 201)

        # 3. Student views Nov 20 Morning
        stu_morn = self.client.get('/api/daily-schedules?date=2026-11-20&session=morning')
        self.assertEqual(stu_morn.status_code, 200)
        morn_sched = stu_morn.get_json()['daily_schedules'][0]
        self.assertEqual(morn_sched['buses_count'], 3)
        self.assertEqual([b['bus_number'] for b in morn_sched['buses']], ['S1', 'S2', 'M1'])
        self.assertEqual(morn_sched['buses'][0]['departure_time'], '7:00 AM')

        # 4. Student views Nov 20 Afternoon
        stu_aft = self.client.get('/api/daily-schedules?date=2026-11-20&session=afternoon')
        self.assertEqual(stu_aft.status_code, 200)
        aft_sched = stu_aft.get_json()['daily_schedules'][0]
        self.assertEqual(aft_sched['buses_count'], 3)
        self.assertEqual([b['bus_number'] for b in aft_sched['buses']], ['S1', 'S2', 'M1'])
        self.assertEqual(aft_sched['buses'][0]['departure_time'], '4:00 PM')

        # 5. Student views unpopulated date
        stu_empty = self.client.get('/api/daily-schedules?date=2026-11-21')
        self.assertEqual(stu_empty.status_code, 200)
        self.assertEqual(stu_empty.get_json()['count'], 0)

    def test_daily_schedule_stage4_stats_and_filters(self):
        """Test Stage 4 admin dashboard stats endpoint, bus_number filter, and delete protection."""
        from services.schedule_visibility import ist_now
        today_str = ist_now().strftime('%Y-%m-%d')

        # 1. Unauthenticated or student request to /stats should be rejected
        anon_resp = self.client.get('/api/daily-schedules/stats')
        self.assertIn(anon_resp.status_code, (401, 403))

        stu_resp = self.client.get('/api/daily-schedules/stats', headers=self.student_headers)
        self.assertEqual(stu_resp.status_code, 403)

        # 2. Create a draft schedule for today
        create_draft = self.client.post('/api/daily-schedules', headers=self.admin_headers, json={
            'date': today_str,
            'session': 'morning',
            'status': 'draft',
            'buses': [
                {
                    'bus_number': 'S99',
                    'route_name': 'Stage 4 Route Draft',
                    'departure_time': '07:30 AM',
                    'stops': [{'stop_name': 'Draft Stop 1', 'arrival_time': '07:30 AM'}]
                }
            ]
        })
        self.assertEqual(create_draft.status_code, 201)
        draft_id = create_draft.get_json()['daily_schedule']['id']

        # 3. Create a published schedule for today
        create_pub = self.client.post('/api/daily-schedules', headers=self.admin_headers, json={
            'date': today_str,
            'session': 'afternoon',
            'status': 'published',
            'buses': [
                {
                    'bus_number': 'M77',
                    'route_name': 'Stage 4 Route Pub',
                    'departure_time': '04:15 PM',
                    'stops': [{'stop_name': 'Pub Stop 1', 'arrival_time': '04:15 PM'}]
                }
            ]
        })
        self.assertEqual(create_pub.status_code, 201)
        pub_id = create_pub.get_json()['daily_schedule']['id']

        # 4. Check admin stats endpoint
        stats_resp = self.client.get('/api/daily-schedules/stats', headers=self.admin_headers)
        self.assertEqual(stats_resp.status_code, 200)
        stats = stats_resp.get_json()
        self.assertGreaterEqual(stats['today_published'], 1)
        self.assertGreaterEqual(stats['today_drafts'], 1)
        self.assertGreaterEqual(stats['total_published'], 1)
        self.assertIn('total_buses', stats)
        self.assertIn('total_routes', stats)

        # 5. Test bus_number filter
        filter_s99 = self.client.get('/api/daily-schedules?bus_number=S99', headers=self.admin_headers)
        self.assertEqual(filter_s99.status_code, 200)
        s99_schedules = filter_s99.get_json()['daily_schedules']
        self.assertTrue(any(s['id'] == draft_id for s in s99_schedules))

        filter_none = self.client.get('/api/daily-schedules?bus_number=NONEXISTENT_999', headers=self.admin_headers)
        self.assertEqual(filter_none.status_code, 200)
        self.assertEqual(filter_none.get_json()['count'], 0)

        # 6. Test updating published schedule -> marks is_updated=True and pending_sms_alert=True
        update_pub = self.client.put(f'/api/daily-schedules/{pub_id}', headers=self.admin_headers, json={
            'update_summary': 'Departure delayed by 10 mins',
            'buses': [
                {
                    'bus_number': 'M77',
                    'route_name': 'Stage 4 Route Pub Revised',
                    'departure_time': '04:25 PM',
                    'stops': [{'stop_name': 'Pub Stop 1', 'arrival_time': '04:25 PM'}]
                }
            ]
        })
        self.assertEqual(update_pub.status_code, 200)
        updated_data = update_pub.get_json()['daily_schedule']
        self.assertTrue(updated_data['is_updated'])
        self.assertEqual(updated_data['version'], 2)
        self.assertTrue(updated_data['pending_sms_alert'])
        self.assertEqual(updated_data['update_summary'], 'Departure delayed by 10 mins')

        # 7. Test delete protection: published schedule is archived, NOT permanently deleted from MongoDB
        del_pub = self.client.delete(f'/api/daily-schedules/{pub_id}', headers=self.admin_headers)
        self.assertEqual(del_pub.status_code, 200)
        self.assertTrue(del_pub.get_json().get('archived'))
        # Verify the record is preserved in the database
        preserved = self.db['daily_schedules'].find_one({'_id': pub_id})
        self.assertIsNotNone(preserved)
        self.assertEqual(preserved.get('status'), 'archived')

        # 8. Draft schedule CAN be permanently deleted
        del_draft = self.client.delete(f'/api/daily-schedules/{draft_id}', headers=self.admin_headers)
        self.assertEqual(del_draft.status_code, 200)
        draft_in_db = self.db['daily_schedules'].find_one({'_id': draft_id})
        self.assertIsNone(draft_in_db)

    def test_student_excel_template_and_privacy(self):
        """Test Stage 5 Excel template download and privacy restrictions."""
        # 1. Unauthenticated or student request to template is blocked
        anon_t = self.client.get('/api/students/template')
        self.assertIn(anon_t.status_code, (401, 403))

        stu_t = self.client.get('/api/students/template', headers=self.student_headers)
        self.assertEqual(stu_t.status_code, 403)

        # 2. Admin downloads XLSX template
        xlsx_resp = self.client.get('/api/students/template', headers=self.admin_headers)
        self.assertEqual(xlsx_resp.status_code, 200)
        self.assertIn('spreadsheetml', xlsx_resp.headers.get('Content-Type', ''))
        self.assertGreater(len(xlsx_resp.data), 100)

        # 3. Admin downloads CSV template
        csv_resp = self.client.get('/api/students/template?format=csv', headers=self.admin_headers)
        self.assertEqual(csv_resp.status_code, 200)
        csv_text = csv_resp.data.decode('utf-8-sig')
        self.assertIn('Register Number', csv_text)
        self.assertIn('SAMPLE9106001', csv_text)

    def test_student_upload_preview_and_validation(self):
        """Test Stage 5 Excel/CSV preview validation (sample row exclusion, mobile, duplicates)."""
        import io

        csv_content = (
            "Register Number,Student Name,Department,Year,Section,Student Mobile Number,Parent Mobile Number,Route Name,Regular Bus Number,Boarding Stop\n"
            "SAMPLE9106001,Sample Student (DO NOT IMPORT),CSE,II,A,9876543210,9876543211,Route A,S1,Teppakulam\n"
            "910621104001,Anitha R,CSE,III,A,+91 9876543210,9876543211,Route A,S1,Teppakulam\n"
            "910621104002,Balaji M,ECE,II,B,12345,,Route B,S2,Periyar\n"  # invalid mobile
            "910621104001,Duplicate Anitha,CSE,III,A,9876543212,,Route A,S1,Teppakulam\n"  # duplicate in file
            ",Missing RegNo,MECH,IV,A,9876543213,,Route C,M1,Anna Nagar\n"  # missing reg no
        )

        data = {
            'file': (io.BytesIO(csv_content.encode('utf-8')), 'students_test.csv')
        }

        resp = self.client.post(
            '/api/students/upload-preview',
            headers=self.admin_headers,
            data=data,
            content_type='multipart/form-data'
        )
        self.assertEqual(resp.status_code, 200)
        preview = resp.get_json()

        self.assertEqual(preview['sample_count'], 1)
        self.assertEqual(preview['valid_count'], 1)  # Only Anitha R (first) is valid
        self.assertGreaterEqual(preview['invalid_count'], 3)
        self.assertGreaterEqual(preview['duplicate_in_file_count'], 1)
        self.assertGreaterEqual(preview['invalid_mobile_count'], 1)

    def test_student_import_crud_and_route_allocations(self):
        """Test Stage 5 student import, MongoDB persistence, safe update, manual add, and allocations."""
        # 1. Import new students
        import_resp = self.client.post('/api/students/import', headers=self.admin_headers, json={
            'students': [
                {
                    'row_number': 2,
                    'register_number': '910622104010',
                    'name': 'Kavitha S',
                    'department': 'CSE',
                    'year': 'II',
                    'section': 'A',
                    'student_mobile': '9840123456',
                    'parent_mobile': '9840123457',
                    'route_name': 'Route A - Periyar',
                    'bus_number': 'S1',
                    'boarding_stop': 'Teppakulam'
                },
                {
                    'row_number': 3,
                    'register_number': '910622104011',
                    'name': 'Ramesh K',
                    'department': 'MECH',
                    'year': 'III',
                    'section': 'B',
                    'student_mobile': '9840123458',
                    'parent_mobile': '',
                    'route_name': 'Route B - Thirunagar',
                    'bus_number': 'S2',
                    'boarding_stop': 'Thirunagar'
                }
            ],
            'update_existing': False
        })
        self.assertEqual(import_resp.status_code, 200)
        self.assertEqual(import_resp.get_json()['imported_count'], 2)

        # 2. Re-import with update_existing=False should report existing/failed
        dup_resp = self.client.post('/api/students/import', headers=self.admin_headers, json={
            'students': [
                {
                    'register_number': '910622104010',
                    'name': 'Kavitha S Updated',
                    'department': 'CSE',
                    'year': 'II',
                    'section': 'A',
                    'student_mobile': '9840123456',
                    'route_name': 'Route A - Periyar',
                    'bus_number': 'S1',
                    'boarding_stop': 'Teppakulam'
                }
            ],
            'update_existing': False
        })
        self.assertEqual(dup_resp.status_code, 200)
        self.assertEqual(dup_resp.get_json()['failed_count'], 1)

        # 3. Re-import with update_existing=True should safely update
        up_resp = self.client.post('/api/students/import', headers=self.admin_headers, json={
            'students': [
                {
                    'register_number': '910622104010',
                    'name': 'Kavitha S Revised',
                    'department': 'CSE',
                    'year': 'II',
                    'section': 'B',
                    'student_mobile': '9840999999',
                    'route_name': 'Route A - Periyar',
                    'bus_number': 'S1',
                    'boarding_stop': 'Goripalayam'
                }
            ],
            'update_existing': True
        })
        self.assertEqual(up_resp.status_code, 200)
        self.assertEqual(up_resp.get_json()['updated_count'], 1)

        # 4. Search and filter students
        list_resp = self.client.get('/api/students?q=Kavitha', headers=self.admin_headers)
        self.assertEqual(list_resp.status_code, 200)
        results = list_resp.get_json()['students']
        self.assertEqual(len(results), 1)
        kavitha = results[0]
        self.assertEqual(kavitha['name'], 'Kavitha S Revised')
        self.assertEqual(kavitha['student_mobile'], '9840999999')
        self.assertEqual(kavitha['boarding_stop'], 'Goripalayam')

        # Filter by department
        cse_resp = self.client.get('/api/students?department=CSE', headers=self.admin_headers)
        self.assertEqual(cse_resp.status_code, 200)
        self.assertGreaterEqual(cse_resp.get_json()['total'], 1)

        # Filter by bus number
        s1_resp = self.client.get('/api/students?bus_number=S1', headers=self.admin_headers)
        self.assertEqual(s1_resp.status_code, 200)
        self.assertGreaterEqual(s1_resp.get_json()['total'], 1)

        # 5. Manual Add Student
        manual_add = self.client.post('/api/students', headers=self.admin_headers, json={
            'register_number': '910622104020',
            'name': 'Deepak V',
            'department': 'IT',
            'year': 'I',
            'student_mobile': '9840112233',
            'route_name': 'Route A - Periyar',
            'bus_number': 'S1',
            'boarding_stop': 'Simmakkal'
        })
        self.assertEqual(manual_add.status_code, 201)
        deepak_id = manual_add.get_json()['student']['id']

        # 6. Toggle transport status
        toggle_resp = self.client.patch(f'/api/students/{deepak_id}/status', headers=self.admin_headers, json={
            'is_transport_active': False
        })
        self.assertEqual(toggle_resp.status_code, 200)
        self.assertFalse(toggle_resp.get_json()['student']['is_transport_active'])

        # 7. Check Route Allocations summary
        alloc_resp = self.client.get('/api/students/route-allocations', headers=self.admin_headers)
        self.assertEqual(alloc_resp.status_code, 200)
        alloc_data = alloc_resp.get_json()
        self.assertGreaterEqual(alloc_data['total_students'], 3)
        self.assertTrue(any(r['route_name'] == 'Route A - Periyar' for r in alloc_data['routes']))
        self.assertTrue(any(b['bus_number'] == 'S1' for b in alloc_data['buses']))

        # 8. SMS Recipients Retrieval (Admin only, privacy check)
        sms_all = self.client.get('/api/students/sms-recipients?target=all_active', headers=self.admin_headers)
        self.assertEqual(sms_all.status_code, 200)
        self.assertGreaterEqual(sms_all.get_json()['count'], 2)

        sms_route = self.client.get('/api/students/sms-recipients?target=route&route_name=Route+A+-+Periyar', headers=self.admin_headers)
        self.assertEqual(sms_route.status_code, 200)

        # Privacy check: student cannot access sms-recipients
        sms_stu = self.client.get('/api/students/sms-recipients', headers=self.student_headers)
        self.assertEqual(sms_stu.status_code, 403)

    # ------------------------------------------------------------------ #
    # 21. Stage 6: Android SIM-Based SMS Integration Tests                #
    # ------------------------------------------------------------------ #
    def test_stage_6_sms_integration(self):
        """
        Verify Stage 6: Android Phone SIM-based SMS Integration backend endpoints:
        - Query recipients by target (all_active, route, bus, selected).
        - Privacy: ensure students cannot query recipients or campaigns.
        - Create test SMS campaign (validating mobile number).
        - Create bulk SMS campaign.
        - Update campaign dispatch progress with per-recipient statuses.
        - List campaign history.
        - Retrieve campaign details.
        """
        from models.student import Student

        # Seed students for SMS tests
        s1 = Student(
            register_number='912822104001',
            name='Kavitha Raman',
            department='CSE',
            year='IV',
            section='A',
            student_mobile='9840123456',
            parent_mobile='9840123457',
            route_name='Route 1 - Mattuthavani',
            bus_number='S1',
            boarding_stop='KK Nagar',
            is_transport_active=True
        )
        s1.save()

        s2 = Student(
            register_number='912822104002',
            name='Suresh Kumar',
            department='ECE',
            year='III',
            section='B',
            student_mobile='9790123456',
            route_name='Route 2 - Periyar',
            bus_number='S2',
            boarding_stop='Simmakkal',
            is_transport_active=True
        )
        s2.save()

        s3 = Student(
            register_number='912822104003',
            name='Meenakshi Sundaram',
            department='MECH',
            year='II',
            section='A',
            student_mobile='9443123456',
            route_name='Route 1 - Mattuthavani',
            bus_number='S1',
            boarding_stop='Anna Nagar',
            is_transport_active=False  # INACTIVE — should NOT be included in all_active
        )
        s3.save()

        # 1. Test recipient query via /api/sms/recipients
        # All active (should return s1 and s2, but not inactive s3)
        resp_all = self.client.get('/api/sms/recipients?target=all_active', headers=self.admin_headers)
        self.assertEqual(resp_all.status_code, 200)
        data_all = resp_all.get_json()
        self.assertEqual(data_all['count'], 2)
        reg_numbers = [r['register_number'] for r in data_all['recipients']]
        self.assertIn('912822104001', reg_numbers)
        self.assertIn('912822104002', reg_numbers)
        self.assertNotIn('912822104003', reg_numbers)

        # Route query
        resp_route = self.client.get('/api/sms/recipients?target=route&route_name=Route+1+-+Mattuthavani', headers=self.admin_headers)
        self.assertEqual(resp_route.status_code, 200)
        self.assertEqual(resp_route.get_json()['count'], 1)
        self.assertEqual(resp_route.get_json()['recipients'][0]['register_number'], '912822104001')

        # Bus query
        resp_bus = self.client.get('/api/sms/recipients?target=bus&bus_number=S2', headers=self.admin_headers)
        self.assertEqual(resp_bus.status_code, 200)
        self.assertEqual(resp_bus.get_json()['count'], 1)
        self.assertEqual(resp_bus.get_json()['recipients'][0]['bus_number'], 'S2')

        # Selected query
        resp_sel = self.client.get(f'/api/sms/recipients?target=selected&student_ids={s1.id}', headers=self.admin_headers)
        self.assertEqual(resp_sel.status_code, 200)
        self.assertEqual(resp_sel.get_json()['count'], 1)

        # 2. Security / Privacy: students forbidden
        resp_stu = self.client.get('/api/sms/recipients', headers=self.student_headers)
        self.assertEqual(resp_stu.status_code, 403)

        resp_stu_post = self.client.post('/api/sms/campaigns', headers=self.student_headers, json={'message': 'test'})
        self.assertEqual(resp_stu_post.status_code, 403)

        # 3. Create Test SMS Campaign
        # Invalid mobile number rejected
        resp_invalid_test = self.client.post('/api/sms/campaigns', headers=self.admin_headers, json={
            'target_type': 'test',
            'test_phone': '12345',  # invalid
            'message': 'Test SMS from admin phone'
        })
        self.assertEqual(resp_invalid_test.status_code, 400)

        # Valid test SMS
        resp_test = self.client.post('/api/sms/campaigns', headers=self.admin_headers, json={
            'target_type': 'test',
            'test_phone': '9876543210',
            'message': 'Test SMS from admin phone SIM',
            'sender_device': {'model': 'SM-G998B', 'sim_slot': 0, 'carrier': 'Jio 4G'}
        })
        self.assertEqual(resp_test.status_code, 201)
        test_camp = resp_test.get_json()['campaign']
        self.assertEqual(test_camp['total_recipients'], 1)
        self.assertEqual(test_camp['recipients'][0]['mobile_number'], '9876543210')

        # 4. Create Bulk SMS Campaign for Route 1
        resp_camp = self.client.post('/api/sms/campaigns', headers=self.admin_headers, json={
            'title': 'Morning Route 1 Delay Notice',
            'message': 'Dear Student, Bus S1 is delayed by 10 minutes due to traffic.',
            'target_type': 'route',
            'route_name': 'Route 1 - Mattuthavani',
            'delivery_method': 'direct_sim',
            'sender_device': {'model': 'SM-G998B', 'sim_slot': 0, 'carrier': 'Jio 4G'}
        })
        self.assertEqual(resp_camp.status_code, 201)
        camp_data = resp_camp.get_json()['campaign']
        camp_id = camp_data['id']
        self.assertEqual(camp_data['total_recipients'], 1)
        self.assertEqual(camp_data['status'], 'draft')

        # 5. Update Dispatch Progress from Phone
        # Phone reports message sent to Android SMS service
        update_resp = self.client.put(f'/api/sms/campaigns/{camp_id}/status', headers=self.admin_headers, json={
            'status': 'sending',
            'recipient_updates': [
                {
                    'student_id': s1.id,
                    'status': 'sent_to_sms_service',
                    'dispatched_at': '2026-11-20T13:35:00Z'
                }
            ]
        })
        self.assertEqual(update_resp.status_code, 200)
        updated_camp = update_resp.get_json()['campaign']
        self.assertEqual(updated_camp['sent_count'], 1)
        self.assertEqual(updated_camp['failed_count'], 0)
        self.assertEqual(updated_camp['pending_count'], 0)
        self.assertEqual(updated_camp['status'], 'completed')

        # 6. List Campaigns
        list_resp = self.client.get('/api/sms/campaigns', headers=self.admin_headers)
        self.assertEqual(list_resp.status_code, 200)
        self.assertGreaterEqual(list_resp.get_json()['count'], 2)

        # 7. Get Campaign Details
        detail_resp = self.client.get(f'/api/sms/campaigns/{camp_id}', headers=self.admin_headers)
        self.assertEqual(detail_resp.status_code, 200)
        self.assertEqual(detail_resp.get_json()['recipients'][0]['status'], 'sent_to_sms_service')

    # ------------------------------------------------------------------ #
    # 22. Stage 7: SMS Confirmation, Bulk Sending & Status Tracking Tests  #
    # ------------------------------------------------------------------ #
    def test_stage_7_sms_confirmation_bulk_and_status_tracking(self):
        """
        Verify Stage 7 features:
        - Recipient Preview with duplicate detection and masking.
        - Segment calculation endpoint.
        - Batch status tracking with submitted, delivery confirmed, failed, and cancelled.
        - Pause and Resume campaign endpoints.
        - Cancel pending messages in a campaign.
        - Selective retry of failed messages (strictly never re-sending successful ones).
        """
        from models.student import Student

        # 1. Seed students including duplicate numbers (e.g. siblings sharing parent/student mobile)
        s_a = Student(
            register_number='912822105001',
            name='Arun Kumar',
            department='CSE',
            year='III',
            student_mobile='9840999001',
            route_name='Route 5 - Thirunagar',
            bus_number='M2',
            boarding_stop='Thirunagar',
            is_transport_active=True,
        )
        s_a.save()

        # Sibling sharing the exact same mobile number
        s_b = Student(
            register_number='912822105002',
            name='Anitha Kumar',
            department='ECE',
            year='I',
            student_mobile='9840999001',  # DUPLICATE NUMBER
            route_name='Route 5 - Thirunagar',
            bus_number='M2',
            boarding_stop='Thirunagar',
            is_transport_active=True,
        )
        s_b.save()

        s_c = Student(
            register_number='912822105003',
            name='Bala Murugan',
            department='MECH',
            year='IV',
            student_mobile='9840999002',  # Unique number
            route_name='Route 5 - Thirunagar',
            bus_number='M2',
            boarding_stop='Thirunagar',
            is_transport_active=True,
        )
        s_c.save()

        # Invalid mobile number student
        s_d = Student(
            register_number='912822105004',
            name='Chandran R',
            department='CIVIL',
            year='II',
            student_mobile='12345',  # INVALID
            route_name='Route 5 - Thirunagar',
            bus_number='M2',
            boarding_stop='Thirunagar',
            is_transport_active=True,
        )
        s_d.save()

        # 2. Test Recipient Preview API with Route filter
        prev_resp = self.client.get(
            '/api/sms/recipients?target=route&route_name=Route+5+-+Thirunagar',
            headers=self.admin_headers,
        )
        self.assertEqual(prev_resp.status_code, 200)
        pdata = prev_resp.get_json()
        self.assertEqual(pdata['total_selected_students'], 4)
        self.assertEqual(pdata['valid_count'], 3)
        self.assertEqual(pdata['invalid_count'], 1)
        self.assertEqual(pdata['duplicate_count'], 1)
        # By default (allow_duplicates=false), duplicates are prevented
        self.assertEqual(pdata['effective_recipient_count'], 2)
        self.assertEqual(pdata['duplicates_prevented'], 1)
        # Check masked mobile
        self.assertTrue(pdata['recipients'][0]['masked_mobile'].startswith('+91'))
        self.assertIn('***', pdata['recipients'][0]['masked_mobile'])

        # 3. Test Segment Calculation Endpoint
        seg_resp = self.client.post('/api/sms/calculate-segments', headers=self.admin_headers, json={
            'message': 'Short alert under 160 characters.'
        })
        self.assertEqual(seg_resp.status_code, 200)
        self.assertEqual(seg_resp.get_json()['segments_per_message'], 1)

        long_msg = 'A' * 170
        seg_long = self.client.post('/api/sms/calculate-segments', headers=self.admin_headers, json={
            'message': long_msg
        })
        self.assertEqual(seg_long.status_code, 200)
        self.assertEqual(seg_long.get_json()['segments_per_message'], 2)

        # 4. Create Campaign with Deduplication Enabled (Default)
        create_resp = self.client.post('/api/sms/campaigns', headers=self.admin_headers, json={
            'title': 'Route 5 Morning Delay',
            'message': 'Bus M2 will depart 10 minutes late today.',
            'target_type': 'route',
            'route_name': 'Route 5 - Thirunagar',
            'allow_duplicates': False,
            'sender_device': {'model': 'Pixel 8', 'carrier': 'Airtel', 'sim_slot': 0},
        })
        self.assertEqual(create_resp.status_code, 201)
        camp = create_resp.get_json()['campaign']
        camp_id = camp['id']
        # 2 unique valid phone numbers
        self.assertEqual(camp['total_recipients'], 2)
        self.assertEqual(camp['duplicates_prevented_count'], 1)

        # Check recipient fields have Stage 7 metadata
        r0 = camp['recipients'][0]
        self.assertIn('message_ref', r0)
        self.assertIn('masked_mobile', r0)
        self.assertEqual(r0['status'], 'pending')

        # 5. Pause and Resume Campaign
        pause_resp = self.client.post(f'/api/sms/campaigns/{camp_id}/pause', headers=self.admin_headers)
        self.assertEqual(pause_resp.status_code, 200)
        self.assertEqual(pause_resp.get_json()['campaign']['status'], 'paused')

        resume_resp = self.client.post(f'/api/sms/campaigns/{camp_id}/resume', headers=self.admin_headers)
        self.assertEqual(resume_resp.status_code, 200)
        self.assertEqual(resume_resp.get_json()['campaign']['status'], 'sending')

        # 6. Simulate Status Tracking updates:
        # First recipient submitted to SMS service
        # Second recipient fails (e.g. NO_SERVICE)
        upd_resp = self.client.put(f'/api/sms/campaigns/{camp_id}/status', headers=self.admin_headers, json={
            'status': 'sending',
            'recipient_updates': [
                {
                    'student_id': s_a.id,
                    'status': 'submitted_to_sms_service',
                    'sent_at': '2026-11-20T16:25:00Z',
                },
                {
                    'student_id': s_c.id,
                    'status': 'failed',
                    'error_reason': 'NO_SERVICE (no signal)',
                }
            ]
        })
        self.assertEqual(upd_resp.status_code, 200)
        upd_camp = upd_resp.get_json()['campaign']
        self.assertEqual(upd_camp['submitted_count'], 1)
        self.assertEqual(upd_camp['failed_count'], 1)
        self.assertEqual(upd_camp['status'], 'partially_failed')

        # 7. Delivery Report Confirmation for Recipient 1
        deliv_resp = self.client.put(f'/api/sms/campaigns/{camp_id}/status', headers=self.admin_headers, json={
            'recipient_updates': [
                {
                    'student_id': s_a.id,
                    'status': 'delivery_confirmed',
                    'delivered_at': '2026-11-20T16:25:30Z',
                }
            ]
        })
        self.assertEqual(deliv_resp.status_code, 200)
        self.assertEqual(deliv_resp.get_json()['campaign']['delivery_confirmed_count'], 1)

        # 8. Cancel Pending Recipients test on a new campaign
        cancel_camp_resp = self.client.post('/api/sms/campaigns', headers=self.admin_headers, json={
            'title': 'Test Cancel Campaign',
            'message': 'Cancel test',
            'target_type': 'route',
            'route_name': 'Route 5 - Thirunagar',
        })
        cancel_id = cancel_camp_resp.get_json()['campaign']['id']
        cancel_action = self.client.post(f'/api/sms/campaigns/{cancel_id}/cancel-pending', headers=self.admin_headers)
        self.assertEqual(cancel_action.status_code, 200)
        c_res = cancel_action.get_json()['campaign']
        self.assertEqual(c_res['status'], 'cancelled')
        self.assertTrue(all(r['status'] == 'cancelled' for r in c_res['recipients']))

        # 9. Selective Retry of Failed Messages
        # On camp_id, recipient s_c was failed, s_a was delivery_confirmed
        retry_resp = self.client.post(f'/api/sms/campaigns/{camp_id}/retry-failed', headers=self.admin_headers)
        self.assertEqual(retry_resp.status_code, 200)
        retried_camp = retry_resp.get_json()['campaign']
        recips = {r['student_id']: r for r in retried_camp['recipients']}

        # Failed recipient s_c is reset to 'pending' with error cleared
        self.assertEqual(recips[s_c.id]['status'], 'pending')
        self.assertIsNone(recips[s_c.id]['error_reason'])

        # Successful recipient s_a is UNTOUCHED (still delivery_confirmed)!
        self.assertEqual(recips[s_a.id]['status'], 'delivery_confirmed')
        self.assertEqual(retried_camp['submitted_count'], 1)


if __name__ == '__main__':
    unittest.main()
