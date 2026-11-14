import unittest

from flask import Flask
from flask_jwt_extended import JWTManager, create_access_token

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
            JWT_SECRET_KEY='test-jwt-secret-for-notification-deletion',
            SQLALCHEMY_DATABASE_URI='sqlite:///:memory:',
            SQLALCHEMY_TRACK_MODIFICATIONS=False,
        )
        db.init_app(app)
        JWTManager(app)
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
        self.admin_headers = self._authorization_headers(admin.id, 'admin')
        self.student_headers = self._authorization_headers(student.id, 'student')
        self.client = app.test_client()

    def tearDown(self):
        db.session.remove()
        db.drop_all()
        self.app_context.pop()

    def _authorization_headers(self, user_id, role):
        token = create_access_token(
            identity=str(user_id),
            additional_claims={'role': role},
        )
        return {'Authorization': f'Bearer {token}'}

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
