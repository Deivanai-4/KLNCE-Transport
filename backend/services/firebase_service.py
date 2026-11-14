"""
Firebase Admin SDK integration for FCM Push Notifications and Cloud Storage.
"""

import os
import json
import logging
from typing import Optional, Dict, Any

logger = logging.getLogger(__name__)

_firebase_initialized = False


def initialize_firebase():
    """Initializes Firebase Admin SDK from environment variables or local service account file."""
    global _firebase_initialized
    if _firebase_initialized:
        return True

    try:
        import firebase_admin
        from firebase_admin import credentials

        cred_json = os.environ.get('FIREBASE_CREDENTIALS')
        cred_path = os.environ.get('FIREBASE_CREDENTIALS_PATH', 'firebase-credentials.json')

        if cred_json:
            cred_dict = json.loads(cred_json)
            cred = credentials.Certificate(cred_dict)
            firebase_admin.initialize_app(cred)
            _firebase_initialized = True
            logger.info("Firebase Admin SDK initialized via environment JSON.")
            return True
        elif os.path.exists(cred_path):
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
            _firebase_initialized = True
            logger.info("Firebase Admin SDK initialized via credentials file %s.", cred_path)
            return True
        else:
            logger.warning("No Firebase credentials provided. Push notifications will run in mock mode.")
            return False
    except Exception as e:
        logger.warning("Failed to initialize Firebase Admin SDK: %s", e)
        return False


def send_notification_to_all(title: str, body: str, data: Optional[Dict[str, str]] = None) -> int:
    """
    Sends FCM push notification to topic 'klnce_transport'.
    Returns estimated recipient count or 1 on success.
    """
    if not initialize_firebase():
        logger.info("[Mock FCM] Broadcast Notification: '%s' - '%s'", title, body)
        return 1

    try:
        from firebase_admin import messaging
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data=data or {},
            topic='klnce_transport'
        )
        response = messaging.send(message)
        logger.info("FCM message sent successfully to topic: %s", response)
        return 1
    except Exception as e:
        logger.error("Error sending FCM notification: %s", e)
        return 0


def send_notification_to_token(token: str, title: str, body: str, data: Optional[Dict[str, str]] = None) -> bool:
    """Sends targeted FCM notification to an individual device token."""
    if not token:
        return False

    if not initialize_firebase():
        logger.info("[Mock FCM] To %s: '%s' - '%s'", token[:10], title, body)
        return True

    try:
        from firebase_admin import messaging
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data=data or {},
            token=token
        )
        messaging.send(message)
        return True
    except Exception as e:
        logger.error("Failed to send notification to token: %s", e)
        return False

