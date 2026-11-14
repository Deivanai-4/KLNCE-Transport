"""
SMS service via MSG91 REST API / GSM SIM module.
Ensures emergency bus schedule changes reach students without active mobile internet.
"""

import os
import logging
import requests
from typing import List

logger = logging.getLogger(__name__)

MSG91_AUTH_KEY = os.environ.get('MSG91_API_KEY', '')
MSG91_SENDER_ID = os.environ.get('MSG91_SENDER_ID', 'KLNCET')
MSG91_FLOW_ID = os.environ.get('MSG91_FLOW_ID', '')


def send_sms(phone_number: str, message: str) -> bool:
    """
    Sends single SMS alert to student's mobile number.
    """
    if not MSG91_AUTH_KEY:
        logger.info("[Mock SMS] To: %s | Message: %s", phone_number, message)
        return True

    clean_phone = phone_number.replace('+', '').replace(' ', '')
    if len(clean_phone) == 10:
        clean_phone = f"91{clean_phone}"

    url = "https://control.msg91.com/api/v5/flow/"
    headers = {
        "authkey": MSG91_AUTH_KEY,
        "content-type": "application/json"
    }
    payload = {
        "template_id": MSG91_FLOW_ID,
        "short_url": "0",
        "recipients": [
            {
                "mobiles": clean_phone,
                "message": message,
                "sender": MSG91_SENDER_ID
            }
        ]
    }

    try:
        response = requests.post(url, json=payload, headers=headers, timeout=10)
        return response.status_code in [200, 201, 202]
    except Exception as e:
        logger.error("Failed to send SMS to %s: %s", phone_number, e)
        return False


def send_bulk_sms(phone_numbers: List[str], message: str) -> int:
    """Sends SMS notification to a list of phone numbers."""
    success_count = 0
    for phone in phone_numbers:
        if send_sms(phone, message):
            success_count += 1
    return success_count

