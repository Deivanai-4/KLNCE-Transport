"""Firebase ID token verification for authenticated API requests."""

from typing import Any

from services.firebase_service import initialize_firebase


class FirebaseAuthUnavailable(Exception):
    """Raised when the Firebase Admin SDK cannot verify tokens."""


class InvalidFirebaseToken(Exception):
    """Raised when Firebase rejects an ID token."""


def verify_firebase_id_token(token: str) -> dict[str, Any]:
    if not initialize_firebase():
        raise FirebaseAuthUnavailable

    from firebase_admin import auth
    from firebase_admin.exceptions import FirebaseError

    try:
        return auth.verify_id_token(token, check_revoked=True)
    except (
        ValueError,
        auth.InvalidIdTokenError,
        auth.ExpiredIdTokenError,
        auth.RevokedIdTokenError,
        auth.UserDisabledError,
    ) as exc:
        raise InvalidFirebaseToken from exc
    except FirebaseError as exc:
        raise FirebaseAuthUnavailable from exc
