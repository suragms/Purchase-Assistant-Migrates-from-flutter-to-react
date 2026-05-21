import re
import uuid
from datetime import datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import and_, desc, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user, require_membership, require_role
from app.models import Business, CatalogItem, Membership, TradePurchase, User
from app.models.stock_adjustment import StockAdjustmentLog
from app.models.user_session import StaffActivityLog, UserSession
from app.schemas.users import (
    ActivityLogIn,
    ActivityLogOut,
    LedgerEntryOut,
    PermissionsOut,
    PermissionsPatchIn,
    ResetPasswordOut,
    StockAdjustmentOut,
    TodayStatsOut,
    UserCreateIn,
    UserCreateOut,
    UserListOut,
    UserPatchIn,
    UserProfileOut,
    UserPurchaseBrief,
)
from app.services.passwords import hash_password
from app.services.permissions import (
    PERMISSION_KEYS,
    effective_permissions,
    membership_permissions,
)
from app.services.readable_password import generate_readable_password
from app.services.staff_audit import log_password_reset
from app.services.user_username import allocate_username

router = APIRouter(prefix="/v1/businesses/{business_id}/users", tags=["users"])


def _phone_digits(phone: str) -> str:
    return re.sub(r"\D", "", phone)


async def _activity_count_7d(db: AsyncSession, business_id: uuid.UUID, user_id: uuid.UUID) -> int:
    start = datetime.now(timezone.utc) - timedelta(days=7)
    r = await db.execute(
        select(func.count())
        .select_from(StaffActivityLog)
        .where(
            StaffActivityLog.business_id == business_id,
            StaffActivityLog.user_id == user_id,
            StaffActivityLog.created_at >= start,
        )
    )
    return int(r.scalar_one())


async def _today_stats(db: AsyncSession, business_id: uuid.UUID, user_id: uuid.UUID) -> TodayStatsOut:
    start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    base = and_(
        StaffActivityLog.business_id == business_id,
        StaffActivityLog.user_id == user_id,
        StaffActivityLog.created_at >= start,
    )

    async def count(action: str) -> int:
        r = await db.execute(
            select(func.count())
            .select_from(StaffActivityLog)
            .where(base, StaffActivityLog.action_type == action)
        )
        return int(r.scalar_one())

    return TodayStatsOut(
        scans=await count("SCAN"),
        stock_updates=await count("STOCK_UPDATE"),
        items_created=await count("ITEM_CREATE"),
    )


async def _warehouse_name(db: AsyncSession, business_id: uuid.UUID) -> str | None:
    r = await db.execute(select(Business.name).where(Business.id == business_id))
    return r.scalar_one_or_none()


async def _user_row(
    db: AsyncSession,
    business_id: uuid.UUID,
    user: User,
    membership: Membership,
    *,
    profile: bool = False,
) -> UserListOut | UserProfileOut:
    stats = await _today_stats(db, business_id, user.id)
    act7 = await _activity_count_7d(db, business_id, user.id)
    wh = await _warehouse_name(db, business_id)
    base = UserListOut(
        id=user.id,
        name=user.name,
        phone=user.phone,
        email=user.email,
        username=user.username,
        role=membership.role,
        is_active=user.is_active,
        last_login_at=user.last_login_at,
        last_active_at=user.last_active_at,
        today_stats=stats,
        warehouse_name=wh,
        activity_count_7d=act7,
        notes=user.notes,
        created_at=user.created_at,
    )
    if not profile:
        return base
    start7 = datetime.now(timezone.utc) - timedelta(days=7)
    pur_r = await db.execute(
        select(func.count())
        .select_from(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.user_id == user.id,
            TradePurchase.created_at >= start7,
        )
    )
    stock_r = await db.execute(
        select(func.count())
        .select_from(StockAdjustmentLog)
        .where(
            StockAdjustmentLog.business_id == business_id,
            StockAdjustmentLog.updated_by == user.id,
            StockAdjustmentLog.updated_at >= start7,
        )
    )
    return UserProfileOut(
        **base.model_dump(),
        login_email=user.email,
        purchases_7d=int(pur_r.scalar_one()),
        stock_updates_7d=int(stock_r.scalar_one()),
    )


def _active_user_filter():
    return User.deleted_at.is_(None)


@router.post("", response_model=UserCreateOut, status_code=status.HTTP_201_CREATED)
async def create_user(
    business_id: uuid.UUID,
    body: UserCreateIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    actor: Annotated[Membership, Depends(require_role("owner", "super_admin"))],
    current_user: Annotated[User, Depends(get_current_user)],
):
    del actor
    digits = _phone_digits(body.phone)
    if len(digits) < 6:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Invalid phone")
    email = f"{digits}@staff.harisree.local"
    try:
        username = await allocate_username(
            db,
            requested=body.username,
            phone_digits=digits,
            full_name=body.full_name,
        )
    except ValueError:
        raise HTTPException(status.HTTP_409_CONFLICT, detail="Username already taken") from None

    ex = await db.execute(
        select(User.id).where(
            or_(User.email == email, User.username == username),
            _active_user_filter(),
        )
    )
    if ex.first():
        raise HTTPException(status.HTTP_409_CONFLICT, detail="User with this phone already exists")

    plain = body.password.strip() if body.password and body.password.strip() else generate_readable_password()
    user = User(
        email=email,
        username=username,
        password_hash=hash_password(plain),
        phone=body.phone.strip(),
        name=body.full_name.strip(),
        is_active=body.is_active,
        notes=body.notes.strip() if body.notes else None,
        created_by=current_user.id,
    )
    db.add(user)
    await db.flush()
    mem = Membership(
        user_id=user.id,
        business_id=business_id,
        role=body.role,
        permissions_json=effective_permissions(body.role, None),
    )
    db.add(mem)
    await db.commit()
    await db.refresh(user)
    row = await _user_row(db, business_id, user, mem)
    return UserCreateOut(
        user=row,
        generated_password=plain if not body.password else None,
        login_username=username,
        login_email=email,
    )


@router.get("", response_model=list[UserListOut])
async def list_users(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_role("owner", "manager", "super_admin"))],
    include_inactive: bool = Query(False),
):
    clauses = [Membership.business_id == business_id, _active_user_filter()]
    if not include_inactive:
        clauses.append(User.is_active.is_(True))
    r = await db.execute(
        select(User, Membership)
        .join(Membership, Membership.user_id == User.id)
        .where(*clauses)
        .order_by(User.name)
    )
    out: list[UserListOut] = []
    for user, mem in r.all():
        out.append(await _user_row(db, business_id, user, mem))
    return out


@router.get("/active-sessions", response_model=list[UserListOut])
async def active_sessions(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_role("owner", "manager", "super_admin"))],
):
    cutoff = datetime.now(timezone.utc) - timedelta(minutes=5)
    r = await db.execute(
        select(User, Membership)
        .join(Membership, Membership.user_id == User.id)
        .where(
            Membership.business_id == business_id,
            User.last_active_at.isnot(None),
            User.last_active_at >= cutoff,
            User.is_active.is_(True),
            _active_user_filter(),
        )
    )
    out: list[UserListOut] = []
    for user, mem in r.all():
        out.append(await _user_row(db, business_id, user, mem))
    return out


async def _load_user_membership(
    db: AsyncSession, business_id: uuid.UUID, user_id: uuid.UUID
) -> tuple[User, Membership] | None:
    r = await db.execute(
        select(User, Membership)
        .join(Membership, Membership.user_id == User.id)
        .where(
            Membership.business_id == business_id,
            User.id == user_id,
            _active_user_filter(),
        )
    )
    row = r.one_or_none()
    return row if row else None


@router.get("/{user_id}", response_model=UserProfileOut)
async def get_user(
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_role("owner", "manager", "super_admin"))],
):
    row = await _load_user_membership(db, business_id, user_id)
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="User not found")
    user, mem = row
    return await _user_row(db, business_id, user, mem, profile=True)


@router.patch("/{user_id}", response_model=UserListOut)
async def patch_user(
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    body: UserPatchIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_role("owner", "super_admin"))],
):
    row = await _load_user_membership(db, business_id, user_id)
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="User not found")
    user, mem = row
    if body.full_name is not None:
        user.name = body.full_name.strip()
    if body.phone is not None:
        user.phone = body.phone.strip()
    if body.role is not None:
        mem.role = body.role
        mem.permissions_json = effective_permissions(body.role, mem.permissions_json)
    if body.is_active is not None:
        user.is_active = body.is_active
        if body.is_active:
            user.deleted_at = None
        else:
            user.deleted_at = datetime.now(timezone.utc)
    if body.notes is not None:
        user.notes = body.notes.strip() or None
    await db.commit()
    await db.refresh(user)
    return await _user_row(db, business_id, user, mem)


@router.post("/{user_id}/reset-password", response_model=ResetPasswordOut)
async def reset_password(
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_role("owner", "super_admin"))],
    current_user: Annotated[User, Depends(get_current_user)],
):
    row = await _load_user_membership(db, business_id, user_id)
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="User not found")
    user, _mem = row
    plain = generate_readable_password()
    user.password_hash = hash_password(plain)
    await log_password_reset(
        db, business_id=business_id, actor=current_user, target=user
    )
    await db.commit()
    return ResetPasswordOut(new_password=plain, login_username=user.username)


@router.get("/{user_id}/credentials", response_model=dict)
async def user_credentials(
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_role("owner", "super_admin"))],
):
    row = await _load_user_membership(db, business_id, user_id)
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="User not found")
    user, _mem = row
    return {
        "username": user.username,
        "login_email": user.email,
        "phone": user.phone,
        "note": "Passwords cannot be retrieved. Use reset-password to issue a new one.",
    }


@router.get("/{user_id}/stock-adjustments", response_model=list[StockAdjustmentOut])
async def user_stock_adjustments(
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_role("owner", "manager", "super_admin"))],
    limit: int = Query(50, ge=1, le=200),
):
    r = await db.execute(
        select(StockAdjustmentLog, CatalogItem.name)
        .outerjoin(CatalogItem, CatalogItem.id == StockAdjustmentLog.item_id)
        .where(
            StockAdjustmentLog.business_id == business_id,
            StockAdjustmentLog.updated_by == user_id,
        )
        .order_by(desc(StockAdjustmentLog.updated_at))
        .limit(limit)
    )
    out: list[StockAdjustmentOut] = []
    for log, item_name in r.all():
        out.append(
            StockAdjustmentOut(
                id=log.id,
                item_id=log.item_id,
                item_name=item_name,
                old_qty=float(log.old_qty),
                new_qty=float(log.new_qty),
                adjustment_type=log.adjustment_type,
                reason=log.reason,
                updated_at=log.updated_at,
            )
        )
    return out


@router.get("/{user_id}/purchases", response_model=list[UserPurchaseBrief])
async def user_purchases(
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_role("owner", "manager", "super_admin"))],
    limit: int = Query(50, ge=1, le=100),
):
    r = await db.execute(
        select(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.user_id == user_id,
        )
        .order_by(desc(TradePurchase.created_at))
        .limit(limit)
    )
    out: list[UserPurchaseBrief] = []
    for p in r.scalars().all():
        total = getattr(p, "grand_total", None) or getattr(p, "total_amount", None)
        out.append(
            UserPurchaseBrief(
                id=p.id,
                human_id=getattr(p, "human_id", None),
                purchase_date=getattr(p, "purchase_date", None) or p.created_at,
                status=getattr(p, "status", None),
                total_amount=float(total) if total is not None else None,
            )
        )
    return out


@router.get("/{user_id}/ledger", response_model=list[LedgerEntryOut])
async def user_ledger(
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_role("owner", "manager", "super_admin"))],
    limit: int = Query(80, ge=1, le=200),
):
    entries: list[LedgerEntryOut] = []
    act = await db.execute(
        select(StaffActivityLog)
        .where(
            StaffActivityLog.business_id == business_id,
            StaffActivityLog.user_id == user_id,
        )
        .order_by(desc(StaffActivityLog.created_at))
        .limit(limit)
    )
    for row in act.scalars().all():
        entries.append(
            LedgerEntryOut(
                kind="activity",
                at=row.created_at,
                title=row.action_type,
                subtitle=row.item_name,
                details=row.details,
            )
        )
    stock = await db.execute(
        select(StockAdjustmentLog, CatalogItem.name)
        .outerjoin(CatalogItem, CatalogItem.id == StockAdjustmentLog.item_id)
        .where(
            StockAdjustmentLog.business_id == business_id,
            StockAdjustmentLog.updated_by == user_id,
        )
        .order_by(desc(StockAdjustmentLog.updated_at))
        .limit(limit)
    )
    for log, name in stock.all():
        entries.append(
            LedgerEntryOut(
                kind="stock",
                at=log.updated_at,
                title="STOCK_UPDATE",
                subtitle=name,
                details={
                    "old_qty": float(log.old_qty),
                    "new_qty": float(log.new_qty),
                },
            )
        )
    entries.sort(key=lambda e: e.at, reverse=True)
    return entries[:limit]


@router.get("/{user_id}/permissions", response_model=PermissionsOut)
async def get_permissions(
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_role("owner", "super_admin"))],
):
    row = await _load_user_membership(db, business_id, user_id)
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="User not found")
    _user, mem = row
    perms = await membership_permissions(mem)
    return PermissionsOut(role=mem.role, permissions=perms)


@router.patch("/{user_id}/permissions", response_model=PermissionsOut)
async def patch_permissions(
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    body: PermissionsPatchIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_role("owner", "super_admin"))],
):
    row = await _load_user_membership(db, business_id, user_id)
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="User not found")
    _user, mem = row
    current = mem.permissions_json if isinstance(mem.permissions_json, dict) else {}
    merged = dict(current)
    for k in PERMISSION_KEYS:
        if k in body.permissions:
            merged[k] = bool(body.permissions[k])
    mem.permissions_json = merged
    await db.commit()
    perms = await membership_permissions(mem)
    return PermissionsOut(role=mem.role, permissions=perms)


activity_router = APIRouter(prefix="/v1/businesses/{business_id}/activity-log", tags=["activity"])


@activity_router.post("", response_model=ActivityLogOut, status_code=status.HTTP_201_CREATED)
async def post_activity(
    business_id: uuid.UUID,
    body: ActivityLogIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    display = user.name or user.username
    row = StaffActivityLog(
        business_id=business_id,
        user_id=user.id,
        user_name=display,
        action_type=body.action_type,
        item_id=body.item_id,
        item_name=body.item_name,
        details=body.details,
    )
    db.add(row)
    user.last_active_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(row)
    return ActivityLogOut.model_validate(row)


@activity_router.get("", response_model=list[ActivityLogOut])
async def list_activity(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
    user_id: uuid.UUID | None = None,
    period: str = Query("today"),
    days: int | None = Query(None, ge=1, le=90),
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=200),
):
    uid = user_id or user.id
    now = datetime.now(timezone.utc)
    if days is not None:
        start = now - timedelta(days=days)
    elif period == "week":
        start = now - timedelta(days=7)
    elif period == "month":
        start = now - timedelta(days=30)
    else:
        start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    r = await db.execute(
        select(StaffActivityLog)
        .where(
            StaffActivityLog.business_id == business_id,
            StaffActivityLog.user_id == uid,
            StaffActivityLog.created_at >= start,
        )
        .order_by(desc(StaffActivityLog.created_at))
        .offset((page - 1) * per_page)
        .limit(per_page)
    )
    return [ActivityLogOut.model_validate(x) for x in r.scalars().all()]
