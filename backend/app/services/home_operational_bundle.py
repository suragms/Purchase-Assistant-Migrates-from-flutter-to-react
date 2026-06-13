"""Bundled owner-home operational counts (single DB round-trip group for home-overview)."""

from __future__ import annotations

import asyncio
import uuid
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.membership import Membership
from app.models.notification import AppNotification
from app.routers.stock import stock_alerts_summary, warehouse_alerts_from_stock
from app.services import trade_purchase_service as tps


def _stock_status_counts_from_alerts(stock) -> dict[str, int]:
    out_count = (
        int(stock.active_out_of_stock or 0)
        if int(stock.active_out_of_stock or 0) > 0
        else int(stock.out_of_stock or 0)
    )
    return {
        "all": int(stock.total_items or 0),
        "low": int(stock.low_stock or 0),
        "critical": int(stock.critical_stock or 0),
        "out": out_count,
        "missing_code": int(stock.missing_item_code or 0),
        "missing_barcode": int(stock.missing_barcode or 0),
    }


async def _unread_notification_count(
    db: AsyncSession,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
) -> int:
    unread_r = await db.execute(
        select(func.count())
        .select_from(AppNotification)
        .where(
            AppNotification.business_id == business_id,
            AppNotification.user_id == user_id,
            AppNotification.read_at.is_(None),
        )
    )
    return int(unread_r.scalar_one() or 0)


async def build_home_operational_bundle(
    db: AsyncSession,
    business_id: uuid.UUID,
    membership: Membership,
) -> dict[str, Any]:
    """Stock chips, warehouse alerts, delivery pipeline, and notification unread for Home."""
    stock, pipeline, unread = await asyncio.gather(
        stock_alerts_summary(
            business_id=business_id,
            db=db,
            _m=membership,
        ),
        tps.get_trade_purchase_delivery_pipeline(db, business_id),
        _unread_notification_count(db, business_id, membership.user_id),
    )
    warehouse = await warehouse_alerts_from_stock(db, business_id, stock)
    return {
        "stock_status_counts": _stock_status_counts_from_alerts(stock),
        "warehouse_alerts": warehouse.model_dump(),
        "delivery_pipeline": pipeline.model_dump(mode="json"),
        "notifications_unread": unread,
    }
