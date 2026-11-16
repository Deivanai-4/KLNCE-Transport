import unittest
from flask import Flask
from flask_jwt_extended import JWTManager, create_access_token
import mongomock

from models.database import init_db, get_db
from models.user import User
from routes.auth import auth_bp


class FirebaseAuthenticationTests(unittest.TestCase):
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

        self.app_context = app.app_context()
        self.app_context.push()

        db = get_db()
        db['users'].delete_many({})

        user = User(
            name='Test Student',
            email='student@example.test',
            password_hash='unused',
            role='student',
        )
        user.save()
        self.user_id = user.id

        self.valid_token = create_access_token(identity='student@example.test')
        self.unlinked_token = create_access_token(identity='other@example.test')
        self.client = app.test_client()

    def tearDown(self):
        self.app_context.pop()

    def test_me_returns_the_database_profile_for_a_verified_user(self):
        response = self.client.get(
            '/api/auth/me',
            headers={'Authorization': f'Bearer {self.valid_token}'},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()['user']['id'], self.user_id)

    def test_me_rejects_missing_identity(self):
        self.assertEqual(self.client.get('/api/auth/me').status_code, 401)

    def test_me_rejects_accounts_without_a_transport_profile(self):
        response = self.client.get(
            '/api/auth/me',
            headers={'Authorization': f'Bearer {self.unlinked_token}'},
        )

        self.assertEqual(response.status_code, 403)


if __name__ == '__main__':
    unittest.main()
