"""Reports sourced from trade_purchases + trade_purchase_lines (wholesale flow)."""

from __future__ import annotations

import uuid
from collections import OrderedDict
from copy import deepcopy
from datetime import date, datetime, timedelta, timezone
from time import monotonic
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import String, and_, case, cast, func, literal, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.async_budget import run_read_budget_bounded
from app.database import get_db
from app.db_resilience import execute_with_retry
from app.deps import get_current_user, require_membership, require_role
from app.models import CatalogItem, CategoryType, ItemCategory, Membership, TradePurchase, TradePurchaseLine, User
from app.models.stock_adjustment import StockAdjustmentLog
from app.models.contacts import Supplier
from app.read_cache_generation import trade_read_cache_generation
from app.services import trade_mapping as trade_map
from app.services import trade_query as tq
from app.services.stock_inventory import compute_inventory_summary

router = APIRouter(prefix="/v1/businesses/{business_id}/reports", tags=["reports-trade"])

_trade_line_amount_expr = tq.trade_line_amount_expr
_trade_purchase_date_filter = tq.trade_purchase_date_filter

_trade_dashboard_ttl_s = 20.0
_trade_dashboard_cache: dict[tuple[str, str, str, int, bool], tuple[float, dict[str, Any]]] = {}
_trade_dashboard_cache_max = 256

_trade_summary_ttl_s = 20.0
_trade_summary_cache: dict[tuple[str, str, str, str, int], tuple[float, dict[str, Any]]] = {}
_trade_summary_cache_max = 256

_DEGRADED_META = frozenset({"degraded", "degraded_reason"})
_trade_dashboard_last_good: OrderedDict[tuple[Any, ...], dict[str, Any]] = OrderedDict()
_trade_dashboard_last_good_max = 512
_trade_summary_last_good: OrderedDict[tuple[Any, ...], dict[str, Any]] = OrderedDict()
_trade_summary_last_good_max = 256


def _normalize_optional_uuid_str(value: Any) -> str | None:
    """Hyphenated UUID for API JSON; SQLite max(cast(uuid, String)) can return 32-char hex."""
    if value is None:
        return None
    s = str(value).strip()
    if not s:
        return None
    try:
        return str(uuid.UUID(s))
    except ValueError:
        pass
    if len(s) == 32 and "-" not in s:
        try:
            return str(uuid.UUID(hex=s))
        except ValueError:
            return s
    return s


def _strip_degraded_snapshot_fields(payload: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in payload.items() if k not in _DEGRADED_META}


def _empty_snapshot_for_dates(ds_from: str, ds_to: str) -> dict[str, Any]:
    return {
        "from": ds_from,
        "to": ds_to,
        "summary": {
            "deals": 0,
            "total_purchase": 0.0,
            "total_landing": 0.0,
            "total_selling": 0.0,
            "total_profit": 0.0,
            "profit_percent": None,
            "total_qty": 0.0,
            "pending_delivery_count": 0,
        },
        "unit_totals": {
            "total_kg": 0.0,
            "total_bags": 0.0,
            "total_boxes": 0.0,
            "total_tins": 0.0,
        },
        "categories": [],
        "subcategories": [],
        "item_slices": [],
        "suppliers": [],
        "recommendations": [],
        "consistency": {"portfolio_score": None},
    }


def _put_dashboard_last_good(key: tuple[Any, ...], payload: dict[str, Any]) -> None:
    clean = _strip_degraded_snapshot_fields(dict(payload))
    if key in _trade_dashboard_last_good:
        del _trade_dashboard_last_good[key]
    _trade_dashboard_last_good[key] = deepcopy(clean)
    while len(_trade_dashboard_last_good) > _trade_dashboard_last_good_max:
        _trade_dashboard_last_good.popitem(last=False)


def _put_summary_last_good(key: tuple[Any, ...], payload: dict[str, Any]) -> None:
    clean = _strip_degraded_snapshot_fields(dict(payload))
    if key in _trade_summary_last_good:
        del _trade_summary_last_good[key]
    _trade_summary_last_good[key] = deepcopy(clean)
    while len(_trade_summary_last_good) > _trade_summary_last_good_max:
        _trade_summary_last_good.popitem(last=False)


def _degraded_dashboard_response(
    key: tuple[Any, ...],
    date_from: date,
    date_to: date,
    *,
    compact: bool,
) -> dict[str, Any]:
    lg = _trade_dashboard_last_good.get(key)
    if lg:
        out = dict(deepcopy(lg))
    else:
        out = _empty_snapshot_for_dates(date_from.isoformat(), date_to.isoformat())
        if compact:
            _apply_trade_dashboard_compact(out)
    out["degraded"] = True
    out["degraded_reason"] = "read_budget_exceeded"
    return out


def _degraded_summary_response(key: tuple[Any, ...]) -> dict[str, Any]:
    lg = _trade_summary_last_good.get(key)
    if lg:
        out = dict(deepcopy(lg))
    else:
        out = {
            "deals": 0,
            "total_purchase": 0.0,
            "total_qty": 0.0,
            "avg_cost": 0.0,
            "unit_totals": {
                "total_kg": 0.0,
                "total_bags": 0.0,
                "total_boxes": 0.0,
                "total_tins": 0.0,
            },
        }
    out["degraded"] = True
    out["degraded_reason"] = "read_budget_exceeded"
    return out


async def _trade_suppliers_rows(
    db: AsyncSession,
    business_id: uuid.UUID,
    date_from: date,
    date_to: date,
) -> list[dict[str, Any]]:
    """Same rows as GET /trade-suppliers (line-based amounts, report status filter)."""
    amt = _trade_line_amount_expr()
    kg_line = tq.trade_line_weight_expr()
    bag_expr = tq.trade_line_qty_bags_expr()
    box_expr = tq.trade_line_qty_boxes_expr()
    tin_expr = tq.trade_line_qty_tins_expr()
    bag_sum = func.coalesce(func.sum(bag_expr), 0.0)
    box_sum = func.coalesce(func.sum(box_expr), 0.0)
    tin_sum = func.coalesce(func.sum(tin_expr), 0.0)
    kg_sum = func.coalesce(func.sum(kg_line), 0.0)
    bf = _trade_purchase_date_filter(business_id, date_from, date_to)
    q = (
        select(
            Supplier.id,
            func.coalesce(Supplier.name, "Unknown").label("supplier_name"),
            func.count(func.distinct(TradePurchase.id)).label("deals"),
            func.coalesce(func.sum(amt), 0.0).label("total_purchase"),
            func.coalesce(func.sum(TradePurchaseLine.qty), 0.0).label("total_qty"),
            bag_sum.label("total_bags"),
            box_sum.label("total_boxes"),
            tin_sum.label("total_tins"),
            kg_sum.label("total_kg"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .outerjoin(Supplier, Supplier.id == TradePurchase.supplier_id)
        .where(bf)
        .group_by(Supplier.id, Supplier.name)
        .having(func.count(func.distinct(TradePurchase.id)) > 0)
        .order_by(func.coalesce(func.sum(amt), 0.0).desc())
    )
    rows = (await execute_with_retry(lambda: db.execute(q))).mappings().all()
    return [
        {
            "supplier_id": str(r["id"]) if r["id"] is not None else "",
            "supplier_name": str(r["supplier_name"] or "Unknown"),
            "purchase_count": int(r["deals"] or 0),
            "deals": int(r["deals"] or 0),
            "total_purchase": float(r["total_purchase"] or 0),
            "total_qty": float(r["total_qty"] or 0),
            "total_bags": float(r["total_bags"] or 0),
            "total_boxes": float(r["total_boxes"] or 0),
            "total_tins": float(r["total_tins"] or 0),
            "total_kg": float(r["total_kg"] or 0),
            "total_profit": 0.0,
            "avg_landing": 0.0,
            "margin_pct": 0.0,
        }
        for r in rows
    ]


def _snapshot_cache_key(
    business_id: uuid.UUID,
    date_from: date,
    date_to: date,
    *,
    compact: bool,
    shell_bundle: bool = False,
) -> tuple[str, str, str, int, bool, bool]:
    return (
        str(business_id),
        date_from.isoformat(),
        date_to.isoformat(),
        trade_read_cache_generation(business_id),
        compact,
        shell_bundle,
    )


def _apply_trade_dashboard_compact(payload: dict[str, Any]) -> None:
    """Trim heavy arrays; summary, categories, unit_totals, suppliers retained."""
    payload["subcategories"] = []
    payload["item_slices"] = []
    payload["recommendations"] = []
    payload["consistency"] = {"portfolio_score": None}


def _attach_analytics_panel_blocks(
    payload: dict[str, Any],
    stock: dict[str, float | int],
) -> None:
    """Point-in-time stock + period purchased totals for home analytics strip."""
    unit_totals = payload.get("unit_totals")
    if not isinstance(unit_totals, dict):
        unit_totals = {}
    summary = payload.get("summary")
    if not isinstance(summary, dict):
        summary = {}
    payload["stock_in_hand"] = {
        "bags": stock.get("bags", 0),
        "boxes": stock.get("boxes", 0),
        "tins": stock.get("tins", 0),
        "kg": stock.get("kg", 0),
        "total_value_inr": stock.get("total_value_inr", 0),
        "item_count": stock.get("item_count", 0),
    }
    payload["purchased"] = {
        "bags": float(unit_totals.get("total_bags") or 0),
        "boxes": float(unit_totals.get("total_boxes") or 0),
        "tins": float(unit_totals.get("total_tins") or 0),
        "kg": float(unit_totals.get("total_kg") or 0),
        "amount_inr": float(summary.get("total_purchase") or 0),
        "deals": int(summary.get("deals") or 0),
    }


async def _fetch_trade_items_breakdown_rows(
    db: AsyncSession,
    business_id: uuid.UUID,
    date_from: date,
    date_to: date,
) -> list[dict[str, Any]]:
    amt = _trade_line_amount_expr()
    bf = _trade_purchase_date_filter(business_id, date_from, date_to)
    kg_line = tq.trade_line_weight_expr()
    bag_expr = tq.trade_line_qty_bags_expr()
    box_expr = tq.trade_line_qty_boxes_expr()
    tin_expr = tq.trade_line_qty_tins_expr()
    bag_sum = func.coalesce(func.sum(bag_expr), 0.0)
    box_sum = func.coalesce(func.sum(box_expr), 0.0)
    tin_sum = func.coalesce(func.sum(tin_expr), 0.0)
    kg_sum = func.coalesce(func.sum(kg_line), 0.0)
    land_gross = tq.trade_line_amount_expr()
    sell_gross = tq.trade_line_selling_expr()
    land_sum = func.coalesce(func.sum(land_gross), 0.0)
    sell_sum = func.coalesce(func.sum(sell_gross), 0.0)
    q = (
        select(
            TradePurchaseLine.item_name,
            func.max(cast(TradePurchaseLine.catalog_item_id, String)).label("catalog_item_id"),
            func.coalesce(func.sum(amt), 0).label("total_purchase"),
            func.coalesce(func.sum(TradePurchaseLine.qty), 0).label("total_qty"),
            func.count(TradePurchaseLine.id).label("line_count"),
            func.count(func.distinct(TradePurchaseLine.trade_purchase_id)).label("deals"),
            func.max(TradePurchaseLine.unit).label("unit"),
            bag_sum.label("total_bags"),
            box_sum.label("total_boxes"),
            tin_sum.label("total_tins"),
            kg_sum.label("total_kg"),
            land_sum.label("total_landing_gross"),
            sell_sum.label("total_selling_gross"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(bf)
        .group_by(TradePurchaseLine.item_name)
        .order_by(func.coalesce(func.sum(amt), 0).desc())
    )
    rows = (await execute_with_retry(lambda: db.execute(q))).mappings().all()
    out: list[dict[str, Any]] = []
    for r in rows:
        qty = float(r["total_qty"] or 0)
        tp = float(r["total_purchase"] or 0)
        tb = float(r["total_bags"] or 0)
        txb = float(r["total_boxes"] or 0)
        ttn = float(r["total_tins"] or 0)
        tkg = float(r["total_kg"] or 0)
        tland = float(r["total_landing_gross"] or 0)
        tsl = float(r["total_selling_gross"] or 0)
        tprof = tsl - tland if tsl > 1e-12 or tland > 1e-12 else 0.0
        cid = _normalize_optional_uuid_str(r.get("catalog_item_id"))
        out.append(
            {
                "item_name": (r["item_name"] or "Unknown").strip() or "Unknown",
                "catalog_item_id": cid,
                "total_qty": qty,
                "unit": (r["unit"] or "").strip() or "—",
                "total_purchase": tp,
                "total_profit": tprof,
                "line_count": int(r["line_count"] or 0),
                "purchase_count": int(r["deals"] or 0),
                "avg_landing": (tland / qty) if qty > 1e-12 else 0.0,
                "total_bags": tb,
                "total_boxes": txb,
                "total_tins": ttn,
                "total_kg": tkg,
                "total_selling": tsl,
                "total_landing_gross": tland,
            }
        )
    return out


async def _fetch_trade_types_breakdown_rows(
    db: AsyncSession,
    business_id: uuid.UUID,
    date_from: date,
    date_to: date,
) -> list[dict[str, Any]]:
    amt = _trade_line_amount_expr()
    bf = _trade_purchase_date_filter(business_id, date_from, date_to)
    parent_cat = func.coalesce(ItemCategory.name, "Uncategorized").label("category_name")
    type_label = case(
        (CatalogItem.type_id.is_(None), literal("No type")),
        else_=func.coalesce(CategoryType.name, "Unknown"),
    ).label("type_name")
    qty_sum = func.coalesce(func.sum(TradePurchaseLine.qty), 0)
    kg_line = tq.trade_line_weight_expr()
    bag_expr = tq.trade_line_qty_bags_expr()
    box_expr = tq.trade_line_qty_boxes_expr()
    tin_expr = tq.trade_line_qty_tins_expr()
    bag_sum = func.coalesce(func.sum(bag_expr), 0.0)
    box_sum = func.coalesce(func.sum(box_expr), 0.0)
    tin_sum = func.coalesce(func.sum(tin_expr), 0.0)
    kg_sum = func.coalesce(func.sum(kg_line), 0.0)
    q = (
        select(
            parent_cat,
            type_label,
            func.coalesce(func.sum(amt), 0).label("total_purchase"),
            qty_sum.label("total_qty"),
            bag_sum.label("total_bags"),
            box_sum.label("total_boxes"),
            tin_sum.label("total_tins"),
            kg_sum.label("total_kg"),
            func.count(TradePurchaseLine.id).label("line_count"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .outerjoin(
            CatalogItem,
            and_(CatalogItem.id == TradePurchaseLine.catalog_item_id, CatalogItem.deleted_at.is_(None)),
        )
        .outerjoin(ItemCategory, ItemCategory.id == CatalogItem.category_id)
        .outerjoin(CategoryType, CategoryType.id == CatalogItem.type_id)
        .where(bf)
        .group_by(parent_cat, type_label)
        .order_by(func.coalesce(func.sum(amt), 0).desc())
    )
    rows = (await execute_with_retry(lambda: db.execute(q))).mappings().all()
    return [
        {
            "type_name": str(r["type_name"] or "No type"),
            "category_name": str(r["category_name"] or "Uncategorized"),
            "subcategory": str(r["type_name"] or "No type"),
            "line_count": int(r["line_count"] or 0),
            "total_purchase": float(r["total_purchase"] or 0),
            "total_qty": float(r["total_qty"] or 0),
            "total_bags": float(r["total_bags"] or 0),
            "total_boxes": float(r["total_boxes"] or 0),
            "total_tins": float(r["total_tins"] or 0),
            "total_kg": float(r["total_kg"] or 0),
            "total_profit": 0.0,
        }
        for r in rows
    ]


async def _compute_trade_dashboard_snapshot_payload(
    db: AsyncSession,
    business_id: uuid.UUID,
    date_from: date,
    date_to: date,
) -> dict[str, Any]:
    """Single snapshot dict — same fields as GET /trade-dashboard-snapshot."""
    amt = _trade_line_amount_expr()
    bf = _trade_purchase_date_filter(business_id, date_from, date_to)
    kg_expr = tq.trade_line_weight_expr()
    bag_expr = tq.trade_line_qty_bags_expr()
    box_expr = tq.trade_line_qty_boxes_expr()
    tin_expr = tq.trade_line_qty_tins_expr()
    roll = (
        select(
            func.coalesce(func.sum(bag_expr), 0.0).label("total_bags"),
            func.coalesce(func.sum(box_expr), 0.0).label("total_boxes"),
            func.coalesce(func.sum(tin_expr), 0.0).label("total_tins"),
            func.coalesce(func.sum(kg_expr), 0.0).label("total_kg"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(bf)
    )
    sell_line = tq.trade_line_selling_expr()
    sum_q = select(
        func.count(func.distinct(TradePurchase.id)).label("deals"),
        func.coalesce(func.sum(amt), 0.0).label("total_purchase"),
        func.coalesce(func.sum(TradePurchaseLine.qty), 0.0).label("total_qty"),
        func.coalesce(func.sum(sell_line), 0.0).label("total_selling"),
    ).select_from(TradePurchaseLine).join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id).where(bf)
    cat_id_key = case(
        (ItemCategory.id.isnot(None), func.cast(ItemCategory.id, String)),
        else_=literal("_uncat"),
    ).label("category_id")
    cn = func.coalesce(ItemCategory.name, "Uncategorised").label("category_name")
    nest_q = (
        select(
            cat_id_key,
            cn,
            TradePurchaseLine.item_name,
            func.max(TradePurchaseLine.unit).label("unit"),
            func.max(TradePurchaseLine.unit_type).label("unit_type"),
            func.coalesce(func.sum(amt), 0.0).label("amount"),
            func.coalesce(func.sum(TradePurchaseLine.qty), 0.0).label("qty"),
            func.max(cast(TradePurchaseLine.catalog_item_id, String)).label("catalog_item_id"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .outerjoin(
            CatalogItem,
            and_(CatalogItem.id == TradePurchaseLine.catalog_item_id, CatalogItem.deleted_at.is_(None)),
        )
        .outerjoin(ItemCategory, ItemCategory.id == CatalogItem.category_id)
        .where(bf)
        .group_by(cat_id_key, cn, TradePurchaseLine.item_name)
    )
    eroll = await execute_with_retry(lambda: db.execute(roll))
    esum = await execute_with_retry(lambda: db.execute(sum_q))
    enest = await execute_with_retry(lambda: db.execute(nest_q))
    roll_row = eroll.mappings().one()
    srow = esum.mappings().one()
    flat = enest.mappings().all()

    mapping = await trade_map.item_supplier_broker_rows(db, business_id, date_from, date_to)
    items = await _fetch_trade_items_breakdown_rows(db, business_id, date_from, date_to)
    types = await _fetch_trade_types_breakdown_rows(db, business_id, date_from, date_to)
    suppliers = await _trade_suppliers_rows(db, business_id, date_from, date_to)
    detail, recs = mapping
    total_purchase = float(srow["total_purchase"] or 0)
    total_selling = float(srow["total_selling"] or 0)
    total_qty = float(srow["total_qty"] or 0)
    deals = int(srow["deals"] or 0)
    total_landing = total_purchase
    total_profit = total_selling - total_landing
    profit_percent: float | None
    if total_landing > 1e-12:
        profit_percent = (total_profit / total_landing) * 100.0
    else:
        profit_percent = None

    cat_map: dict[str, dict[str, Any]] = {}
    for r in flat:
        cid = str(r["category_id"] or "_uncat")
        cname = str(r["category_name"] or "Uncategorised")
        if cid not in cat_map:
            cat_map[cid] = {
                "category_id": cid,
                "category_name": cname,
                "total_purchase": 0.0,
                "total_qty": 0.0,
                "units": {"bags": 0.0, "boxes": 0.0, "tins": 0.0},
                "items": [],
            }
        unit = str(r["unit"] or "")
        uu = unit.upper()
        ut_cat = str(r["unit_type"] or "").strip().lower()
        qv = float(r["qty"] or 0)
        am = float(r["amount"] or 0)
        cat_map[cid]["total_purchase"] += am
        cat_map[cid]["total_qty"] += qv
        if ut_cat == "bag" or (not ut_cat and ("BAG" in uu or "SACK" in uu)):
            cat_map[cid]["units"]["bags"] += qv
        if ut_cat == "box" or (not ut_cat and "BOX" in uu):
            cat_map[cid]["units"]["boxes"] += qv
        if ut_cat == "tin" or (not ut_cat and "TIN" in uu):
            cat_map[cid]["units"]["tins"] += qv
        ci = _normalize_optional_uuid_str(r["catalog_item_id"])
        cat_map[cid]["items"].append(
            {
                "name": (r["item_name"] or "—").strip() or "—",
                "qty": qv,
                "unit": unit,
                "amount": am,
                "catalog_item_id": ci,
            }
        )
    for c in cat_map.values():
        c["items"].sort(key=lambda x: x["amount"], reverse=True)

    by_cid: dict[str, list[dict[str, Any]]] = {}
    for drow in detail:
        iid = _normalize_optional_uuid_str(drow.get("catalog_item_id"))
        if not iid:
            continue
        sid = iid
        if sid not in by_cid:
            by_cid[sid] = []
        by_cid[sid].append(drow)
    for c in cat_map.values():
        its = c.get("items") or []
        sup = "—"
        bro: str = "—"
        for it in its:
            iid = it.get("catalog_item_id")
            if not iid:
                continue
            group = by_cid.get(str(iid))
            if not group:
                continue
            best = max(
                group,
                key=lambda g: (float(g.get("total_purchase") or 0.0), str(g.get("supplier_id") or "")),
            )
            sname = str(best.get("supplier_name") or "").strip()
            bname = best.get("broker_name")
            sup = sname or "—"
            bro = str(bname).strip() if bname is not None and str(bname).strip() else "—"
            break
        c["subtitle_supplier"] = sup
        c["subtitle_broker"] = bro
    cids = {d["catalog_item_id"] for d in detail if d.get("catalog_item_id")}
    scores: list[float] = []
    for cid in cids:
        zs = [r.get("vwap_zscore") for r in detail if r.get("catalog_item_id") == cid]
        sc = trade_map.consistency_score_from_zscores(zs)
        if sc is not None:
            scores.append(sc)
    portfolio_consistency = sum(scores) / len(scores) if scores else None

    pend_q = (
        select(func.count())
        .select_from(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.is_delivered.is_(False),
            TradePurchase.status.notin_(("deleted", "cancelled")),
        )
    )
    pending_delivery_count = int(
        (await execute_with_retry(lambda: db.execute(pend_q))).scalar() or 0
    )

    return {
        "from": date_from.isoformat(),
        "to": date_to.isoformat(),
        "summary": {
            "deals": deals,
            "total_purchase": total_purchase,
            "total_landing": total_landing,
            "total_selling": total_selling,
            "total_profit": total_profit,
            "profit_percent": round(profit_percent, 2) if profit_percent is not None else None,
            "total_qty": total_qty,
            "pending_delivery_count": pending_delivery_count,
        },
        "unit_totals": {
            "total_kg": float(roll_row["total_kg"] or 0),
            "total_bags": float(roll_row["total_bags"] or 0),
            "total_boxes": float(roll_row["total_boxes"] or 0),
            "total_tins": float(roll_row["total_tins"] or 0),
        },
        "categories": list(cat_map.values()),
        "subcategories": types,
        "item_slices": items,
        "suppliers": suppliers,
        "recommendations": recs,
        "consistency": {"portfolio_score": portfolio_consistency},
    }


@router.get("/trade-supplier-broker-map")
async def trade_supplier_broker_map(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    date_from: date = Query(..., alias="from"),
    date_to: date = Query(..., alias="to"),
) -> dict[str, Any]:
    """Item-level trade lines to (supplier, broker) with vwap; optional z-scores and best-supplier recs (deals>=2)."""
    del _m
    detail, recs = await trade_map.item_supplier_broker_rows(db, business_id, date_from, date_to)
    return {"rows": detail, "recommendations": recs}


@router.get("/trade-last-supplier-autofill")
async def trade_last_supplier_autofill(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    supplier_id: uuid.UUID = Query(..., description="Supplier to load latest trade header for"),
) -> dict[str, Any]:
    """Latest TradePurchase header for supplier (draft autofill; trade rows only)."""
    del user, _m
    return await trade_map.latest_supplier_trade_header_defaults(db, business_id, supplier_id)


@router.get("/trade-dashboard-snapshot")
async def trade_dashboard_snapshot(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_role("owner", "manager", "super_admin"))],
    db: Annotated[AsyncSession, Depends(get_db)],
    date_from: date = Query(..., alias="from"),
    date_to: date = Query(..., alias="to"),
) -> dict[str, Any]:
    """Single payload matching report definitions: summary, unit rollups, categories with line items, types, top items."""
    del _m
    cache_key = _snapshot_cache_key(business_id, date_from, date_to, compact=False, shell_bundle=False)
    now_mono = monotonic()
    cached = _trade_dashboard_cache.get(cache_key)
    if cached is not None and now_mono - cached[0] <= _trade_dashboard_ttl_s:
        return cached[1]

    async def compute() -> dict[str, Any]:
        return await _compute_trade_dashboard_snapshot_payload(db, business_id, date_from, date_to)

    ok, maybe = await run_read_budget_bounded(compute)
    if not ok or maybe is None:
        return _degraded_dashboard_response(cache_key, date_from, date_to, compact=False)
    payload = _strip_degraded_snapshot_fields(dict(maybe))
    _put_dashboard_last_good(cache_key, payload)
    _trade_dashboard_cache[cache_key] = (now_mono, payload)
    if len(_trade_dashboard_cache) > _trade_dashboard_cache_max:
        _trade_dashboard_cache.clear()
    return payload


@router.get("/home-overview")
async def trade_home_overview(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    date_from: date = Query(..., alias="from"),
    date_to: date = Query(..., alias="to"),
    compact: bool = Query(False, description="Omit heavy snapshot arrays when true."),
    shell_bundle: bool = Query(
        False,
        description="When true, attach home_shell (subcategories, suppliers, items) from the same snapshot compute (no extra queries).",
    ),
    max_span_days: int | None = Query(
        None,
        ge=1,
        le=400,
        description="When set, reject ranges longer than this (inclusive calendar days).",
    ),
) -> dict[str, Any]:
    """Bundled dashboard snapshot shape for Flutter home — delegates to snapshot builder (+ optional compact)."""
    del _m
    if date_from > date_to:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail="from_must_not_exceed_to")
    inclusive_days = (date_to - date_from).days + 1
    if max_span_days is not None and inclusive_days > max_span_days:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail="date_range_exceeds_max_span_days")

    cache_key = _snapshot_cache_key(
        business_id, date_from, date_to, compact=compact, shell_bundle=shell_bundle
    )
    now_mono = monotonic()
    cached = _trade_dashboard_cache.get(cache_key)
    if cached is not None and now_mono - cached[0] <= _trade_dashboard_ttl_s:
        return cached[1]

    async def compute() -> dict[str, Any]:
        full = await _compute_trade_dashboard_snapshot_payload(db, business_id, date_from, date_to)
        out = dict(full)
        home_shell: dict[str, Any] | None = None
        if shell_bundle:
            home_shell = {
                "subcategories": list(out.get("subcategories") or []),
                "suppliers": list(out.get("suppliers") or []),
                "items": list(out.get("item_slices") or []),
            }
            stock = await compute_inventory_summary(db, business_id)
            _attach_analytics_panel_blocks(out, stock)
        if compact:
            _apply_trade_dashboard_compact(out)
        if home_shell is not None:
            out["home_shell"] = home_shell
        return out

    ok, maybe = await run_read_budget_bounded(compute)
    if not ok or maybe is None:
        return _degraded_dashboard_response(cache_key, date_from, date_to, compact=compact)
    payload = _strip_degraded_snapshot_fields(dict(maybe))
    _put_dashboard_last_good(cache_key, payload)
    _trade_dashboard_cache[cache_key] = (now_mono, payload)
    if len(_trade_dashboard_cache) > _trade_dashboard_cache_max:
        _trade_dashboard_cache.clear()
    return payload


@router.get("/trade-summary")
async def trade_purchase_summary(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_role("owner", "manager", "super_admin"))],
    date_from: date | None = Query(None, alias="from"),
    date_to: date | None = Query(None, alias="to"),
    supplier_id: uuid.UUID | None = Query(None),
):
    """
    Line-based totals: same [trade_line_amount_expr] and status filter as
    /trade-items and /trade-dashboard-snapshot. Header [TradePurchase.total_amount]
    can differ (freight/rounding); report KPIs use line sums.
    """
    del user
    gen = trade_read_cache_generation(business_id)
    su_key = (
        str(business_id),
        date_from.isoformat() if date_from is not None else "",
        date_to.isoformat() if date_to is not None else "",
        str(supplier_id) if supplier_id is not None else "",
        gen,
    )
    t0 = monotonic()
    hit = _trade_summary_cache.get(su_key)
    if hit is not None and t0 - hit[0] <= _trade_summary_ttl_s:
        return hit[1]

    async def compute_summary() -> dict[str, Any]:
        amt_inner = tq.trade_line_amount_expr()
        conditions_inner = [
            TradePurchase.business_id == business_id,
            tq.trade_purchase_status_in_reports(),
        ]
        if date_from is not None:
            conditions_inner.append(TradePurchase.purchase_date >= date_from)
        if date_to is not None:
            conditions_inner.append(TradePurchase.purchase_date <= date_to)
        if supplier_id is not None:
            conditions_inner.append(TradePurchase.supplier_id == supplier_id)
        q_inner = (
            select(
                func.count(func.distinct(TradePurchase.id)).label("deals"),
                func.coalesce(func.sum(amt_inner), 0.0).label("total_purchase"),
                func.coalesce(func.sum(TradePurchaseLine.qty), 0.0).label("total_qty"),
            )
            .select_from(TradePurchaseLine)
            .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
            .where(and_(*conditions_inner))
        )
        m = (await execute_with_retry(lambda: db.execute(q_inner))).mappings().one()
        deals_val = int(m["deals"] or 0)
        total_purchase_val = float(m["total_purchase"] or 0)
        total_qty_val = float(m["total_qty"] or 0)
        avg_cost_val = (total_purchase_val / total_qty_val) if total_qty_val > 1e-12 else 0.0

        kg_expr_i = tq.trade_line_weight_expr()
        bag_expr_i = tq.trade_line_qty_bags_expr()
        box_expr_i = tq.trade_line_qty_boxes_expr()
        tin_expr_i = tq.trade_line_qty_tins_expr()
        roll_q_inner = (
            select(
                func.coalesce(func.sum(bag_expr_i), 0.0).label("total_bags"),
                func.coalesce(func.sum(box_expr_i), 0.0).label("total_boxes"),
                func.coalesce(func.sum(tin_expr_i), 0.0).label("total_tins"),
                func.coalesce(func.sum(kg_expr_i), 0.0).label("total_kg"),
            )
            .select_from(TradePurchaseLine)
            .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
            .where(and_(*conditions_inner))
        )
        roll_row_inner = (await execute_with_retry(lambda: db.execute(roll_q_inner))).mappings().one()

        return {
            "deals": deals_val,
            "total_purchase": total_purchase_val,
            "total_qty": total_qty_val,
            "avg_cost": avg_cost_val,
            "unit_totals": {
                "total_kg": float(roll_row_inner["total_kg"] or 0),
                "total_bags": float(roll_row_inner["total_bags"] or 0),
                "total_boxes": float(roll_row_inner["total_boxes"] or 0),
                "total_tins": float(roll_row_inner["total_tins"] or 0),
            },
        }

    ok, maybe = await run_read_budget_bounded(compute_summary)
    if not ok or maybe is None:
        return _degraded_summary_response(su_key)
    payload = _strip_degraded_snapshot_fields(dict(maybe))
    _put_summary_last_good(su_key, payload)
    _trade_summary_cache[su_key] = (monotonic(), payload)
    if len(_trade_summary_cache) > _trade_summary_cache_max:
        _trade_summary_cache.clear()
    return payload


@router.get("/trade-daily-profit")
async def trade_daily_profit_series(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    date_from: date = Query(..., alias="from"),
    date_to: date = Query(..., alias="to"),
) -> list[dict[str, Any]]:
    """Per-calendar-day sum of line profit (same basis as [trade_line_profit_expr]) for charts."""
    del _m
    if date_from > date_to:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail="from_must_not_exceed_to")
    profit_e = tq.trade_line_profit_expr()
    bf = _trade_purchase_date_filter(business_id, date_from, date_to)
    q = (
        select(TradePurchase.purchase_date, func.coalesce(func.sum(profit_e), 0.0))
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(bf)
        .group_by(TradePurchase.purchase_date)
        .order_by(TradePurchase.purchase_date)
    )
    r = await execute_with_retry(lambda: db.execute(q))
    return [{"d": d.isoformat(), "profit": float(p or 0)} for d, p in r.all()]


@router.get("/trade-items")
async def trade_items_breakdown(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    date_from: date = Query(..., alias="from"),
    date_to: date = Query(..., alias="to"),
) -> list[dict[str, Any]]:
    del _m
    return await _fetch_trade_items_breakdown_rows(db, business_id, date_from, date_to)


@router.get("/trade-suppliers")
async def trade_suppliers_breakdown(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    date_from: date = Query(..., alias="from"),
    date_to: date = Query(..., alias="to"),
) -> list[dict[str, Any]]:
    del _m
    return await _trade_suppliers_rows(db, business_id, date_from, date_to)


@router.get("/trade-categories")
async def trade_categories_breakdown(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    date_from: date = Query(..., alias="from"),
    date_to: date = Query(..., alias="to"),
) -> list[dict[str, Any]]:
    del _m
    amt = _trade_line_amount_expr()
    bf = _trade_purchase_date_filter(business_id, date_from, date_to)
    cat_key = func.coalesce(ItemCategory.name, "Uncategorized")
    qty_sum = func.coalesce(func.sum(TradePurchaseLine.qty), 0)
    q = (
        select(
            cat_key.label("category_name"),
            func.count(TradePurchaseLine.id).label("line_count"),
            func.count(func.distinct(TradePurchaseLine.catalog_item_id)).label("item_count"),
            func.coalesce(func.sum(amt), 0).label("total_purchase"),
            qty_sum.label("total_qty"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .outerjoin(
            CatalogItem,
            and_(CatalogItem.id == TradePurchaseLine.catalog_item_id, CatalogItem.deleted_at.is_(None)),
        )
        .outerjoin(ItemCategory, ItemCategory.id == CatalogItem.category_id)
        .where(bf)
        .group_by(cat_key)
        .order_by(func.coalesce(func.sum(amt), 0).desc())
    )
    rows = (await db.execute(q)).mappings().all()
    return [
        {
            "category_name": str(r["category_name"] or "Uncategorized"),
            "category": str(r["category_name"] or "Uncategorized"),
            "line_count": int(r["line_count"] or 0),
            "item_count": int(r["item_count"] or 0),
            "total_purchase": float(r["total_purchase"] or 0),
            "total_profit": 0.0,
            "total_qty": float(r["total_qty"] or 0),
            "type_name": "—",
        }
        for r in rows
    ]


@router.get("/trade-types")
async def trade_types_breakdown(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    date_from: date = Query(..., alias="from"),
    date_to: date = Query(..., alias="to"),
) -> list[dict[str, Any]]:
    """Category → subcategory: spend grouped by CategoryType (catalog `type_id`) with parent category name."""
    del _m
    return await _fetch_trade_types_breakdown_rows(db, business_id, date_from, date_to)


async def _purchase_totals_for_range(
    db: AsyncSession,
    business_id: uuid.UUID,
    date_from: date,
    date_to: date,
) -> dict[str, Any]:
    bf = _trade_purchase_date_filter(business_id, date_from, date_to)
    purchase = await execute_with_retry(
        lambda: db.execute(
            select(func.coalesce(func.sum(_trade_line_amount_expr()), 0))
            .select_from(TradePurchaseLine)
            .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
            .where(bf)
        )
    )
    deals = await execute_with_retry(
        lambda: db.execute(
            select(func.count(TradePurchase.id.distinct()))
            .select_from(TradePurchase)
            .where(bf)
        )
    )
    sups = await execute_with_retry(
        lambda: db.execute(
            select(func.count(TradePurchase.supplier_id.distinct()))
            .select_from(TradePurchase)
            .where(bf)
        )
    )
    kg = await execute_with_retry(
        lambda: db.execute(
            select(func.coalesce(func.sum(tq.trade_line_weight_expr()), 0))
            .select_from(TradePurchaseLine)
            .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
            .where(bf)
        )
    )
    return {
        "total_purchase": float(purchase.scalar() or 0),
        "purchase_count": int(deals.scalar() or 0),
        "supplier_count": int(sups.scalar() or 0),
        "total_kg": float(kg.scalar() or 0),
    }


@router.get("/period-comparison")
async def reports_period_comparison(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    date_from: date = Query(..., alias="from"),
    date_to: date = Query(..., alias="to"),
) -> dict[str, Any]:
    """Current period vs prior equal-length window (purchase value SSOT)."""
    del _m
    span = (date_to - date_from).days + 1
    prior_end = date_from - timedelta(days=1)
    prior_start = prior_end - timedelta(days=span - 1)
    current = await _purchase_totals_for_range(db, business_id, date_from, date_to)
    prior = await _purchase_totals_for_range(db, business_id, prior_start, prior_end)
    cur_p = current["total_purchase"]
    prev_p = prior["total_purchase"]
    pct = None
    if prev_p > 1e-6:
        pct = round(((cur_p - prev_p) / prev_p) * 100, 1)
    return {
        "current": current,
        "prior": prior,
        "purchase_change_pct": pct,
        "prior_from": prior_start.isoformat(),
        "prior_to": prior_end.isoformat(),
    }


@router.get("/movement-summary")
async def reports_movement_summary(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    date_from: date = Query(..., alias="from"),
    date_to: date = Query(..., alias="to"),
) -> dict[str, Any]:
    """Stock adjustment totals by type for the period (no financial totals)."""
    del _m
    start_dt = datetime.combine(date_from, datetime.min.time(), tzinfo=timezone.utc)
    end_dt = datetime.combine(date_to, datetime.max.time(), tzinfo=timezone.utc)
    r = await db.execute(
        select(
            StockAdjustmentLog.adjustment_type,
            func.count(),
            func.coalesce(func.sum(StockAdjustmentLog.new_qty - StockAdjustmentLog.old_qty), 0),
        )
        .where(
            StockAdjustmentLog.business_id == business_id,
            StockAdjustmentLog.updated_at >= start_dt,
            StockAdjustmentLog.updated_at <= end_dt,
        )
        .group_by(StockAdjustmentLog.adjustment_type)
    )
    by_type: dict[str, dict[str, float | int]] = {}
    for adj_type, cnt, delta in r.all():
        key = str(adj_type or "manual")
        by_type[key] = {"count": int(cnt or 0), "qty_delta": float(delta or 0)}
    daily_r = await db.execute(
        select(
            func.date(StockAdjustmentLog.updated_at),
            func.count(),
        )
        .where(
            StockAdjustmentLog.business_id == business_id,
            StockAdjustmentLog.updated_at >= start_dt,
            StockAdjustmentLog.updated_at <= end_dt,
        )
        .group_by(func.date(StockAdjustmentLog.updated_at))
        .order_by(func.date(StockAdjustmentLog.updated_at))
    )
    timeline = [
        {"date": (d.isoformat() if hasattr(d, "isoformat") else str(d)), "events": int(c or 0)}
        for d, c in daily_r.all()
    ]
    return {"by_type": by_type, "timeline": timeline}
