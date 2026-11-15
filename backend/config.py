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
    # Database                                                             #
    # ------------------------------------------------------------------ #
    DB_HOST: str = os.environ.get("DB_HOST", "localhost")
    DB_PORT: int = int(os.environ.get("DB_PORT", 3306))
    DB_USER: str = os.environ.get("DB_USER", "root")
    DB_PASSWORD: str = os.environ.get("DB_PASSWORD", "")
    DB_NAME: str = os.environ.get("DB_NAME", "klnce_transport")

    # SQLAlchemy connection string — uses PyMySQL as the driver.
    # Note: DB_PASSWORD is URL-encoded with quote_plus to safely support special characters like '&'
    SQLALCHEMY_DATABASE_URI: str = (
        f"mysql+pymysql://{os.environ.get('DB_USER', 'root')}:"
        f"{urllib.parse.quote_plus(os.environ.get('DB_PASSWORD', ''))}@"
        f"{os.environ.get('DB_HOST', '127.0.0.1')}:"
        f"{os.environ.get('DB_PORT', 3306)}/"
        f"{os.environ.get('DB_NAME', 'klnce_transport')}"
        "?charset=utf8mb4"
    )
    SQLALCHEMY_TRACK_MODIFICATIONS: bool = False
    SQLALCHEMY_ENGINE_OPTIONS: dict = {
        "pool_recycle": 280,
        "pool_pre_ping": True,
        "pool_size": 5,
        "max_overflow": 10,
    }

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
    # Tighten pool settings for production
    SQLALCHEMY_ENGINE_OPTIONS = {
        "pool_recycle": 280,
        "pool_pre_ping": True,
        "pool_size": 10,
        "max_overflow": 20,
    }


class TestingConfig(BaseConfig):
    TESTING = True
    DEBUG = True
    SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:"
    SQLALCHEMY_ENGINE_OPTIONS = {}


_CONFIG_MAP: dict[str, type] = {
    "development": DevelopmentConfig,
    "production": ProductionConfig,
    "testing": TestingConfig,
}


def get_config() -> type:
    """Return the appropriate config class based on the FLASK_ENV variable."""
    env = os.environ.get("FLASK_ENV", "development").lower()
    return _CONFIG_MAP.get(env, DevelopmentConfig)
