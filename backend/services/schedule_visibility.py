"""Indian Standard Time visibility windows for published bus schedules."""

from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

IST = ZoneInfo('Asia/Kolkata')


def ist_now() -> datetime:
    return datetime.now(IST)


def _as_ist(value: datetime | None = None) -> datetime:
    if value is None:
        return ist_now()
    if value.tzinfo is None:
        return value.replace(tzinfo=IST)
    return value.astimezone(IST)


def active_trip_at(value: datetime | None = None) -> str | None:
    local_time = _as_ist(value).time()
    if local_time < time(12, 0):
        return 'incoming'
    if local_time < time(21, 0):
        return 'outgoing'
    return None


def is_trip_visible(trip_direction: str, value: datetime | None = None) -> bool:
    return active_trip_at(value) == trip_direction


def next_transition_at(value: datetime | None = None) -> datetime:
    now = _as_ist(value)
    if now.time() < time(12, 0):
        transition = time(12, 0)
    elif now.time() < time(21, 0):
        transition = time(21, 0)
    else:
        return datetime.combine(
            now.date() + timedelta(days=1),
            time.min,
            tzinfo=IST,
        )
    return datetime.combine(now.date(), transition, tzinfo=IST)


def visibility_metadata(value: datetime | None = None) -> dict:
    now = _as_ist(value)
    return {
        'active_trip': active_trip_at(now),
        'server_time_ist': now.isoformat(),
        'next_transition_ist': next_transition_at(now).isoformat(),
    }
