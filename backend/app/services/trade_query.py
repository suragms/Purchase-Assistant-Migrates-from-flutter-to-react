"""Shared trade purchase line queries: value and report status filters."""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import and_, case, func, literal, or_
from sqlalchemy.sql.elements import ColumnElement

from app.models import TradePurchase, TradePurchaseLine


TRADE_STATUS_IN_REPORTS: tuple[str, ...] = (
    "saved",
    "confirmed",
    "paid",
    "partially_paid",
    "overdue",
    "due_soon",
    "active",
    "approved",
    "ordered",
    "supplier_confirmed",
    "in_transit",
    "arrived",
    "verification_pending",
    "verified",
    "added_to_stock",
    "completed",
    "delivered",
)

TRADE_STATUS_EXCLUDED_FROM_REPORTS: tuple[str, ...] = (
    "draft",
    "cancelled",
    "deleted",
)


def trade_purchase_status_in_reports() -> ColumnElement[bool]:
    """Include all committed purchases; exclude draft/cancelled/deleted only."""
    return ~TradePurchase.status.in_(TRADE_STATUS_EXCLUDED_FROM_REPORTS)


def trade_line_amount_expr() -> ColumnElement:
    """Line spend for SQL aggregates (aligned with ``line_totals_service.line_money``).

    **Policy (t07):** Prefer persisted ``trade_purchase_lines.line_total`` — this is the
    tax/discount-inclusive line total the API persists on confirm/preview SSOT paths.

    When ``line_total`` is NULL (legacy imports / partial rows), fall back to the same
    **pre-discount gross** branch used in ``line_gross_base`` / ``trade_line_computed_amount_python``
    (``qty`` × weight-priced amount when weight snapshots agree within 0.05, else ``qty`` ×
    unit landing). This is **not** the full ``line_money`` inclusive path — backfill and
    new writes should populate ``line_total`` so reports match fiscal truth.
    """
    kpu = TradePurchaseLine.kg_per_unit
    lcpk = TradePurchaseLine.landing_cost_per_kg
    # Weight-priced lines are qty * kg_per_unit * landing_cost_per_kg, BUT older
    # clients may send inconsistent snapshots (landing_cost not matching kpu*lcpk).
    # For reports, treat weight pricing as authoritative only when snapshots agree.
    derived_unit_cost = kpu * lcpk
    landing = func.coalesce(TradePurchaseLine.purchase_rate, TradePurchaseLine.landing_cost)
    weight_ok = and_(
        kpu.isnot(None),
        lcpk.isnot(None),
        kpu > 0,
        lcpk > 0,
        landing.isnot(None),
        func.abs(derived_unit_cost - landing) <= 0.05,
    )
    computed = case(
        (weight_ok, TradePurchaseLine.qty * kpu * lcpk),
        else_=TradePurchaseLine.qty
        * landing,
    )
    return func.coalesce(TradePurchaseLine.line_total, computed)


def trade_line_qty_when_unit_type(
    *,
    canonical: str,
    legacy_like_patterns: tuple[str, ...],
) -> ColumnElement:
    """Qty counted toward bag/box/tin rollups using [unit_type] with LIKE fallback for unmigrated rows."""
    ut = TradePurchaseLine.unit_type
    legs = [func.upper(TradePurchaseLine.unit).like(pat) for pat in legacy_like_patterns]
    legacy = legs[0] if len(legs) == 1 else or_(*legs)
    matched = or_(ut == canonical, and_(ut.is_(None), legacy))
    return case((matched, TradePurchaseLine.qty), else_=literal(0.0))


def trade_line_qty_bags_expr() -> ColumnElement:
    return trade_line_qty_when_unit_type(canonical="bag", legacy_like_patterns=("%SACK%", "%BAG%"))


def trade_line_qty_boxes_expr() -> ColumnElement:
    return trade_line_qty_when_unit_type(canonical="box", legacy_like_patterns=("%BOX%",))


def trade_line_qty_tins_expr() -> ColumnElement:
    return trade_line_qty_when_unit_type(canonical="tin", legacy_like_patterns=("%TIN%",))


def trade_line_weight_expr() -> ColumnElement:
    """Physical kg movement for dashboards/reports.

    **BOX/TIN policy (t08):** Wholesale UI treats inventory as count-only for BOX/TIN in
    the current product mode — this expression returns **0 kg** for box/tin lines so
    dashboard ``total_kg`` reflects bag + loose kg only. Pure ``kg`` lines and bag-family
    units still contribute (using ``total_weight`` when set, else ``qty`` × kg-per-unit
    for bags, else raw qty for kg). Changing BOX/TIN rollup requires updating this
    function, ``trade_line_weight_sql_python``, and any dependent labels together.
    """
    kpu = func.coalesce(TradePurchaseLine.weight_per_unit, TradePurchaseLine.kg_per_unit)
    weight_ok = and_(kpu.isnot(None), kpu > 0)
    utype = TradePurchaseLine.unit_type
    is_bag = or_(
        utype == literal("bag"),
        and_(utype.is_(None), func.upper(TradePurchaseLine.unit).like("%BAG%")),
        and_(utype.is_(None), func.upper(TradePurchaseLine.unit).like("%SACK%")),  # legacy
        and_(utype.is_(None), func.upper(TradePurchaseLine.unit).in_(("BG", "BGS"))),
    )
    kg_fallback = or_(
        utype == literal("kg"),
        and_(utype.is_(None), func.upper(TradePurchaseLine.unit).like("%KG%")),
        and_(utype.is_(None), func.upper(TradePurchaseLine.unit).like("%KILO%")),
        and_(utype.is_(None), func.upper(TradePurchaseLine.unit).like("%كيلو%")),
    )
    legacy = case(
        (and_(weight_ok, is_bag), TradePurchaseLine.qty * kpu),
        else_=case((kg_fallback, TradePurchaseLine.qty), else_=literal(0)),
    )
    # Master rebuild default wholesale mode: ignore BOX/TIN weights even if older
    # rows persisted `total_weight`.
    return case(
        (or_(is_bag, kg_fallback), func.coalesce(TradePurchaseLine.total_weight, legacy)),
        else_=literal(0),
    )


def trade_line_selling_expr() -> ColumnElement:
    selling = func.coalesce(TradePurchaseLine.selling_rate, TradePurchaseLine.selling_cost)
    return case(
        (selling.isnot(None), TradePurchaseLine.qty * selling),
        else_=0,
    )


def trade_line_profit_expr() -> ColumnElement:
    return func.coalesce(TradePurchaseLine.profit, trade_line_selling_expr() - trade_line_amount_expr())


def trade_purchase_date_filter(
    business_id: uuid.UUID,
    date_from: date,
    date_to: date,
):
    return and_(
        TradePurchase.business_id == business_id,
        TradePurchase.purchase_date >= date_from,
        TradePurchase.purchase_date <= date_to,
        trade_purchase_status_in_reports(),
    )
