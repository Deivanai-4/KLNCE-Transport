"""
Storage service: saves uploaded schedule documents permanently and generates access URLs.
Supports local persistent storage and Firebase Cloud Storage.
"""

import os
import uuid
import logging
from werkzeug.utils import secure_filename

logger = logging.getLogger(__name__)

UPLOAD_FOLDER = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'uploads')
os.makedirs(UPLOAD_FOLDER, exist_ok=True)


def save_uploaded_file(file_obj, original_filename: str) -> tuple[str, str]:
    """
    Saves the uploaded schedule file.
    Returns:
        (saved_absolute_path, public_or_relative_url)
    """
    clean_name = secure_filename(original_filename)
    extension = os.path.splitext(clean_name)[1].lower()
    unique_name = f"schedule_{uuid.uuid4().hex[:12]}{extension}"

    destination_path = os.path.join(UPLOAD_FOLDER, unique_name)
    file_obj.save(destination_path)

    # Relative accessible URL for the web server
    relative_url = f"/api/schedules/files/{unique_name}"
    return destination_path, relative_url


def save_uploaded_bytes(file_bytes: bytes, original_filename: str) -> tuple[str, str]:
    """
    Saves raw file bytes (e.g. from base64 uploads).
    Returns:
        (saved_absolute_path, public_or_relative_url)
    """
    clean_name = secure_filename(original_filename) or 'schedule.png'
    extension = os.path.splitext(clean_name)[1].lower() or '.png'
    unique_name = f"schedule_{uuid.uuid4().hex[:12]}{extension}"

    destination_path = os.path.join(UPLOAD_FOLDER, unique_name)
    with open(destination_path, 'wb') as f:
        f.write(file_bytes)

    relative_url = f"/api/schedules/files/{unique_name}"
    return destination_path, relative_url


def get_file_path(filename: str) -> str:
    """Returns absolute file path within upload directory."""
    return os.path.join(UPLOAD_FOLDER, secure_filename(filename))

