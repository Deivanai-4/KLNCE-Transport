"""Create or update an administrator account without storing a plaintext password."""

import argparse
import getpass
import sys

from app import create_app
from models import db
from models.user import User


def _read_password(read_stdin: bool) -> str:
    if read_stdin:
        return sys.stdin.readline().rstrip("\r\n")

    password = getpass.getpass("New administrator password: ")
    confirmation = getpass.getpass("Confirm password: ")
    if password != confirmation:
        raise ValueError("Passwords do not match")
    return password


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Securely create or update an administrator login."
    )
    parser.add_argument("--email", required=True, help="Administrator email to set")
    parser.add_argument(
        "--current-email",
        help="Existing administrator email to update when multiple admins exist",
    )
    parser.add_argument(
        "--password-stdin",
        action="store_true",
        help="Read one password line from stdin instead of prompting",
    )
    args = parser.parse_args()

    email = args.email.strip().lower()
    if not email:
        parser.error("--email cannot be empty")

    try:
        password = _read_password(args.password_stdin)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    if not password:
        print("Password cannot be empty", file=sys.stderr)
        return 2
    if len(password.encode("utf-8")) > 72:
        print("Password must be 72 UTF-8 bytes or fewer", file=sys.stderr)
        return 2

    app = create_app()
    with app.app_context():
        existing_target = User.find_by_email(email)
        if existing_target and existing_target.role != "admin":
            print("The requested email is already used by a non-admin account.", file=sys.stderr)
            return 1

        if existing_target:
            admin = existing_target
        elif args.current_email:
            admin = User.find_by_email(args.current_email.strip().lower())
            if not admin or admin.role != "admin":
                print("The current email does not identify an administrator.", file=sys.stderr)
                return 1
        else:
            admins = User.query.filter_by(role="admin").all()
            if len(admins) > 1:
                print("Specify --current-email to select the administrator to update.", file=sys.stderr)
                return 1
            if admins:
                admin = admins[0]
            else:
                admin = User(
                    name="Transport Department Admin",
                    email=email,
                    role="admin",
                    college="both",
                )
                db.session.add(admin)

        if admin.email != email:
            email_in_use = User.find_by_email(email)
            if email_in_use and email_in_use.id != admin.id:
                print("The requested email is already in use.", file=sys.stderr)
                return 1

        driver_demo = User.find_by_email("driver.k@klnce.edu.in")
        disable_seed_driver = bool(
            driver_demo
            and driver_demo.role == "driver"
            and driver_demo.name == "Driver Manikandan"
            and driver_demo.password_hash == admin.password_hash
        )

        admin.email = email
        admin.is_active = True
        admin.set_password(password)
        if disable_seed_driver:
            driver_demo.is_active = False

        try:
            db.session.commit()
        except Exception:
            db.session.rollback()
            raise

        response = app.test_client().post(
            "/api/auth/login",
            json={"email": email, "password": password},
        )
        if response.status_code != 200:
            print(
                "Credentials were saved, but API login verification failed "
                f"(HTTP {response.status_code}).",
                file=sys.stderr,
            )
            return 1

        profile = response.get_json().get("user", {})
        if profile.get("role") != "admin":
            print("API login succeeded but the account is not an administrator.", file=sys.stderr)
            return 1

    print("Administrator credentials updated; API login verified.")
    if disable_seed_driver:
        print("The shared demo driver account was deactivated.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
