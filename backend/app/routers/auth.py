import logging
import re
import uuid
from datetime import datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import delete, or_, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.database import get_db
from app.models import Business, Membership, User
from app.models.user_session import UserSession
from app.services.staff_audit import log_staff_login_if_applicable
from app.models.password_reset import PasswordResetToken, hash_reset_token, new_reset_token_raw
from app.schemas.auth import (
    ForgotPasswordRequest,
    GoogleAuthRequest,
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    ResetPasswordRequest,
    TokenPair,
)
from app.services.auth_login import resolve_user_by_login_identifier
from app.services.google_oauth import verify_google_id_token_async
from app.services.jwt_tokens import create_access_token, create_refresh_token, decode_refresh_token
from app.services.passwords import hash_password, verify_password

router = APIRouter(prefix="/v1/auth", tags=["auth"])
logger = logging.getLogger(__name__)


def _username_from_google(email: str, sub: str) -> str:
    local = email.split("@", 1)[0].lower()
    s = re.sub(r"[^a-z0-9_]", "_", local)
    s = re.sub(r"_+", "_", s).strip("_")
    tail = re.sub(r"[^a-z0-9_]", "", sub)[-8:]
    combined = f"{s}_{tail}" if s else f"g_{tail}"
    return combined[:64]


async def _allocate_username(db: AsyncSession, email: str, sub: str) -> str:
    base = _username_from_google(email, sub)
    check = await db.execute(select(User.id).where(User.username == base))
    if not check.first():
        return base
    suffix = uuid.uuid4().hex[:8]
    return f"{base[: 64 - len(suffix) - 1]}_{suffix}"[:64]


@router.post("/register", response_model=TokenPair)
async def register(
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    body: RegisterRequest,
):
    if not settings.allow_public_registration:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "Self-registration is disabled. Ask your workspace owner to create "
                "your account from Settings → Users."
            ),
        )

    ex = await db.execute(
        select(User.id).where(or_(User.email == body.email, User.username == body.username))
    )
    if ex.first():
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail="An account with this email or username already exists",
        )

    pwd_hash = hash_password(body.password)
    user = User(
        email=body.email,
        username=body.username,
        password_hash=pwd_hash,
        phone=None,
        name=body.name,
    )
    if settings.superadmin_bootstrap_email and body.email == settings.superadmin_bootstrap_email.strip().lower():
        user.is_super_admin = True

    db.add(user)
    await db.flush()

    biz = Business(name="Harisree workspace")
    db.add(biz)
    await db.flush()
    db.add(Membership(user_id=user.id, business_id=biz.id, role="owner"))

    await db.commit()
    await db.refresh(user)

    access = create_access_token(user.id, settings)
    refresh = create_refresh_token(user.id, settings)
    return TokenPair(
        access_token=access,
        refresh_token=refresh,
        expires_in=settings.jwt_access_ttl_minutes * 60,
    )


@router.post("/forgot-password")
async def forgot_password(
    body: ForgotPasswordRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    """Store a one-time token (email delivery TBD). Response text is user-safe; in development a token is returned for testing."""
    r = await db.execute(select(User).where(User.email == body.email))
    user = r.scalar_one_or_none()
    same: dict = {
        "ok": True,
        "message": "If an account exists for that email, you will receive reset instructions.",
    }
    if not user or not user.password_hash:
        return same
    await db.execute(delete(PasswordResetToken).where(PasswordResetToken.user_id == user.id))
    raw = new_reset_token_raw()
    th = hash_reset_token(raw)
    exp = datetime.now(timezone.utc) + timedelta(hours=1)
    db.add(
        PasswordResetToken(
            user_id=user.id,
            token_hash=th,
            expires_at=exp,
        )
    )
    await db.commit()
    logger.info("Password reset token created for user_id=%s", user.id)
    if (settings.app_env or "").lower() in ("development", "dev", "test"):
        same["dev_reset_token"] = raw
    return same


@router.post("/reset-password")
async def reset_password_with_token(
    body: ResetPasswordRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    th = hash_reset_token(body.token.strip())
    now = datetime.now(timezone.utc)
    q = await db.execute(
        select(PasswordResetToken).where(
            PasswordResetToken.token_hash == th,
            PasswordResetToken.used_at.is_(None),
            PasswordResetToken.expires_at > now,
        )
    )
    pr = q.scalar_one_or_none()
    if not pr:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired reset link. Request a new one.",
        )
    ur = await db.execute(select(User).where(User.id == pr.user_id))
    user = ur.scalar_one_or_none()
    if not user or not user.password_hash:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="This account cannot set a password here.",
        )
    user.password_hash = hash_password(body.new_password)
    pr.used_at = now
    await db.commit()
    return {
        "ok": True,
        "message": "Password updated. You can sign in now.",
    }


@router.post("/login", response_model=TokenPair)
async def login(
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    body: LoginRequest,
):
    try:
        try:
            user = await resolve_user_by_login_identifier(db, body.identifier)
        except SQLAlchemyError:
            logger.exception("auth.login database error")
            raise HTTPException(
                status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Sign-in is temporarily unavailable. Try again shortly.",
            ) from None

        if (
            not user
            or user.password_hash is None
            or not verify_password(body.password, user.password_hash)
        ):
            raise HTTPException(
                status.HTTP_401_UNAUTHORIZED,
                detail="Invalid username, phone, or password",
            )
        if not user.is_active:
            raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Account is inactive")

        now = datetime.now(timezone.utc)
        user.last_login_at = now
        user.last_active_at = now
        mem_q = await db.execute(select(Membership).where(Membership.user_id == user.id).limit(1))
        mem = mem_q.scalar_one_or_none()
        db.add(
            UserSession(
                user_id=user.id,
                business_id=mem.business_id if mem else None,
                login_at=now,
                is_active=True,
            )
        )
        await log_staff_login_if_applicable(db, user, mem)
        await db.flush()

        try:
            access = create_access_token(user.id, settings)
            refresh = create_refresh_token(user.id, settings)
        except Exception:
            logger.exception("auth.login token issue")
            raise HTTPException(
                status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Sign-in is temporarily unavailable. Try again shortly.",
            ) from None

        return TokenPair(
            access_token=access,
            refresh_token=refresh,
            expires_in=settings.jwt_access_ttl_minutes * 60,
        )
    except HTTPException:
        raise
    except Exception:
        logger.exception("auth.login unexpected failure")
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Sign-in is temporarily unavailable. Try again shortly.",
        ) from None


@router.post("/google", response_model=TokenPair)
async def auth_google(
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    body: GoogleAuthRequest,
):
    audiences = settings.google_oauth_client_id_list()
    if not audiences:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Google Sign-In is not configured (set GOOGLE_OAUTH_CLIENT_IDS)",
        )
    try:
        claims = await verify_google_id_token_async(body.id_token, audiences)
    except ValueError as e:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail=str(e)) from e

    sub = claims.get("sub")
    email = (claims.get("email") or "").strip().lower()
    if not sub or not email:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Google account has no email")
    if claims.get("email_verified") is False:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Google email is not verified")

    r_sub = await db.execute(select(User).where(User.google_sub == sub))
    user = r_sub.scalar_one_or_none()
    if user:
        gn = claims.get("name")
        if (
            gn
            and isinstance(gn, str)
            and gn.strip()
            and not (user.name and user.name.strip())
        ):
            user.name = gn.strip()
            await db.commit()
            await db.refresh(user)
    if not user:
        r_email = await db.execute(select(User).where(User.email == email))
        user = r_email.scalar_one_or_none()
        if user:
            if user.google_sub is None:
                user.google_sub = sub
            elif user.google_sub != sub:
                raise HTTPException(
                    status.HTTP_409_CONFLICT,
                    detail="This email is already linked to a different sign-in method",
                )
            gn2 = claims.get("name")
            if (
                gn2
                and isinstance(gn2, str)
                and gn2.strip()
                and not (user.name and user.name.strip())
            ):
                user.name = gn2.strip()
            await db.commit()
            await db.refresh(user)
        else:
            uname = await _allocate_username(db, email, sub)
            raw_name = claims.get("name")
            disp = raw_name.strip()[:255] if isinstance(raw_name, str) and raw_name.strip() else None
            user = User(
                email=email,
                username=uname,
                password_hash=None,
                phone=None,
                name=disp,
                google_sub=sub,
            )
            if settings.superadmin_bootstrap_email and email == settings.superadmin_bootstrap_email.strip().lower():
                user.is_super_admin = True
            db.add(user)
            await db.flush()
            biz = Business(name="Harisree workspace")
            db.add(biz)
            await db.flush()
            db.add(Membership(user_id=user.id, business_id=biz.id, role="owner"))
            await db.commit()
            await db.refresh(user)

    access = create_access_token(user.id, settings)
    refresh = create_refresh_token(user.id, settings)
    return TokenPair(
        access_token=access,
        refresh_token=refresh,
        expires_in=settings.jwt_access_ttl_minutes * 60,
    )


@router.post("/refresh", response_model=TokenPair)
async def refresh_token(
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    body: RefreshRequest,
):
    uid = decode_refresh_token(body.refresh_token, settings)
    if not uid:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")
    result = await db.execute(select(User).where(User.id == uid))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="User not found")
    access = create_access_token(user.id, settings)
    refresh = create_refresh_token(user.id, settings)
    return TokenPair(
        access_token=access,
        refresh_token=refresh,
        expires_in=settings.jwt_access_ttl_minutes * 60,
    )
