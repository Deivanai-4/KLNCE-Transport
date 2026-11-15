import unittest
from unittest.mock import patch

from flask import Flask

from models import db
from models.notification import Notification
from models.user import User
from routes.notifications import notifications_bp


class NotificationDeletionTests(unittest.TestCase):
    def setUp(self):
        app = Flask(__name__)
        app.config.update(
            TESTING=True,
            SECRET_KEY='test-secret',
            SQLALCHEMY_DATABASE_URI='sqlite:///:memory:',
            SQLALCHEMY_TRACK_MODIFICATIONS=False,
        )
        db.init_app(app)
        app.register_blueprint(notifications_bp)

        self.app = app
        self.app_context = app.app_context()
        self.app_context.push()
        db.create_all()

        admin = User(
            name='Test Admin',
            email='admin@example.test',
            password_hash='test-hash',
            role='admin',
        )
        student = User(
            name='Test Student',
            email='student@example.test',
            password_hash='test-hash',
            role='student',
        )
        db.session.add_all([admin, student])
        db.session.flush()

        notification = Notification(
            title='Bus delay',
            body='A test alert',
            type='general',
            sent_by=admin.id,
            recipient_count=0,
        )
        db.session.add(notification)
        db.session.commit()

        self.notification_id = notification.id
        self.claims_by_token = {
            'admin-token': {
                'email': admin.email,
                'email_verified': True,
            },
            'student-token': {
                'email': student.email,
                'email_verified': True,
            },
        }
        self.firebase_verification = patch(
            'routes.auth.verify_firebase_id_token',
            side_effect=self.claims_by_token.__getitem__,
        )
        self.firebase_verification.start()
        self.addCleanup(self.firebase_verification.stop)
        self.admin_headers = {'Authorization': 'Bearer admin-token'}
        self.student_headers = {'Authorization': 'Bearer student-token'}
        self.client = app.test_client()

    def tearDown(self):
        db.session.remove()
        db.drop_all()
        self.app_context.pop()

    def test_only_admins_can_delete_alerts(self):
        path = f'/api/notifications/{self.notification_id}'

        self.assertEqual(self.client.delete(path).status_code, 401)
        self.assertEqual(
            self.client.delete(path, headers=self.student_headers).status_code,
            403,
        )
        self.assertIsNotNone(db.session.get(Notification, self.notification_id))

    def test_admin_delete_removes_alert_from_public_history(self):
        path = f'/api/notifications/{self.notification_id}'

        response = self.client.delete(path, headers=self.admin_headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            self.client.get('/api/notifications/history').get_json()['notifications'],
            [],
        )


if __name__ == '__main__':
    unittest.main()
