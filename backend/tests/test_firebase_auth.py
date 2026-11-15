import unittest
from unittest.mock import patch

from flask import Flask

from models import db
from models.user import User
from routes.auth import auth_bp


class FirebaseAuthenticationTests(unittest.TestCase):
    def setUp(self):
        app = Flask(__name__)
        app.config.update(
            TESTING=True,
            SQLALCHEMY_DATABASE_URI='sqlite:///:memory:',
            SQLALCHEMY_TRACK_MODIFICATIONS=False,
        )
        db.init_app(app)
        app.register_blueprint(auth_bp)

        self.app_context = app.app_context()
        self.app_context.push()
        db.create_all()

        user = User(
            name='Test Student',
            email='student@example.test',
            password_hash='unused',
            role='student',
        )
        db.session.add(user)
        db.session.commit()
        self.user_id = user.id

        self.claims_by_token = {
            'valid-token': {
                'email': 'student@example.test',
                'email_verified': True,
            },
            'unverified-token': {
                'email': 'student@example.test',
                'email_verified': False,
            },
            'unlinked-token': {
                'email': 'other@example.test',
                'email_verified': True,
            },
        }
        self.firebase_verification = patch(
            'routes.auth.verify_firebase_id_token',
            side_effect=self.claims_by_token.__getitem__,
        )
        self.firebase_verification.start()
        self.addCleanup(self.firebase_verification.stop)
        self.client = app.test_client()

    def tearDown(self):
        db.session.remove()
        db.drop_all()
        self.app_context.pop()

    def test_me_returns_the_database_profile_for_a_verified_firebase_user(self):
        response = self.client.get(
            '/api/auth/me',
            headers={'Authorization': 'Bearer valid-token'},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()['user']['id'], self.user_id)

    def test_me_rejects_missing_or_unverified_firebase_identity(self):
        self.assertEqual(self.client.get('/api/auth/me').status_code, 401)
        response = self.client.get(
            '/api/auth/me',
            headers={'Authorization': 'Bearer unverified-token'},
        )

        self.assertEqual(response.status_code, 403)

    def test_me_rejects_firebase_accounts_without_a_transport_profile(self):
        response = self.client.get(
            '/api/auth/me',
            headers={'Authorization': 'Bearer unlinked-token'},
        )

        self.assertEqual(response.status_code, 403)


if __name__ == '__main__':
    unittest.main()
