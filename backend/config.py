"""
config.py — Application configuration for KLNCE Smart Transport System.

Reads all settings from environment variables (via python-dotenv).
"""

import os
import urllib.parse
from dotenv import load_dotenv

# Load .env file explicitly from the backend directory
_backend_dir = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(_backend_dir, ".env"))


def _csv_to_list(env_var: str, default: str = "") -> list[str]:
    """Split a comma-separated env var into a stripped list."""
    raw = os.environ.get(env_var, default)
    return [item.strip() for item in raw.split(",") if item.strip()]


class BaseConfig:
    # ------------------------------------------------------------------ #
    # Flask Core                                                           #
    # ------------------------------------------------------------------ #
    SECRET_KEY: str = os.environ.get("SECRET_KEY", "dev-secret-key-change-me")
    DEBUG: bool = False
    TESTING: bool = False

    # ------------------------------------------------------------------ #
    # MongoDB Database                                                     #
    # ------------------------------------------------------------------ #
    MONGODB_URI: str = os.environ.get("MONGODB_URI", "")
    MONGODB_DATABASE: str = os.environ.get("MONGODB_DATABASE", "klnce_transport")

    # ------------------------------------------------------------------ #
    # File Upload                                                          #
    # ------------------------------------------------------------------ #
    UPLOAD_FOLDER: str = os.environ.get("UPLOAD_FOLDER", "uploads")
    MAX_CONTENT_LENGTH: int = int(os.environ.get("MAX_CONTENT_LENGTH", 10 * 1024 * 1024))
    ALLOWED_EXTENSIONS: set[str] = {"jpg", "jpeg", "png", "pdf"}

    # ------------------------------------------------------------------ #
    # CORS                                                                 #
    # ------------------------------------------------------------------ #
    CORS_ORIGINS: list[str] = _csv_to_list(
        "CORS_ORIGINS",
        "http://localhost:3000,http://localhost:8080",
    )

    # ------------------------------------------------------------------ #
    # Firebase                                                             #
    # ------------------------------------------------------------------ #
    FIREBASE_CREDENTIALS: str = os.environ.get("FIREBASE_CREDENTIALS", "")
    FIREBASE_STORAGE_BUCKET: str = os.environ.get("FIREBASE_STORAGE_BUCKET", "")

    # ------------------------------------------------------------------ #
    # Google Maps                                                          #
    # ------------------------------------------------------------------ #
    GOOGLE_MAPS_API_KEY: str = os.environ.get("GOOGLE_MAPS_API_KEY", "")

    # ------------------------------------------------------------------ #
    # MSG91 SMS                                                            #
    # ------------------------------------------------------------------ #
    MSG91_API_KEY: str = os.environ.get("MSG91_API_KEY", "")
    MSG91_SENDER_ID: str = os.environ.get("MSG91_SENDER_ID", "KLNCE")
    MSG91_TEMPLATE_ID: str = os.environ.get("MSG91_TEMPLATE_ID", "")


class DevelopmentConfig(BaseConfig):
    DEBUG = True


class ProductionConfig(BaseConfig):
    DEBUG = False


class TestingConfig(BaseConfig):
    TESTING = True
    DEBUG = True
    # Isolated test MongoDB database — never touches production
    MONGODB_DATABASE: str = "klnce_transport_test"


_CONFIG_MAP: dict[str, type] = {
    "development": DevelopmentConfig,
    "production": ProductionConfig,
    "testing": TestingConfig,
}


def get_config() -> type:
    """Return the appropriate config class based on the FLASK_ENV variable."""
    env = os.environ.get("FLASK_ENV", "development").lower()
    return _CONFIG_MAP.get(env, DevelopmentConfig)
