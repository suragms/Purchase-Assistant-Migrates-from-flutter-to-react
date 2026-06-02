"""OTP storage: Redis when REDIS_URL is reachable, else in-process (single-instance dev)."""

from __future__ import annotations

import logging
import random
import time
from dataclasses import dataclass
from typing import TYPE_CHECKING, Protocol

from app.config import Settings
from app.middleware.rate_limit import SlidingWindowLimiter

if TYPE_CHECKING:
    pass

logger = logging.getLogger(__name__)
_PHONE_OTP_REQUEST_LIMITER = SlidingWindowLimiter(max_requests=3, window_seconds=600.0)


@dataclass
class OtpAttemptState:
    failed_attempts: int = 0
    locked_until_epoch_s: float = 0.0


_OTP_ATTEMPT_STATE: dict[str, OtpAttemptState] = {}


class OtpStore(Protocol):
    async def set_code(self, phone: str, code: str, ttl_seconds: int = 600) -> None: ...
    async def get_code(self, phone: str) -> str | None: ...
    async def delete(self, phone: str) -> None: ...


class MemoryOtpStore:
    def __init__(self) -> None:
        self._data: dict[str, tuple[str, float]] = {}

    async def set_code(self, phone: str, code: str, ttl_seconds: int = 600) -> None:
        self._data[phone] = (code, time.time() + ttl_seconds)

    async def get_code(self, phone: str) -> str | None:
        row = self._data.get(phone)
        if not row:
            return None
        code, exp = row
        if time.time() > exp:
            del self._data[phone]
            return None
        return code

    async def delete(self, phone: str) -> None:
        self._data.pop(phone, None)


class RedisOtpStore:
    """OTP codes in Redis with TTL (multi-instance safe)."""

    def __init__(self, redis_url: str) -> None:
        import redis.asyncio as redis

        self._redis = redis.from_url(redis_url, decode_responses=True)
        self._prefix = "hexa:otp:"

    async def set_code(self, phone: str, code: str, ttl_seconds: int = 600) -> None:
        await self._redis.setex(f"{self._prefix}{phone}", ttl_seconds, code)

    async def get_code(self, phone: str) -> str | None:
        return await self._redis.get(f"{self._prefix}{phone}")

    async def delete(self, phone: str) -> None:
        await self._redis.delete(f"{self._prefix}{phone}")


memory_otp_store = MemoryOtpStore()
_redis_store: RedisOtpStore | None = None
_redis_otp_unavailable: bool = False


def get_otp_store(settings: Settings) -> OtpStore:
    """Return Redis-backed store when REDIS_URL is set and reachable; else memory."""
    global _redis_store, _redis_otp_unavailable
    if not settings.redis_url or _redis_otp_unavailable:
        return memory_otp_store
    if _redis_store is None:
        try:
            import redis as sync_redis

            sync_redis.from_url(settings.redis_url, decode_responses=True).ping()
        except Exception as e:  # noqa: BLE001
            logger.warning("OTP store: Redis unreachable (%s), using in-memory OTP store", e)
            _redis_otp_unavailable = True
            return memory_otp_store
        _redis_store = RedisOtpStore(settings.redis_url)
        logger.info("OTP store: Redis")
    return _redis_store


def generate_otp() -> str:
    return f"{random.randint(0, 999999):06d}"


async def send_otp(
    settings: Settings,
    store: OtpStore,
    phone: str,
    *,
    requester_ip: str | None = None,
) -> str:
    if settings.dev_otp_code:
        code = settings.dev_otp_code
    else:
        code = generate_otp()
    await store.set_code(phone, code)
    logger.info(
        "OTP issued | phone=%s ip=%s",
        phone,
        (requester_ip or "-"),
    )
    # Production: plug SMS provider (OTP_PROVIDER / OTP_API_KEY) here
    return code


def otp_request_allowed(settings: Settings, *, phone: str) -> bool:
    limiter = _PHONE_OTP_REQUEST_LIMITER
    limiter.max_requests = max(1, int(settings.otp_requests_per_10_minutes_per_phone))
    return limiter.allow(f"otp:phone:{phone}")


def otp_verify_allowed(settings: Settings, *, phone: str) -> bool:
    state = _OTP_ATTEMPT_STATE.get(phone)
    if not state:
        return True
    return time.time() >= state.locked_until_epoch_s


def otp_record_verify_failure(settings: Settings, *, phone: str) -> None:
    state = _OTP_ATTEMPT_STATE.setdefault(phone, OtpAttemptState())
    state.failed_attempts += 1
    if state.failed_attempts >= max(1, int(settings.otp_failed_attempts_lockout_threshold)):
        mins = max(1, int(settings.otp_failed_attempts_lockout_minutes))
        state.locked_until_epoch_s = time.time() + (mins * 60)
        logger.warning("OTP verify lockout applied | phone=%s minutes=%s", phone, mins)
    else:
        logger.info("OTP verify failed | phone=%s attempts=%s", phone, state.failed_attempts)


def otp_record_verify_success(*, phone: str) -> None:
    _OTP_ATTEMPT_STATE.pop(phone, None)
