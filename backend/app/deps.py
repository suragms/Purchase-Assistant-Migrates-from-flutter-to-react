"""Request dependencies: auth via JWT user id; tenant data scoped by Membership.business_id."""

import secrets
import uuid
from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.database import get_db
from app.models import Membership, User
from app.services.jwt_tokens import decode_access_token
from app.services.permissions import membership_permissions, require_permission_key

security = HTTPBearer(auto_error=False)


async def require_ai_parse_enabled(
    settings: Annotated[Settings, Depends(get_settings)],
) -> None:
    """Env gate for purchase-bill AI parsing.

    SaaS feature-flag/billing gates were removed for the single-client
    warehouse app; OpenAI Vision scan remains controlled by deployment env.
    """
    if not settings.enable_ai:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="AI parse is disabled")


async def require_realtime_effective(
    settings: Annotated[Settings, Depends(get_settings)],
) -> None:
    if not settings.enable_realtime:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Realtime is disabled")


async def get_current_user(
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(security)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> User:
    if not creds or creds.scheme.lower() != "bearer":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Not authenticated")
    claims = decode_access_token(creds.credentials, settings)
    if not claims:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token")
    result = await db.execute(select(User).where(User.id == claims.user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "User not found")
    expected_tv = int(getattr(user, "token_version", 0) or 0)
    if claims.token_version != expected_tv:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Token revoked")
    if getattr(user, "deleted_at", None) is not None:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Account is inactive")
    if getattr(user, "is_blocked", False):
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Account is blocked")
    if not user.is_active:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Account is inactive")
    return user


async def require_membership(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Membership:
    q = await db.execute(
        select(Membership).where(
            Membership.business_id == business_id,
            Membership.user_id == user.id,
        )
    )
    m = q.scalar_one_or_none()
    if not m:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Not a member of this business")
    return m


async def require_owner_membership(
    membership: Annotated[Membership, Depends(require_membership)],
) -> Membership:
    if membership.role != "owner":
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Owner role required")
    return membership


def require_role(*roles: str):
    """RBAC: membership.role must be one of [roles] (or user is super_admin)."""

    async def _dep(
        membership: Annotated[Membership, Depends(require_membership)],
        user: Annotated[User, Depends(get_current_user)],
    ) -> Membership:
        if user.is_super_admin:
            return membership
        if membership.role not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Access denied. Required roles: {list(roles)}",
            )
        return membership

    return _dep


def require_permission(permission: str):
    """RBAC: membership must have permission key (owner defaults via template)."""

    async def _dep(
        membership: Annotated[Membership, Depends(require_membership)],
        user: Annotated[User, Depends(get_current_user)],
    ) -> Membership:
        if user.is_super_admin:
            return membership
        perms = await membership_permissions(membership)
        require_permission_key(permission, perms)
        return membership

    return _dep


async def get_current_user_role(
    membership: Annotated[Membership, Depends(require_membership)],
) -> str:
    return membership.role


async def require_super_admin(
    user: Annotated[User, Depends(get_current_user)],
) -> User:
    if not user.is_super_admin:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Super admin only")
    return user


@dataclass(frozen=True)
class AdminCaller:
    """Admin panel auth: static `ADMIN_API_TOKEN` Bearer, or JWT for a user with `is_super_admin`."""

    machine: bool
    user: User | None


async def require_admin_caller(
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(security)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> AdminCaller:
    """Authorize admin routes via `Authorization: Bearer <ADMIN_API_TOKEN>` or super-admin JWT."""
    tok = settings.admin_api_token
    if creds and creds.scheme.lower() == "bearer" and tok:
        if len(tok) >= 8 and secrets.compare_digest(creds.credentials, tok):
            return AdminCaller(machine=True, user=None)
    if not creds or creds.scheme.lower() != "bearer":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")
    claims = decode_access_token(creds.credentials, settings)
    if not claims:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    result = await db.execute(select(User).where(User.id == claims.user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="User not found")
    expected_tv = int(getattr(user, "token_version", 0) or 0)
    if claims.token_version != expected_tv:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Token revoked")
    if not user.is_super_admin:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Super admin only")
    return AdminCaller(machine=False, user=user)
