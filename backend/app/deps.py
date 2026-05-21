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
from app.services.billing_entitlements import assert_ai_entitled
from app.services.feature_flags import is_ai_parsing_enabled
from app.services.jwt_tokens import decode_access_token
from app.services.permissions import membership_permissions, require_permission_key

security = HTTPBearer(auto_error=False)


async def require_ai_parse_enabled(
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> None:
    """Env + DB feature flag for `/parse` and similar AI-assisted entry flows."""
    if not settings.enable_ai:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="AI parse is disabled")
    if not await is_ai_parsing_enabled(db, settings):
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="AI parse is disabled")


async def require_realtime_effective(
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> None:
    from app.services.feature_flags import is_realtime_enabled

    if not await is_realtime_enabled(db, settings):
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Realtime is disabled")


async def get_current_user(
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(security)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> User:
    if not creds or creds.scheme.lower() != "bearer":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Not authenticated")
    uid = decode_access_token(creds.credentials, settings)
    if not uid:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token")
    result = await db.execute(select(User).where(User.id == uid))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "User not found")
    return user


async def charge_ai_turn_for_business(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> User:
    """AI routes: membership + feature flags + billing AI add-on + token budget."""
    q = await db.execute(
        select(Membership).where(
            Membership.business_id == business_id,
            Membership.user_id == user.id,
        )
    )
    if q.scalar_one_or_none() is None:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Not a member of this business")
    if not settings.enable_ai:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="AI is disabled for this deployment")
    if not await is_ai_parsing_enabled(db, settings):
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="AI parsing is disabled")
    await assert_ai_entitled(db, business_id, settings)
    budget = user.ai_monthly_token_budget
    used = user.ai_tokens_used_month or 0
    if budget is not None and budget > 0 and used >= budget:
        raise HTTPException(
            status.HTTP_402_PAYMENT_REQUIRED,
            detail="Monthly AI limit reached — use manual entry or ask an owner to raise the cap.",
        )
    user.ai_tokens_used_month = used + 48
    await db.commit()
    await db.refresh(user)
    return user


async def charge_ai_stub_turn(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> User:
    """Gate AI routes: feature flag + monthly token budget (stub accounting)."""
    if not settings.enable_ai:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="AI is disabled for this deployment")
    if not await is_ai_parsing_enabled(db, settings):
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="AI parsing is disabled")
    budget = user.ai_monthly_token_budget
    used = user.ai_tokens_used_month or 0
    if budget is not None and budget > 0 and used >= budget:
        raise HTTPException(
            status.HTTP_402_PAYMENT_REQUIRED,
            detail="Monthly AI limit reached — use manual entry or ask an owner to raise the cap.",
        )
    user.ai_tokens_used_month = used + 48
    await db.commit()
    await db.refresh(user)
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
    uid = decode_access_token(creds.credentials, settings)
    if not uid:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    result = await db.execute(select(User).where(User.id == uid))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="User not found")
    if not user.is_super_admin:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Super admin only")
    return AdminCaller(machine=False, user=user)
