import unittest
from flask import Flask
from flask_jwt_extended import JWTManager, create_access_token
import mongomock

from models.database import init_db, get_db
from models.notification import Notification
from models.user import User
from routes.notifications import notifications_bp
from routes.auth import auth_bp


class NotificationDeletionTests(unittest.TestCase):
    def setUp(self):
        app = Flask(__name__)
        app.config.update(
            TESTING=True,
            SECRET_KEY='test-secret',
            JWT_SECRET_KEY='test-jwt-secret',
            MONGODB_URI='',
            MONGODB_DATABASE='klnce_transport_test',
        )
        init_db(app)
        JWTManager(app)
        app.register_blueprint(auth_bp)
        app.register_blueprint(notifications_bp)

        self.app = app
        self.app_context = app.app_context()
        self.app_context.push()

        # Clean test DB
        db = get_db()
        db['users'].delete_many({})
        db['notifications'].delete_many({})

        admin = User(
            name='Test Admin',
            email='admin@example.test',
            password_hash='test-hash',
            role='admin',
        )
        admin.save()

        student = User(
            name='Test Student',
            email='student@example.test',
            password_hash='test-hash',
            role='student',
        )
        student.save()

        notification = Notification(
            title='Bus delay',
            body='A test alert',
            type='general',
            sent_by=admin.id,
            recipient_count=0,
        )
        notification.save()

        self.notification_id = notification.id
        self.admin_token = create_access_token(identity=admin.email)
        self.student_token = create_access_token(identity=student.email)
        self.admin_headers = {'Authorization': f'Bearer {self.admin_token}'}
        self.student_headers = {'Authorization': f'Bearer {self.student_token}'}
        self.client = app.test_client()

    def tearDown(self):
        self.app_context.pop()

    def test_only_admins_can_delete_alerts(self):
        path = f'/api/notifications/{self.notification_id}'

        self.assertEqual(self.client.delete(path).status_code, 401)
        self.assertEqual(
            self.client.delete(path, headers=self.student_headers).status_code,
            403,
        )
        self.assertIsNotNone(Notification.find_by_id(self.notification_id))

    def test_admin_delete_removes_alert_from_public_history(self):
        path = f'/api/notifications/{self.notification_id}'

        response = self.client.delete(path, headers=self.admin_headers)
        self.assertEqual(response.status_code, 200)
        history_resp = self.client.get('/api/notifications/history')
        self.assertEqual(history_resp.get_json()['notifications'], [])


if __name__ == '__main__':
    unittest.main()
