"""Transaction-safe stock movement ledger helpers."""

from __future__ import annotations

import asyncio

import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Literal

from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CatalogItem, Membership, User
from app.models.stock_adjustment import StockAdjustmentLog
from app.models.stock_movement import StockMovement
from app.services.staff_audit import log_staff_activity_best_effort
from app.services.stock_inventory import catalog_stock_qty
from app.services.unit_normalization import catalog_stock_unit

MovementMode = Literal["absolute", "delta"]


class StaleStockVersionError(ValueError):
    def __init__(
        self,
        *,
        current_version: int,
        current_qty: Decimal,
        item_name: str | None = None,
    ):
        super().__init__("Stock changed. Refresh and try again.")
        self.current_version = current_version
        self.current_qty = current_qty
        self.item_name = (item_name or "").strip() or "item"


@dataclass(frozen=True)
class StockMovementResult:
    movement: StockMovement
    item: CatalogItem
    duplicate: bool = False


class NegativeStockError(ValueError):
    def __init__(
        self,
        *,
        item_name: str,
        current_qty: Decimal,
        attempted_delta: Decimal,
        unit: str | None,
    ) -> None:
        self.item_name = item_name
        self.current_qty = current_qty
        self.attempted_delta = attempted_delta
        self.unit = (unit or "").strip().upper()
        msg = (
            f"This would reduce {item_name} stock below zero. "
            f"Current stock: {current_qty} {self.unit or ''}. "
            f"You tried to remove: {abs(attempted_delta)} {self.unit or ''}."
        ).strip()
        super().__init__(" ".join(msg.split()))


def _actor_name(user: User) -> str:
    return (user.name or user.username or user.email or "User").strip()


def staff_activity_type_for_stock_kind(kind: str) -> str:
    """Map stock movement kind to staff_activity_log.action_type.

    Uses legacy-safe codes (032 CHECK) until migration 059 is applied everywhere.
    After 059, callers may log richer codes via dedicated endpoints.
    """
    k = (kind or "").strip().lower()
    legacy_safe = {
        "quick_purchase",
        "damage",
        "correction",
        "sale",
        "opening_stock",
        "delivery_adjustment",
        "physical_count",
        "verification",
        "usage",
        "undo",
    }
    if k in legacy_safe:
        return "STOCK_UPDATE"
    return "STOCK_UPDATE"


def _activity_type_for(kind: str) -> str:
    return staff_activity_type_for_stock_kind(kind)


def _adjustment_type_for(kind: str) -> str:
    mapping = {
        "quick_purchase": "purchase",
        "physical_count": "verification",
        "damage": "damaged",
        "correction": "correction",
        "sale": "sale",
        "opening_stock": "opening_stock",
        "delivery_receive": "purchase",
        "delivery_revoke": "purchase_reversal",
        "delivery_adjustment": "purchase_adjustment",
        "usage": "usage",
        "undo": "correction",
    }
    return mapping.get((kind or "").strip().lower(), "manual")


async def _locked_item(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    item_id: uuid.UUID,
) -> CatalogItem | None:
    stmt = (
        select(CatalogItem)
        .where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
        .with_for_update()
    )
    r = await db.execute(stmt)
    return r.scalar_one_or_none()


async def apply_stock_movement(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    user: User,
    movement_kind: str,
    mode: MovementMode,
    qty: Decimal,
    reason: str | None,
    notes: str | None = None,
    source_type: str | None = None,
    source_id: uuid.UUID | None = None,
    idempotency_key: str | None = None,
    metadata: dict[str, Any] | None = None,
    unit_mismatch_flag: bool = False,
    last_seen_stock_version: int | None = None,
    force_version: bool = False,
    version_tolerance: int = 0,
    create_projection: bool = True,
    create_activity: bool = True,
) -> StockMovementResult:
    """Apply one stock event and write ledger/projection rows in the same DB transaction.

    The caller owns commit/rollback. Additive operations use `mode="delta"` and
    absolute physical counts use `mode="absolute"`.
    """

    idem = (idempotency_key or "").strip()
    if idem:
        existing_r = await db.execute(
            select(StockMovement).where(
                StockMovement.business_id == business_id,
                StockMovement.idempotency_key == idem,
            )
        )
        existing = existing_r.scalar_one_or_none()
        if existing is not None:
            item = await _locked_item(db, business_id=business_id, item_id=existing.item_id)
            if item is None:
                raise ValueError("Item not found")
            return StockMovementResult(existing, item, duplicate=True)
    else:
        idem = f"{movement_kind}:{item_id}:{uuid.uuid4().hex}"

    from app.services.stock_change_guard import assert_stock_changes_allowed

    await assert_stock_changes_allowed(
        db,
        business_id=business_id,
        movement_kind=movement_kind,
        source_type=source_type,
        actor_user_id=user.id,
    )

    # Serialize concurrent writers per business+item to reduce high-contention
    # stale-version storms before row-level lock acquisition.
    dialect_name = ""
    try:
        bind = db.get_bind()
        if bind is not None and bind.dialect is not None:
            dialect_name = (bind.dialect.name or "").lower()
    except Exception:
        dialect_name = ""
    if dialect_name == "postgresql":
        lock_key = f"stock_item:{business_id}:{item_id}"
        await db.execute(
            text("SELECT pg_advisory_xact_lock(hashtext(:lock_key)::bigint)"),
            {"lock_key": lock_key},
        )

    item = await _locked_item(db, business_id=business_id, item_id=item_id)
    if item is None:
        raise ValueError("Item not found")

    current_version = int(getattr(item, "stock_version", 0) or 0)
    before = catalog_stock_qty(item)
    if last_seen_stock_version is not None and last_seen_stock_version != current_version:
        drift = current_version - int(last_seen_stock_version)
        allowed = force_version or (
            version_tolerance > 0 and 0 < drift <= version_tolerance
        )
        if not allowed:
            raise StaleStockVersionError(
                current_version=current_version,
                current_qty=before,
                item_name=item.name,
            )

    raw_qty = Decimal(qty)
    if mode == "absolute":
        after = raw_qty
        delta = after - before
    else:
        delta = raw_qty
        after = before + delta
    if after < 0:
        raise NegativeStockError(
            item_name=item.name or "Item",
            current_qty=before,
            attempted_delta=delta,
            unit=catalog_stock_unit(item),
        )

    display = _actor_name(user)
    now = datetime.now(timezone.utc)
    unit = catalog_stock_unit(item)
    item.current_stock = after
    item.stock_version = current_version + 1
    item.last_stock_updated_at = now
    item.last_stock_updated_by = display

    movement = StockMovement(
        id=uuid.uuid4(),
        business_id=business_id,
        item_id=item_id,
        movement_kind=movement_kind,
        delta_qty=delta,
        qty_before=before,
        qty_after=after,
        stock_unit=unit,
        reason=(reason or "").strip() or None,
        notes=(notes or "").strip() or None,
        source_type=source_type,
        source_id=source_id,
        idempotency_key=idem,
        actor_id=user.id,
        actor_name=display,
        unit_mismatch_flag=unit_mismatch_flag,
        metadata_json=metadata or None,
        created_at=now,
    )
    db.add(movement)

    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        if idem:
            existing_r = await db.execute(
                select(StockMovement).where(
                    StockMovement.business_id == business_id,
                    StockMovement.idempotency_key == idem,
                )
            )
            existing = existing_r.scalar_one_or_none()
            if existing is not None:
                item = await _locked_item(
                    db, business_id=business_id, item_id=existing.item_id
                )
                if item is None:
                    raise ValueError("Item not found") from None
                return StockMovementResult(existing, item, duplicate=True)
        raise

    if create_projection:
        db.add(
            StockAdjustmentLog(
                business_id=business_id,
                item_id=item_id,
                old_qty=before,
                new_qty=after,
                adjustment_type=_adjustment_type_for(movement_kind),
                reason=movement.reason or reason,
                updated_by=user.id,
                updated_by_name=display,
                updated_at=now,
            )
        )

    if create_activity:
        await log_staff_activity_best_effort(
            db,
            business_id=business_id,
            user=user,
            action_type=_activity_type_for(movement_kind),
            item_id=item_id,
            item_name=item.name,
            details={
                "movement_kind": movement_kind,
                "source_type": source_type,
                "source_id": str(source_id) if source_id else None,
                "stock_unit": unit,
                "reason": movement.reason,
                "notes": movement.notes,
                "idempotency_key": idem,
            },
            before_data={
                "qty": float(before),
                "stock_version": current_version,
            },
            after_data={
                "qty": float(after),
                "delta_qty": float(delta),
                "stock_version": current_version + 1,
            },
        )

    from app.read_cache_generation import bump_trade_read_caches_for_business

    bump_trade_read_caches_for_business(business_id)
    return StockMovementResult(movement, item)


_MAX_STALE_RETRIES = 3


async def apply_stock_movement_with_retry(
    db: AsyncSession,
    *,
    max_attempts: int = _MAX_STALE_RETRIES,
    **kwargs: Any,
) -> StockMovementResult:
    """Retry on optimistic-lock conflict (concurrent stock updates)."""
    last_err: StaleStockVersionError | None = None
    for attempt in range(max_attempts):
        try:
            return await apply_stock_movement(db, **kwargs)
        except StaleStockVersionError as e:
            last_err = e
            if kwargs.get("last_seen_stock_version") is not None:
                raise
            if attempt + 1 >= max_attempts:
                raise
            await asyncio.sleep(0.1)
    assert last_err is not None
    raise last_err
