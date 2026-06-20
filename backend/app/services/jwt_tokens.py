from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from uuid import UUID

from jose import JWTError, jwt

from app.config import Settings


@dataclass(frozen=True)
class AccessTokenClaims:
    user_id: UUID
    token_version: int


def create_access_token(
    user_id: UUID,
    settings: Settings,
    *,
    token_version: int = 0,
) -> str:
    exp = datetime.now(timezone.utc) + timedelta(minutes=settings.jwt_access_ttl_minutes)
    payload = {
        "sub": str(user_id),
        "typ": "access",
        "exp": exp,
        "tv": int(token_version),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def create_refresh_token(user_id: UUID, settings: Settings) -> str:
    exp = datetime.now(timezone.utc) + timedelta(days=settings.jwt_refresh_ttl_days)
    payload = {"sub": str(user_id), "typ": "refresh", "exp": exp}
    return jwt.encode(payload, settings.jwt_refresh_secret, algorithm="HS256")


def decode_access_token(token: str, settings: Settings) -> AccessTokenClaims | None:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
        if payload.get("typ") != "access":
            return None
        tv = payload.get("tv", 0)
        return AccessTokenClaims(
            user_id=UUID(payload["sub"]),
            token_version=int(tv) if tv is not None else 0,
        )
    except (JWTError, KeyError, ValueError, TypeError):
        return None


def decode_refresh_token(token: str, settings: Settings) -> UUID | None:
    try:
        payload = jwt.decode(token, settings.jwt_refresh_secret, algorithms=["HS256"])
        if payload.get("typ") != "refresh":
            return None
        return UUID(payload["sub"])
    except (JWTError, KeyError, ValueError):
        return None
