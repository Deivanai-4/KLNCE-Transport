"""Link a verified Firebase account to an administrator transport profile."""

import argparse
import sys

from app import create_app
from firebase_admin import auth
from models.database import get_db
from models.user import User, _doc_to_obj
from services.firebase_service import initialize_firebase


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Link a verified Firebase account to an administrator profile."
    )
    parser.add_argument("--email", required=True, help="Verified Firebase account email")
    parser.add_argument(
        "--current-email",
        help="Existing administrator profile email to update",
    )
    args = parser.parse_args()

    email = args.email.strip().lower()
    if not email:
        parser.error("--email cannot be empty")

    app = create_app()
    with app.app_context():
        if not initialize_firebase():
            print(
                "Firebase Admin is unavailable. Configure FIREBASE_CREDENTIALS "
                "or FIREBASE_CREDENTIALS_PATH.",
                file=sys.stderr,
            )
            return 1

        try:
            firebase_user = auth.get_user_by_email(email)
        except auth.UserNotFoundError:
            print("Create this account in Firebase Authentication first.", file=sys.stderr)
            return 1
        if not firebase_user.email_verified:
            print("Verify the Firebase account email before linking it.", file=sys.stderr)
            return 1

        existing_target = User.find_by_email(email)
        if existing_target and existing_target.role != "admin":
            print(
                "The requested email is already used by a non-admin account.",
                file=sys.stderr,
            )
            return 1

        db = get_db()

        if existing_target:
            admin = existing_target
        elif args.current_email:
            admin = User.find_by_email(args.current_email.strip().lower())
            if not admin or admin.role != "admin":
                print(
                    "The current email does not identify an administrator.",
                    file=sys.stderr,
                )
                return 1
        else:
            admin_docs = list(db['users'].find({"role": "admin"}))
            admins = [_doc_to_obj(d) for d in admin_docs]
            if len(admins) > 1:
                print(
                    "Specify --current-email to select the administrator to update.",
                    file=sys.stderr,
                )
                return 1
            if admins:
                admin = admins[0]
            else:
                admin = User(
                    name="Transport Department Admin",
                    email=email,
                    password_hash=None,
                    role="admin",
                    college="both",
                )
                admin.save()

        if admin.email != email:
            email_in_use = User.find_by_email(email)
            if email_in_use and email_in_use.id != admin.id:
                print("The requested email is already in use.", file=sys.stderr)
                return 1

        admin.email = email
        admin.is_active = True
        admin.save()

    print("Verified Firebase account linked to the administrator profile.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
