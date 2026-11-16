import os
import unittest
from datetime import date, datetime
from unittest.mock import patch
from zoneinfo import ZoneInfo

os.environ['FLASK_ENV'] = 'testing'

from app import create_app
from config import TestingConfig
from models.database import get_db
from models.schedule import ScheduleDocument
from models.user import User

IST = ZoneInfo('Asia/Kolkata')


class ScheduleVisibilityTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app(TestingConfig)
        self.app_context = self.app.app_context()
        self.app_context.push()

        db = get_db()
        db['users'].delete_many({})
        db['schedule_documents'].delete_many({})
        db['bus_routes'].delete_many({})
        db['route_stops'].delete_many({})

        user = User(
            name='Schedule Test Admin',
            email='schedule-test@example.test',
            password_hash='unused-test-hash',
            role='admin',
        )
        user.save()

        self.schedules = {}
        for direction in ('incoming', 'outgoing'):
            schedule = ScheduleDocument(
                title=f'{direction} schedule',
                file_url='',
                file_type='image',
                trip_direction=direction,
                college='both',
                effective_date='2026-11-14',
                status='published',
                created_by=user.id,
            )
            schedule.save()
            self.schedules[direction] = schedule

        self.client = self.app.test_client()

    def tearDown(self):
        self.app_context.pop()

    def test_published_schedule_switches_at_ist_cutoffs_without_deleting_rows(self):
        cases = [
            (11, 59, 'incoming'),
            (12, 0, 'outgoing'),
            (20, 59, 'outgoing'),
            (21, 0, None),
            (0, 0, 'incoming'),
        ]
        for hour, minute, expected in cases:
            day = 15 if hour == 0 else 14
            now = datetime(2026, 11, day, hour, minute, tzinfo=IST)
            with self.subTest(time=now.isoformat()):
                with patch('routes.schedules.ist_now', return_value=now):
                    response = self.client.get('/api/schedules/published')
                self.assertEqual(response.status_code, 200)
                payload = response.get_json()
                self.assertEqual(payload['active_trip'], expected)
                actual = payload['schedule']
                self.assertEqual(
                    actual['trip_direction'] if actual else None,
                    expected,
                )
                self.assertEqual(
                    get_db()['schedule_documents'].count_documents({'status': 'published'}),
                    2,
                )

    def test_expired_direction_is_hidden_even_when_requested_directly(self):
        now = datetime(2026, 11, 14, 12, 0, tzinfo=IST)
        with patch('routes.schedules.ist_now', return_value=now):
            response = self.client.get(
                '/api/schedules/published?trip=incoming',
            )

        self.assertEqual(response.status_code, 200)
        self.assertIsNone(response.get_json()['schedule'])
        self.assertEqual(response.get_json()['active_trip'], 'outgoing')

    def test_bus_search_uses_the_active_trip_when_no_direction_is_given(self):
        now = datetime(2026, 11, 14, 12, 0, tzinfo=IST)
        with patch('routes.buses.ist_now', return_value=now):
            response = self.client.get('/api/buses/search?stop=Teppakulam')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()['active_trip'], 'outgoing')


if __name__ == '__main__':
    unittest.main()
