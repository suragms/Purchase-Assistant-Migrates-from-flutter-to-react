"""Business logic for trade purchases (human IDs, duplicates, totals)."""

from __future__ import annotations

import json
import re
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from typing import Any

from sqlalchemy import delete, exists, not_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.db_resilience import execute_with_retry
from app.models import CatalogItem, SupplierItemDefault, TradePurchase, TradePurchaseDraft, TradePurchaseLine
from app.services.trade_unit_type import derive_trade_unit_type
from app.schemas.trade_purchases import (
    TradeDuplicateCheckRequest,
    TradeDuplicateCheckResponse,
    TradeDraftOut,
    TradeMarkPaidRequest,
    TradePurchaseCreateRequest,
    TradePurchaseLineIn,
    TradePurchaseLineOut,
    StockUpdateOut,
    TradePurchaseOut,
    TradePurchaseDeliveryPatch,
    TradePurchaseVerifyIn,
    TradePurchasePaymentPatch,
    TradePurchaseUpdateRequest,
)
from app.read_cache_generation import bump_trade_read_caches_for_business
from app.services import decimal_precision as dp
from app.services.stock_inventory import (
    apply_confirmed_purchase_stock,
    revert_confirmed_purchase_stock,
    sync_confirmed_purchase_stock_diff,
)
from app.services.purchase_line_unit_validation import validate_purchase_line_unit
from app.services.unit_normalization import fetch_catalog_items_map, line_qty_in_stock_unit


def _line_tax_mode(li: TradePurchaseLineIn) -> str:
    tm = (getattr(li, "tax_mode", None) or "exclusive").strip().lower()
    return tm if tm in ("exclusive", "inclusive", "none") else "exclusive"
from app.services.aggregate_totals_service import aggregate_landing_selling_profit
from app.services.line_totals_service import (
    line_gross_base as _line_gross_base,
    line_item_freight_charges,
    line_money as _line_money,
    line_profit as _line_profit,
    line_total_weight as _line_total_weight,
)
from app.services.purchase_status import compute_status
from app.services.rate_display_context import build_rate_context, validate_rate_label_consistency
from app.services.trade_query import trade_purchase_status_in_reports
from app.services.unit_resolution_service import resolve_from_text


class TradePurchaseValidationError(Exception):
    """Structured validation failures (FastAPI maps to HTTP 422)."""

    def __init__(self, details: list[dict[str, Any]]) -> None:
        self.details = details


DUPLICATE_PURCHASE_DETECTED_CODE = "DUPLICATE_PURCHASE_DETECTED"


class TradePurchaseDuplicateError(Exception):
    """Another purchase matches supplier, date, lines, and total (within tolerance)."""

    def __init__(
        self,
        *,
        existing_id: uuid.UUID,
        existing_human_id: str,
        message: str = "DUPLICATE_PURCHASE_DETECTED",
    ) -> None:
        self.code = DUPLICATE_PURCHASE_DETECTED_CODE
        self.existing_id = existing_id
        self.existing_human_id = existing_human_id
        self.message = message


# Purchases with these statuses are ignored for duplicate matching and excluded from duplicates.
_STATUS_EXCLUDED_FROM_DUP_MATCH: frozenset[str] = frozenset({"deleted", "cancelled"})
_DUP_TOTAL_TOLERANCE = Decimal(
    "1.0"
)  # ₹ — header total_amount may differ slightly from fingerprinted line math
_DUP_QTY_EPS = Decimal("0.02")
_DUP_RATE_EPS = Decimal("0.05")  # ₹ per unit rate comparison (landing or per-kg)


_UNIT_PATTERN = re.compile(r"^[a-z][a-z0-9\- ]{0,31}$")


def _collect_trade_purchase_validation_errors(
    body: TradePurchaseCreateRequest,
    *,
    for_preview: bool = False,
) -> list[dict[str, Any]]:
    """Post-schema checks: permissive units + authoritative line gross.

    When ``for_preview`` is true, skip the line-gross > 0 rule so the wizard can
    debounce-preview while the user is still entering rates/weights.
    """
    errs: list[dict[str, Any]] = []
    if not body.lines:
        errs.append({"loc": ["body", "lines"], "msg": "At least one line item is required"})
        return errs
    status_l = (body.status or "").lower()
    enforce_gross = (not for_preview) and status_l in {"confirmed", "saved", "draft"}
    for i, li in enumerate(body.lines):
        base: list[Any] = ["body", "lines", i]
        if not (li.item_name or "").strip():
            errs.append({"loc": [*base, "item_name"], "msg": "item name is required"})
        u = (li.unit or "").strip().lower()
        if not u:
            errs.append({"loc": [*base, "unit"], "msg": "unit is required"})
        elif not _UNIT_PATTERN.match(u):
            errs.append({"loc": [*base, "unit"], "msg": "invalid unit"})
        if li.qty <= 0:
            errs.append({"loc": [*base, "qty"], "msg": "quantity must be greater than 0"})
        if enforce_gross:
            gross = _line_gross_base(li)
            if gross <= 0:
                errs.append(
                    {
                        "loc": [*base, "landing_cost"],
                        "msg": "line gross (qty × weight × rates) must be greater than 0",
                    }
                )
    return errs


async def _collect_line_unit_profile_errors(
    db: AsyncSession,
    business_id: uuid.UUID,
    lines: list[TradePurchaseLineIn],
) -> list[dict[str, Any]]:
    """Block bag/piece mismatches per catalog stock-tracking profile."""
    item_ids = {li.catalog_item_id for li in lines if li.catalog_item_id}
    items = await fetch_catalog_items_map(db, business_id, item_ids)
    errs: list[dict[str, Any]] = []
    for i, li in enumerate(lines):
        item = items.get(li.catalog_item_id)
        if not item:
            continue
        msg = validate_purchase_line_unit(item, li.unit)
        if msg:
            errs.append({"loc": ["body", "lines", i, "unit"], "msg": msg})
    return errs


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _trade_purchase_load_opts() -> tuple:
    return (
        selectinload(TradePurchase.lines).selectinload(TradePurchaseLine.catalog_item),
        selectinload(TradePurchase.supplier_row),
        selectinload(TradePurchase.broker_row),
    )


def _due_date_from(purchase_date: date, payment_days: int | None) -> date | None:
    if payment_days is None:
        return None
    return purchase_date + timedelta(days=int(payment_days))


def _dec(x) -> Decimal:
    return dp.dec(x)


def _line_fp(
    name: str,
    qty,
    landing,
    discount,
    tax_percent,
    kg_per_unit=None,
    per_kg=None,
) -> str:
    q = dp.qty(qty)
    land = dp.rate(landing)
    d = dp.percent(discount or 0)
    t = dp.percent(tax_percent or 0)
    kpu = dp.weight(kg_per_unit or 0)
    pk = dp.rate(per_kg or 0)
    return f"{name.strip().lower()}|{q:f}|{land:f}|{d:f}|{t:f}|{kpu:f}|{pk:f}"


def _fingerprint_lines_from_lines(lines: list[TradePurchaseLine]) -> str:
    parts = sorted(
        _line_fp(
            li.item_name,
            li.qty,
            li.landing_cost,
            li.discount,
            li.tax_percent,
            getattr(li, "kg_per_unit", None),
            getattr(li, "landing_cost_per_kg", None),
        )
        for li in lines
    )
    return "|".join(parts)


def _fingerprint_lines_from_in(lines: list[TradePurchaseLineIn]) -> str:
    parts = sorted(
        _line_fp(
            li.item_name,
            li.qty,
            li.landing_cost,
            li.discount,
            li.tax_percent,
            li.kg_per_unit,
            li.landing_cost_per_kg,
        )
        for li in lines
    )
    return "|".join(parts)


def _line_key_and_rates_in(li: TradePurchaseLineIn) -> tuple[str, Decimal, Decimal]:
    """Stable key (catalog + name) + qty + comparable unit rate for fuzzy duplicate detection."""
    key = f"{li.catalog_item_id}|{(li.item_name or '').strip().lower()}"
    q = dp.qty(li.qty)
    if li.kg_per_unit is not None and li.landing_cost_per_kg is not None:
        rate = dp.rate(li.landing_cost_per_kg)
    else:
        rate = dp.rate(li.landing_cost)
    return key, q, rate


def _line_key_and_rates_db(li: TradePurchaseLine) -> tuple[str, Decimal, Decimal]:
    key = f"{li.catalog_item_id}|{(li.item_name or '').strip().lower()}"
    q = dp.qty(li.qty)
    kpu = getattr(li, "kg_per_unit", None) or getattr(li, "weight_per_unit", None)
    lpk = getattr(li, "landing_cost_per_kg", None)
    if kpu is not None and lpk is not None:
        rate = dp.rate(lpk)
    else:
        rate = dp.rate(li.landing_cost)
    return key, q, rate


def _fingerprint_approx_match(
    lines_in: list[TradePurchaseLineIn], db_lines: list[TradePurchaseLine]
) -> bool:
    """Same items (catalog + name), qty and rate within small tolerance."""
    if len(lines_in) != len(db_lines):
        return False
    pairs_in = sorted(_line_key_and_rates_in(li) for li in lines_in)
    pairs_db = sorted(_line_key_and_rates_db(li) for li in db_lines)
    for (k1, q1, r1), (k2, q2, r2) in zip(pairs_in, pairs_db, strict=True):
        if k1 != k2:
            return False
        if abs(q1 - q2) > _DUP_QTY_EPS:
            return False
        if abs(r1 - r2) > _DUP_RATE_EPS:
            return False
    return True


async def find_matching_duplicate_trade_purchase(
    db: AsyncSession,
    business_id: uuid.UUID,
    *,
    supplier_id: uuid.UUID | None,
    purchase_date: date,
    lines: list[TradePurchaseLineIn],
    target_total: Decimal,
    exclude_purchase_id: uuid.UUID | None = None,
) -> TradePurchase | None:
    # v2 heuristic signals (in addition to exact fingerprint match):
    # - total amount proximity (existing)
    # - total kg proximity (bags + kg only; BOX/TIN count-only)
    # - Jaccard overlap of catalog items
    def _in_total_kg(lines_in: list[TradePurchaseLineIn]) -> Decimal:
        return dp.total_weight(sum((_line_total_weight(li) for li in lines_in), Decimal("0")))

    def _db_total_kg(lines_db: list[TradePurchaseLine]) -> Decimal:
        # Prefer stored total_weight when present; treat BOX/TIN as zero kg.
        tot = Decimal("0")
        for li in lines_db:
            u = (li.unit or "").strip().lower()
            if u == "kg":
                tot += _dec(li.qty)
            elif u == "bag":
                kpu = getattr(li, "weight_per_unit", None) or getattr(li, "kg_per_unit", None)
                if kpu is not None:
                    tot += _dec(li.qty) * _dec(kpu)
            # box/tin count-only: ignore
        return dp.total_weight(tot)

    def _jaccard_catalog(lines_in: list[TradePurchaseLineIn], lines_db: list[TradePurchaseLine]) -> float:
        a = {str(li.catalog_item_id) for li in lines_in if li.catalog_item_id is not None}
        b = {str(li.catalog_item_id) for li in lines_db if getattr(li, "catalog_item_id", None) is not None}
        if not a or not b:
            return 0.0
        inter = len(a & b)
        union = len(a | b)
        return (inter / union) if union else 0.0

    in_kg = _in_total_kg(lines)
    q = (
        select(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.purchase_date == purchase_date,
            not_(TradePurchase.status.in_(tuple(_STATUS_EXCLUDED_FROM_DUP_MATCH))),
        )
        .options(selectinload(TradePurchase.lines))
    )
    if supplier_id is not None:
        q = q.where(TradePurchase.supplier_id == supplier_id)
    else:
        q = q.where(TradePurchase.supplier_id.is_(None))
    if exclude_purchase_id is not None:
        q = q.where(TradePurchase.id != exclude_purchase_id)
    res = await db.execute(q)
    for p in res.scalars().unique().all():
        if abs(_dec(p.total_amount) - _dec(target_total)) > _DUP_TOTAL_TOLERANCE:
            continue
        dbl = list(p.lines or [])
        if _fingerprint_lines_from_in(lines) == _fingerprint_lines_from_lines(dbl):
            return p
        if _fingerprint_approx_match(lines, dbl):
            return p
        # v2 fuzzy: kg + catalog overlap.
        try:
            db_kg = _db_total_kg(dbl)
            kg_close = abs(_dec(db_kg) - _dec(in_kg)) <= Decimal("5")
            jac = _jaccard_catalog(lines, dbl)
            if kg_close and jac >= 0.66:
                return p
        except Exception:  # noqa: BLE001
            pass
    return None


def _purchase_has_missing_optional_details(tp: TradePurchase) -> bool:
    """True when follow-up header fields expected by UX are unset (None only)."""
    if tp.broker_id is None:
        return True
    if tp.payment_days is None:
        return True
    if tp.discount is None:
        return True
    if tp.freight_amount is None:
        return True
    ft = getattr(tp, "freight_type", None)
    if ft is None or str(ft).strip() == "":
        return True
    return False


def _line_item_charges(li: TradePurchaseLineIn, req: TradePurchaseCreateRequest) -> Decimal:
    """Per-line freight/charges (``req`` reserved for future header coupling)."""
    del req
    return line_item_freight_charges(li)


def _strip_disallowed_fields_for_default_wholesale_mode(
    li: TradePurchaseLineIn,
) -> TradePurchaseLineIn:
    """Enforce master rebuild default rules for BOX/TIN count-only units.

    In default wholesale mode, BOX/TIN do not track kg or per-pack weights.
    We therefore drop any weight-related fields to prevent accidental kg math
    or persistence of advanced-inventory fields.
    """
    unit = (li.unit or "").strip().upper()
    if unit == "BOX":
        return li.model_copy(
            update={
                "kg_per_unit": None,
                "weight_per_unit": None,
                "landing_cost_per_kg": None,
                "box_mode": None,
                "items_per_box": None,
                "weight_per_item": None,
                "kg_per_box": None,
            }
        )
    if unit == "TIN":
        return li.model_copy(
            update={
                "kg_per_unit": None,
                "weight_per_unit": None,
                "landing_cost_per_kg": None,
                "weight_per_tin": None,
            }
        )
    return li


def normalize_trade_line_for_preview(li: TradePurchaseLineIn) -> TradePurchaseLineIn:
    """BOX/TIN wholesale stripping; must match ``create_trade_purchase`` before line totals."""
    return _strip_disallowed_fields_for_default_wholesale_mode(li)


def collect_trade_purchase_validation_errors(
    body: TradePurchaseCreateRequest,
) -> list[dict[str, Any]]:
    """Full save/create validation (same as ``create_trade_purchase``)."""
    return _collect_trade_purchase_validation_errors(body, for_preview=False)


def collect_trade_purchase_preview_errors(
    body: TradePurchaseCreateRequest,
) -> list[dict[str, Any]]:
    """Relaxed validation for debounced wizard preview (skips line-gross > 0)."""
    return _collect_trade_purchase_validation_errors(body, for_preview=True)


def _header_commission_rupees(req: TradePurchaseCreateRequest, after_header: Decimal) -> Decimal:
    """Broker commission added to purchase total (matches Flutter `headerCommissionAddOn`)."""
    mode = (req.commission_mode or "percent").strip().lower()
    if mode not in ("percent", "flat_invoice", "flat_kg", "flat_bag", "flat_box", "flat_tin"):
        mode = "percent"
    if mode == "percent":
        comm = _dec(req.commission_percent) if req.commission_percent is not None else Decimal("0")
        if comm <= 0:
            return Decimal("0")
        return dp.total(after_header * dp.clamp_percent(comm) / Decimal("100"))
    money = _dec(req.commission_money) if req.commission_money is not None else Decimal("0")
    if money <= 0:
        return Decimal("0")
    if mode == "flat_invoice":
        return dp.total(money)
    if mode == "flat_kg":
        total_kg = Decimal("0")
        for li in req.lines:
            total_kg += _line_total_weight(li)
        if total_kg <= 0:
            return Decimal("0")
        return dp.total(money * total_kg)
    if mode == "flat_bag":
        bags = Decimal("0")
        for li in req.lines:
            u = (li.unit or "").strip().lower()
            if u in ("bag", "sack"):
                bags += _dec(li.qty)
        if bags <= 0:
            return Decimal("0")
        return dp.total(money * bags)
    if mode == "flat_box":
        boxes = Decimal("0")
        for li in req.lines:
            u = (li.unit or "").strip().lower()
            if u == "box":
                boxes += _dec(li.qty)
        if boxes <= 0:
            return Decimal("0")
        return dp.total(money * boxes)
    if mode == "flat_tin":
        tins = Decimal("0")
        for li in req.lines:
            u = (li.unit or "").strip().lower()
            if u == "tin":
                tins += _dec(li.qty)
        if tins <= 0:
            return Decimal("0")
        return dp.total(money * tins)
    return Decimal("0")


def compute_totals(req: TradePurchaseCreateRequest) -> tuple[Decimal, Decimal]:
    qty_sum = sum(_dec(li.qty) for li in req.lines)
    has_item_level_charges = any(
        li.freight_value is not None or li.delivered_rate is not None or li.billty_rate is not None
        for li in req.lines
    )
    amt_sum = sum((_line_money(li) + _line_item_charges(li, req)) for li in req.lines)
    header_disc = _dec(req.discount) if req.discount is not None else Decimal("0")
    after_header = amt_sum
    if header_disc > 0:
        after_header = amt_sum * (Decimal("1") - dp.clamp_percent(header_disc) / Decimal("100"))
    amt_sum = after_header
    if not has_item_level_charges:
        freight = _dec(req.freight_amount) if req.freight_amount is not None else Decimal("0")
        if req.freight_type == "included":
            freight = Decimal("0")
        amt_sum += freight
    comm_amt = _header_commission_rupees(req, after_header)
    if comm_amt > 0:
        amt_sum += comm_amt
    if not has_item_level_charges:
        # Fixed-rupee header charges kept for compatibility with existing rows/clients.
        billty = _dec(req.billty_rate) if req.billty_rate is not None else Decimal("0")
        delivered = _dec(req.delivered_rate) if req.delivered_rate is not None else Decimal("0")
        amt_sum += billty + delivered
    return dp.qty(qty_sum), dp.total(amt_sum)


async def _sync_purchase_memory(
    db: AsyncSession,
    business_id: uuid.UUID,
    body: TradePurchaseCreateRequest,
    *,
    trade_purchase_id: uuid.UUID | None = None,
) -> None:
    """Update item master last price, optional last-trade snapshot, and supplier-item defaults."""
    snap = (
        trade_purchase_id is not None
        and body.supplier_id is not None
        and (body.status or "confirmed").lower() == "confirmed"
    )
    for li in body.lines:
        if li.catalog_item_id is None:
            continue
        ir = await db.execute(
            select(CatalogItem).where(
                CatalogItem.id == li.catalog_item_id,
                CatalogItem.business_id == business_id,
            )
        )
        item = ir.scalar_one_or_none()
        if item is not None:
            item.last_purchase_price = dp.rate(li.landing_cost)
            if snap:
                wt = _line_total_weight(li)
                sell_raw = li.selling_rate if li.selling_rate is not None else None
                item.last_selling_rate = dp.rate(sell_raw) if sell_raw is not None else None
                item.last_supplier_id = body.supplier_id
                item.last_broker_id = body.broker_id
                item.last_trade_purchase_id = trade_purchase_id
                item.last_line_qty = dp.qty(li.qty)
                u = (li.unit or "").strip()
                item.last_line_unit = u[:32] if u else None
                item.last_line_weight_kg = wt if wt > 0 else None
        if body.supplier_id is None:
            continue
        dr = await db.execute(
            select(SupplierItemDefault).where(
                SupplierItemDefault.business_id == business_id,
                SupplierItemDefault.supplier_id == body.supplier_id,
                SupplierItemDefault.catalog_item_id == li.catalog_item_id,
            )
        )
        row = dr.scalar_one_or_none()
        line_pd = li.payment_days if li.payment_days is not None else body.payment_days
        if row is None:
            db.add(
                SupplierItemDefault(
                    business_id=business_id,
                    supplier_id=body.supplier_id,
                    catalog_item_id=li.catalog_item_id,
                    last_price=dp.rate(li.landing_cost),
                    last_discount=dp.percent(li.discount) if li.discount is not None else None,
                    last_payment_days=line_pd,
                    purchase_count=1,
                )
            )
        else:
            row.purchase_count = int(row.purchase_count or 0) + 1
            row.last_price = dp.rate(li.landing_cost)
            if li.discount is not None:
                row.last_discount = dp.percent(li.discount)
            if line_pd is not None:
                row.last_payment_days = line_pd


async def next_human_id(db: AsyncSession, business_id: uuid.UUID) -> str:
    year = date.today().year
    prefix = f"PUR-{year}-"
    q = await db.execute(
        select(TradePurchase.human_id).where(
            TradePurchase.business_id == business_id,
            TradePurchase.human_id.like(f"{prefix}%"),
        )
    )
    best = 0
    for (hid,) in q.all():
        if not isinstance(hid, str) or not hid.startswith(prefix):
            continue
        tail = hid.removeprefix(prefix)
        try:
            best = max(best, int(tail))
        except ValueError:
            continue
    return f"{prefix}{best + 1:04d}"


async def check_duplicate(
    db: AsyncSession,
    business_id: uuid.UUID,
    body: TradeDuplicateCheckRequest,
) -> TradeDuplicateCheckResponse:
    target_total = _dec(body.total_amount)
    dup = await find_matching_duplicate_trade_purchase(
        db,
        business_id,
        supplier_id=body.supplier_id,
        purchase_date=body.purchase_date,
        lines=body.lines,
        target_total=target_total,
    )
    if dup is not None:
        return TradeDuplicateCheckResponse(
            duplicate=True,
            message="A purchase with the same lines and total already exists for this date.",
            existing_id=dup.id,
            existing_human_id=dup.human_id,
        )
    return TradeDuplicateCheckResponse(
        duplicate=False, message=None, existing_id=None, existing_human_id=None
    )


async def list_trade_purchases(
    db: AsyncSession,
    business_id: uuid.UUID,
    limit: int = 100,
    *,
    offset: int = 0,
    status_filter: str | None = None,
    q: str | None = None,
    supplier_id: uuid.UUID | None = None,
    broker_id: uuid.UUID | None = None,
    catalog_item_id: uuid.UUID | None = None,
    purchase_from: date | None = None,
    purchase_to: date | None = None,
    reports_eligible_only: bool = False,
) -> list[TradePurchaseOut]:
    """List purchases; optional status_filter: all|draft|due_soon|overdue|paid and search q.

    When ``reports_eligible_only`` is True, restrict to the same status set as dashboards
    and trade reports (excludes deleted, draft, cancelled, etc.).
    """
    has_entity_filter = (
        supplier_id is not None or broker_id is not None or catalog_item_id is not None
    )
    if has_entity_filter:
        fetch_cap = min(max(limit, 1), 500)
    else:
        fetch_cap = (
            min(max(limit * 5, limit), 500)
            if (status_filter and status_filter != "all") or q
            else min(limit, 500)
        )
    stmt = (
        select(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.status != "deleted",
        )
        .options(*_trade_purchase_load_opts())
        .order_by(TradePurchase.purchase_date.desc(), TradePurchase.created_at.desc())
    )
    if reports_eligible_only:
        stmt = stmt.where(trade_purchase_status_in_reports())
    if supplier_id is not None:
        stmt = stmt.where(TradePurchase.supplier_id == supplier_id)
    if broker_id is not None:
        stmt = stmt.where(TradePurchase.broker_id == broker_id)
    if purchase_from is not None:
        stmt = stmt.where(TradePurchase.purchase_date >= purchase_from)
    if purchase_to is not None:
        stmt = stmt.where(TradePurchase.purchase_date <= purchase_to)
    if catalog_item_id is not None:
        stmt = stmt.where(
            exists(
                select(1).where(
                    TradePurchaseLine.trade_purchase_id == TradePurchase.id,
                    TradePurchaseLine.catalog_item_id == catalog_item_id,
                )
            )
        )
    off = min(max(int(offset or 0), 0), 10_000)
    stmt = stmt.offset(off).limit(fetch_cap)
    res = await execute_with_retry(lambda: db.execute(stmt))
    rows = [trade_purchase_to_out(p) for p in res.scalars().unique().all()]
    sf = (status_filter or "all").strip().lower()
    if sf == "draft":
        rows = [r for r in rows if (r.status or "").lower() in ("draft", "saved")]
    elif sf == "due_soon":
        rows = [r for r in rows if r.derived_status == "due_soon"]
    elif sf == "overdue":
        rows = [r for r in rows if r.derived_status == "overdue"]
    elif sf == "paid":
        rows = [r for r in rows if r.derived_status == "paid"]
    needle = (q or "").strip().lower()
    if needle:
        out: list[TradePurchaseOut] = []
        for r in rows:
            if needle in (r.human_id or "").lower():
                out.append(r)
                continue
            if needle in (r.supplier_name or "").lower():
                out.append(r)
                continue
            if needle in (r.broker_name or "").lower():
                out.append(r)
                continue
            for li in r.lines:
                if needle in (li.item_name or "").lower():
                    out.append(r)
                    break
        rows = out
    return rows[: min(limit, 500)]


async def get_trade_purchase(
    db: AsyncSession, business_id: uuid.UUID, purchase_id: uuid.UUID
) -> TradePurchaseOut | None:
    res = await db.execute(
        select(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.id == purchase_id,
        )
        .options(*_trade_purchase_load_opts())
    )
    p = res.scalar_one_or_none()
    return trade_purchase_to_out(p) if p else None


async def last_purchase_defaults(
    db: AsyncSession,
    business_id: uuid.UUID,
    *,
    catalog_item_id: uuid.UUID,
    supplier_id: uuid.UUID | None = None,
    broker_id: uuid.UUID | None = None,
) -> dict:
    """Last-record lookup for purchase autofill.

    Priority (trade purchases only — no catalog fallbacks):
    1. supplier + broker + item
    2. supplier + item
    3. latest trade line for item (any supplier)
    """

    async def find_line(*, use_supplier: bool, use_broker: bool):
        stmt = (
            select(TradePurchaseLine, TradePurchase)
            .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
            .where(
                TradePurchase.business_id == business_id,
                TradePurchaseLine.catalog_item_id == catalog_item_id,
                TradePurchase.status.in_(("saved", "confirmed", "paid", "partially_paid", "overdue", "due_soon")),
            )
            .order_by(TradePurchase.purchase_date.desc(), TradePurchase.created_at.desc())
            .limit(1)
        )
        if use_supplier and supplier_id is not None:
            stmt = stmt.where(TradePurchase.supplier_id == supplier_id)
        if use_broker and broker_id is not None:
            stmt = stmt.where(TradePurchase.broker_id == broker_id)
        row = (await db.execute(stmt)).first()
        return row

    row = None
    source = "none"
    if supplier_id is not None and broker_id is not None:
        row = await find_line(use_supplier=True, use_broker=True)
        if row is not None:
            source = "supplier_broker_item"
    if row is None and supplier_id is not None:
        row = await find_line(use_supplier=True, use_broker=False)
        if row is not None:
            source = "supplier_item"
    if row is None:
        row = await find_line(use_supplier=False, use_broker=False)
        if row is not None:
            source = "item_global_last_trade"
    if row is not None:
        li, p = row
        kpu_raw = getattr(li, "weight_per_unit", None) or li.kg_per_unit
        kpu = dp.weight(kpu_raw) if kpu_raw is not None else None
        lcpk_dec = dp.rate(li.landing_cost_per_kg) if li.landing_cost_per_kg is not None else None
        # Per-bag (line unit) rupees — what the Flutter ₹/bag field expects.
        purchase_rate = dp.rate(getattr(li, "purchase_rate", None) or li.landing_cost)
        selling_raw = getattr(li, "selling_rate", None) or li.selling_cost
        selling_rate = dp.rate(selling_raw) if selling_raw is not None else None
        tax_pct = dp.percent(li.tax_percent) if li.tax_percent is not None else None
        sup = getattr(p, "supplier_row", None)
        supplier_name = sup.name if sup is not None else None
        return {
            "source": source,
            "purchase_id": str(p.id),
            "purchase_date": p.purchase_date.isoformat(),
            "payment_days": p.payment_days,
            "broker_id": str(p.broker_id) if p.broker_id is not None else None,
            "supplier_name": supplier_name,
            "item_id": str(li.catalog_item_id),
            "unit": li.unit,
            "purchase_rate": purchase_rate,
            "landing_cost": purchase_rate,
            "landing_cost_per_kg": float(lcpk_dec) if lcpk_dec is not None else None,
            "selling_rate": selling_rate,
            "selling_cost": selling_rate,
            "weight_per_unit": kpu,
            "kg_per_unit": kpu,
            "tax_percent": tax_pct,
            "delivered_rate": dp.money(p.delivered_rate) if p.delivered_rate is not None else None,
            "billty_rate": dp.money(p.billty_rate) if p.billty_rate is not None else None,
            "freight_type": p.freight_type or "separate",
            "freight_value": dp.money(getattr(li, "freight_value", None))
            if getattr(li, "freight_value", None) is not None
            else (dp.money(p.freight_amount) if p.freight_amount is not None else None),
            "freight_amount": dp.money(getattr(li, "freight_value", None))
            if getattr(li, "freight_value", None) is not None
            else (dp.money(p.freight_amount) if p.freight_amount is not None else None),
            "box_mode": getattr(li, "box_mode", None),
            "items_per_box": dp.qty(getattr(li, "items_per_box", None)) if getattr(li, "items_per_box", None) is not None else None,
            "weight_per_item": dp.weight(getattr(li, "weight_per_item", None)) if getattr(li, "weight_per_item", None) is not None else None,
            "kg_per_box": dp.weight(getattr(li, "kg_per_box", None)) if getattr(li, "kg_per_box", None) is not None else None,
            "weight_per_tin": dp.weight(getattr(li, "weight_per_tin", None)) if getattr(li, "weight_per_tin", None) is not None else None,
        }

    return {"source": "none"}


async def create_trade_purchase(
    db: AsyncSession,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    body: TradePurchaseCreateRequest,
) -> TradePurchaseOut:
    errs = _collect_trade_purchase_validation_errors(body)
    unit_errs = await _collect_line_unit_profile_errors(db, business_id, body.lines)
    errs = errs + unit_errs
    if errs:
        raise TradePurchaseValidationError(errs)
    initial_status = body.status if body.status in ("draft", "saved", "confirmed") else "confirmed"
    if initial_status == "confirmed":
        if body.supplier_id is None:
            raise TradePurchaseValidationError(
                [{"loc": ["body", "supplier_id"], "msg": "supplier is required for confirmed purchases"}]
            )
    qty_sum, amt_sum = compute_totals(body)
    land_s, sell_s, prof = aggregate_landing_selling_profit(body)
    if not body.force_duplicate:
        dup_p = await find_matching_duplicate_trade_purchase(
            db,
            business_id,
            supplier_id=body.supplier_id,
            purchase_date=body.purchase_date,
            lines=body.lines,
            target_total=dp.total(amt_sum),
        )
        if dup_p is not None:
            raise TradePurchaseDuplicateError(
                existing_id=dup_p.id,
                existing_human_id=dup_p.human_id or "",
                message=DUPLICATE_PURCHASE_DETECTED_CODE,
            )

    human_id = await next_human_id(db, business_id)
    due = _due_date_from(body.purchase_date, body.payment_days)
    inv = (body.invoice_number.strip() if body.invoice_number else None) or None
    tp = TradePurchase(
        business_id=business_id,
        user_id=user_id,
        human_id=human_id,
        invoice_number=inv,
        purchase_date=body.purchase_date,
        supplier_id=body.supplier_id,
        broker_id=body.broker_id,
        payment_days=body.payment_days,
        due_date=due,
        paid_amount=dp.money(0),
        paid_at=None,
        discount=dp.percent(body.discount) if body.discount is not None else None,
        commission_percent=dp.percent(body.commission_percent)
        if body.commission_percent is not None
        else None,
        commission_mode=body.commission_mode,
        commission_money=dp.money(body.commission_money) if body.commission_money is not None else None,
        delivered_rate=dp.money(body.delivered_rate) if body.delivered_rate is not None else None,
        billty_rate=dp.money(body.billty_rate) if body.billty_rate is not None else None,
        freight_amount=dp.money(body.freight_amount) if body.freight_amount is not None else None,
        freight_type=body.freight_type,
        total_qty=dp.qty(qty_sum),
        total_amount=dp.total(amt_sum),
        total_landing_subtotal=land_s,
        total_selling_subtotal=sell_s,
        total_line_profit=prof,
        status=initial_status,
    )
    db.add(tp)
    await db.flush()
    line_item_ids = {li.catalog_item_id for li in body.lines if li.catalog_item_id}
    catalog_by_id = await fetch_catalog_items_map(db, business_id, line_item_ids)
    for li in body.lines:
        li = _strip_disallowed_fields_for_default_wholesale_mode(li)
        line_total = _line_money(li)
        line_weight = _line_total_weight(li)
        # Profit uses `li` only for selling_rate; safe to reuse normalized line.
        line_profit = _line_profit(li, body)
        cat_item = catalog_by_id.get(li.catalog_item_id)
        qty_su = line_qty_in_stock_unit(li, cat_item) if cat_item else dp.qty(li.qty)
        db.add(
            TradePurchaseLine(
                trade_purchase_id=tp.id,
                catalog_item_id=li.catalog_item_id,
                item_name=li.item_name,
                qty=dp.qty(li.qty),
                unit=li.unit,
                qty_in_stock_unit=qty_su,
                unit_type=derive_trade_unit_type(li.unit),
                purchase_rate=dp.rate(li.purchase_rate or li.landing_cost),
                selling_rate=dp.rate(li.selling_rate) if li.selling_rate is not None else None,
                freight_type=li.freight_type,
                freight_value=dp.money(li.freight_value) if li.freight_value is not None else None,
                delivered_rate=dp.money(li.delivered_rate) if li.delivered_rate is not None else None,
                billty_rate=dp.money(li.billty_rate) if li.billty_rate is not None else None,
                weight_per_unit=dp.weight(li.weight_per_unit) if li.weight_per_unit is not None else None,
                total_weight=line_weight if line_weight > 0 else None,
                line_total=line_total,
                profit=line_profit,
                box_mode=li.box_mode,
                items_per_box=dp.qty(li.items_per_box) if li.items_per_box is not None else None,
                weight_per_item=dp.weight(li.weight_per_item) if li.weight_per_item is not None else None,
                kg_per_box=dp.weight(li.kg_per_box) if li.kg_per_box is not None else None,
                weight_per_tin=dp.weight(li.weight_per_tin) if li.weight_per_tin is not None else None,
                landing_cost=dp.rate(li.landing_cost),
                kg_per_unit=dp.weight(li.kg_per_unit) if li.kg_per_unit is not None else None,
                landing_cost_per_kg=dp.rate(li.landing_cost_per_kg)
                if li.landing_cost_per_kg is not None
                else None,
                selling_cost=dp.rate(li.selling_cost) if li.selling_cost is not None else None,
                discount=dp.percent(li.discount) if li.discount is not None else None,
                tax_percent=dp.percent(li.tax_percent) if li.tax_percent is not None else None,
                tax_mode=_line_tax_mode(li),
                payment_days=li.payment_days,
                hsn_code=(li.hsn_code.strip() if (li.hsn_code and li.hsn_code.strip()) else None),
                item_code=(li.item_code.strip() if (li.item_code and str(li.item_code).strip()) else None),
                description=(li.description.strip() if (li.description and li.description.strip()) else None),
            )
        )
    await _sync_purchase_memory(db, business_id, body, trade_purchase_id=tp.id)
    await db.commit()
    bump_trade_read_caches_for_business(business_id)
    res = await db.execute(
        select(TradePurchase)
        .where(TradePurchase.id == tp.id)
        .options(*_trade_purchase_load_opts())
    )
    loaded = res.scalar_one()
    return trade_purchase_to_out(loaded, stock_updates=[])


async def update_trade_purchase(
    db: AsyncSession,
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    body: TradePurchaseUpdateRequest,
) -> TradePurchaseOut | None:
    errs = _collect_trade_purchase_validation_errors(body)
    unit_errs = await _collect_line_unit_profile_errors(db, business_id, body.lines)
    errs = errs + unit_errs
    if errs:
        raise TradePurchaseValidationError(errs)
    new_status = body.status if body.status in ("draft", "saved", "confirmed") else "confirmed"
    if new_status == "confirmed":
        if body.supplier_id is None:
            raise TradePurchaseValidationError(
                [{"loc": ["body", "supplier_id"], "msg": "supplier is required for confirmed purchases"}]
            )
    res = await db.execute(
        select(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.id == purchase_id,
        )
        .options(selectinload(TradePurchase.lines))
    )
    tp = res.scalar_one_or_none()
    if not tp:
        return None
    if (tp.status or "").lower() == "deleted":
        raise ValueError("Cannot edit a deleted purchase")
    if (tp.status or "").lower() == "cancelled":
        raise ValueError("Cannot edit a cancelled purchase")
    old_lines_snapshot = list(tp.lines)
    was_delivered = bool(getattr(tp, "is_delivered", False))
    qty_sum, amt_sum = compute_totals(body)
    land_s, sell_s, prof = aggregate_landing_selling_profit(body)
    if not body.force_duplicate:
        dup_p = await find_matching_duplicate_trade_purchase(
            db,
            business_id,
            supplier_id=body.supplier_id,
            purchase_date=body.purchase_date,
            lines=body.lines,
            target_total=dp.total(amt_sum),
            exclude_purchase_id=purchase_id,
        )
        if dup_p is not None:
            raise TradePurchaseDuplicateError(
                existing_id=dup_p.id,
                existing_human_id=dup_p.human_id or "",
                message=DUPLICATE_PURCHASE_DETECTED_CODE,
            )
    tp.purchase_date = body.purchase_date
    tp.invoice_number = (body.invoice_number.strip() if body.invoice_number else None) or None
    tp.supplier_id = body.supplier_id
    tp.broker_id = body.broker_id
    tp.payment_days = body.payment_days
    tp.due_date = _due_date_from(body.purchase_date, body.payment_days)
    tp.discount = dp.percent(body.discount) if body.discount is not None else None
    tp.commission_percent = dp.percent(body.commission_percent) if body.commission_percent is not None else None
    tp.commission_mode = body.commission_mode
    tp.commission_money = dp.money(body.commission_money) if body.commission_money is not None else None
    tp.delivered_rate = dp.money(body.delivered_rate) if body.delivered_rate is not None else None
    tp.billty_rate = dp.money(body.billty_rate) if body.billty_rate is not None else None
    tp.freight_amount = dp.money(body.freight_amount) if body.freight_amount is not None else None
    tp.freight_type = body.freight_type
    tp.total_qty = dp.qty(qty_sum)
    tp.total_amount = dp.total(amt_sum)
    tp.total_landing_subtotal = land_s
    tp.total_selling_subtotal = sell_s
    tp.total_line_profit = prof
    if body.status in ("draft", "saved", "confirmed"):
        tp.status = body.status
    await db.execute(delete(TradePurchaseLine).where(TradePurchaseLine.trade_purchase_id == tp.id))
    await db.flush()
    line_item_ids = {li.catalog_item_id for li in body.lines if li.catalog_item_id}
    catalog_by_id = await fetch_catalog_items_map(db, business_id, line_item_ids)
    for li in body.lines:
        li = _strip_disallowed_fields_for_default_wholesale_mode(li)
        line_total = _line_money(li)
        line_weight = _line_total_weight(li)
        line_profit = _line_profit(li, body)
        cat_item = catalog_by_id.get(li.catalog_item_id)
        qty_su = line_qty_in_stock_unit(li, cat_item) if cat_item else dp.qty(li.qty)
        db.add(
            TradePurchaseLine(
                trade_purchase_id=tp.id,
                catalog_item_id=li.catalog_item_id,
                item_name=li.item_name,
                qty=dp.qty(li.qty),
                unit=li.unit,
                qty_in_stock_unit=qty_su,
                unit_type=derive_trade_unit_type(li.unit),
                purchase_rate=dp.rate(li.purchase_rate or li.landing_cost),
                selling_rate=dp.rate(li.selling_rate) if li.selling_rate is not None else None,
                freight_type=li.freight_type,
                freight_value=dp.money(li.freight_value) if li.freight_value is not None else None,
                delivered_rate=dp.money(li.delivered_rate) if li.delivered_rate is not None else None,
                billty_rate=dp.money(li.billty_rate) if li.billty_rate is not None else None,
                weight_per_unit=dp.weight(li.weight_per_unit) if li.weight_per_unit is not None else None,
                total_weight=line_weight if line_weight > 0 else None,
                line_total=line_total,
                profit=line_profit,
                box_mode=li.box_mode,
                items_per_box=dp.qty(li.items_per_box) if li.items_per_box is not None else None,
                weight_per_item=dp.weight(li.weight_per_item) if li.weight_per_item is not None else None,
                kg_per_box=dp.weight(li.kg_per_box) if li.kg_per_box is not None else None,
                weight_per_tin=dp.weight(li.weight_per_tin) if li.weight_per_tin is not None else None,
                landing_cost=dp.rate(li.landing_cost),
                kg_per_unit=dp.weight(li.kg_per_unit) if li.kg_per_unit is not None else None,
                landing_cost_per_kg=dp.rate(li.landing_cost_per_kg)
                if li.landing_cost_per_kg is not None
                else None,
                selling_cost=dp.rate(li.selling_cost) if li.selling_cost is not None else None,
                discount=dp.percent(li.discount) if li.discount is not None else None,
                tax_percent=dp.percent(li.tax_percent) if li.tax_percent is not None else None,
                tax_mode=_line_tax_mode(li),
                payment_days=li.payment_days,
                hsn_code=(li.hsn_code.strip() if (li.hsn_code and li.hsn_code.strip()) else None),
                item_code=(li.item_code.strip() if (li.item_code and str(li.item_code).strip()) else None),
                description=(li.description.strip() if (li.description and li.description.strip()) else None),
            )
        )
    # Re-sync paid vs new total: clamp paid_amount
    total_dec = _dec(tp.total_amount)
    paid_dec = _dec(tp.paid_amount)
    if paid_dec > total_dec:
        tp.paid_amount = dp.money(total_dec)
    tp.updated_at = utcnow()
    await _sync_purchase_memory(db, business_id, body, trade_purchase_id=tp.id)
    stock_updates: list[dict] = []
    try:
        if was_delivered:
            stock_updates = await sync_confirmed_purchase_stock_diff(
                db,
                business_id,
                tp.user_id,
                old_lines_snapshot,
                body.lines,
                purchase_human_id=tp.human_id,
            )
    except ValueError:
        await db.rollback()
        raise
    await db.commit()
    bump_trade_read_caches_for_business(business_id)
    res2 = await db.execute(
        select(TradePurchase)
        .where(TradePurchase.id == tp.id)
        .options(*_trade_purchase_load_opts())
    )
    return trade_purchase_to_out(res2.scalar_one(), stock_updates=stock_updates)


async def patch_trade_purchase_payment(
    db: AsyncSession,
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    body: TradePurchasePaymentPatch,
) -> TradePurchaseOut | None:
    res = await db.execute(
        select(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.id == purchase_id,
        )
        .options(*_trade_purchase_load_opts())
    )
    tp = res.scalar_one_or_none()
    if not tp:
        return None
    if (tp.status or "").lower() == "deleted":
        return None
    if (tp.status or "").lower() in ("cancelled", "draft"):
        raise ValueError("Payment not allowed for this purchase state")
    total = _dec(tp.total_amount)
    paid = min(max(_dec(body.paid_amount), Decimal("0")), total)
    tp.paid_amount = dp.money(paid)
    tp.paid_at = body.paid_at or utcnow()
    tp.updated_at = utcnow()
    derived = compute_status(
        stored_status=tp.status or "confirmed",
        total_amount=total,
        paid_amount=dp.money(paid),
        due_date=tp.due_date,
    )
    if (tp.status or "").lower() not in ("draft", "cancelled"):
        tp.status = derived
    await db.commit()
    bump_trade_read_caches_for_business(business_id)
    return await get_trade_purchase(db, business_id, purchase_id)


async def patch_trade_purchase_delivery(
    db: AsyncSession,
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    body: TradePurchaseDeliveryPatch,
) -> TradePurchaseOut | None:
    res = await db.execute(
        select(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.id == purchase_id,
        )
        .options(*_trade_purchase_load_opts())
    )
    tp = res.scalar_one_or_none()
    if not tp:
        return None
    st = (tp.status or "").lower()
    if st == "deleted":
        return None
    if st == "cancelled":
        raise ValueError("Delivery changes are not allowed for cancelled purchases")
    was_delivered = bool(getattr(tp, "is_delivered", False))
    if was_delivered == bool(body.is_delivered) and body.delivery_notes is None:
        return trade_purchase_to_out(tp, stock_updates=[])
    lines_snapshot = list(tp.lines)
    stock_updates: list[dict] = []
    tp.is_delivered = body.is_delivered
    if body.is_delivered:
        tp.delivered_at = body.delivered_at or utcnow()
    else:
        tp.delivered_at = None
    if body.delivery_notes is not None:
        notes = body.delivery_notes.strip()
        tp.delivery_notes = notes or None
    tp.updated_at = utcnow()
    try:
        if not was_delivered and body.is_delivered:
            stock_updates = await apply_confirmed_purchase_stock(
                db,
                business_id,
                tp.user_id,
                lines_snapshot,
                purchase_human_id=tp.human_id,
            )
        elif was_delivered and not body.is_delivered:
            stock_updates = await revert_confirmed_purchase_stock(
                db,
                business_id,
                tp.user_id,
                lines_snapshot,
                purchase_human_id=tp.human_id,
            )
    except ValueError:
        await db.rollback()
        raise
    await db.commit()
    bump_trade_read_caches_for_business(business_id)
    try:
        from app.services.notification_emitter import (
            CATEGORY_PURCHASE,
            PRIORITY_HIGH,
            PRIORITY_INFO,
            emit_notification,
        )

        sup = (tp.supplier_name or "Supplier").strip()
        if body.is_delivered:
            await emit_notification(
                db,
                business_id=business_id,
                kind="delivery_received",
                title=f"Delivery received: {tp.human_id}",
                body=f"{sup} — stock updated at warehouse",
                priority=PRIORITY_INFO,
                category=CATEGORY_PURCHASE,
                dedupe_key=f"delivery_received:{purchase_id}",
                action_route=f"/purchase/detail/{purchase_id}",
                related_purchase_id=purchase_id,
            )
        else:
            await emit_notification(
                db,
                business_id=business_id,
                kind="delivery_pending",
                title=f"Pending delivery: {tp.human_id}",
                body=f"{sup} — awaiting warehouse receipt",
                priority=PRIORITY_HIGH,
                category=CATEGORY_PURCHASE,
                dedupe_key=f"delivery_pending:{purchase_id}",
                action_route=f"/purchase/detail/{purchase_id}",
                related_purchase_id=purchase_id,
            )
        await db.commit()
    except Exception:
        await db.rollback()
    res2 = await db.execute(
        select(TradePurchase)
        .where(TradePurchase.id == purchase_id)
        .options(*_trade_purchase_load_opts())
    )
    return trade_purchase_to_out(res2.scalar_one(), stock_updates=stock_updates)


async def verify_trade_purchase_delivery(
    db: AsyncSession,
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    user: User,
    body: TradePurchaseVerifyIn,
) -> TradePurchaseOut | None:
    res = await db.execute(
        select(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.id == purchase_id,
        )
        .options(*_trade_purchase_load_opts())
    )
    tp = res.scalar_one_or_none()
    if not tp:
        return None
    if not bool(getattr(tp, "is_delivered", False)):
        raise ValueError("Delivery must be marked received before verification")

    by_id = {str(line.id): line for line in tp.lines}
    total_received = Decimal("0")
    total_damaged = Decimal("0")
    total_return = Decimal("0")
    for line in body.lines:
        row = by_id.get(str(line.line_id))
        if row is None:
            continue
        total_received += _dec(line.received_qty)
        total_damaged += _dec(line.damaged_qty)
        total_return += _dec(line.return_qty)

    vnote = (
        f"Verified by {user.name or user.username or user.email}"
        f" | received={total_received} damaged={total_damaged} return={total_return}"
    )
    if body.notes and body.notes.strip():
        vnote = f"{vnote} | notes={body.notes.strip()}"
    existing = (tp.delivery_notes or "").strip()
    tp.delivery_notes = f"{existing}\n{vnote}".strip() if existing else vnote
    tp.updated_at = utcnow()
    await db.commit()
    bump_trade_read_caches_for_business(business_id)
    try:
        from app.services.notification_emitter import (
            CATEGORY_PURCHASE,
            PRIORITY_INFO,
            emit_notification,
        )

        await emit_notification(
            db,
            business_id=business_id,
            kind="delivery_verified",
            title=f"Verified: {tp.human_id}",
            body=f"{user.name or user.username or user.email} verified warehouse receipt",
            priority=PRIORITY_INFO,
            category=CATEGORY_PURCHASE,
            dedupe_key=f"delivery_verified:{purchase_id}:{int(datetime.now(timezone.utc).timestamp())}",
            action_route=f"/purchase/detail/{purchase_id}",
            related_purchase_id=purchase_id,
        )
        await db.commit()
    except Exception:
        await db.rollback()
    return await get_trade_purchase(db, business_id, purchase_id)


async def mark_trade_purchase_paid(
    db: AsyncSession,
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    body: TradeMarkPaidRequest,
) -> TradePurchaseOut | None:
    res = await db.execute(
        select(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.id == purchase_id,
        )
        .options(*_trade_purchase_load_opts())
    )
    tp = res.scalar_one_or_none()
    if not tp:
        return None
    if (tp.status or "").lower() == "deleted":
        return None
    if (tp.status or "").lower() in ("cancelled", "draft"):
        raise ValueError("Payment not allowed for this purchase state")
    total = _dec(tp.total_amount)
    if body.paid_amount is None:
        new_paid = total
    else:
        new_paid = min(max(_dec(body.paid_amount), Decimal("0")), total)
    tp.paid_amount = dp.money(new_paid)
    tp.paid_at = body.paid_at or utcnow()
    tp.updated_at = utcnow()
    derived = compute_status(
        stored_status=tp.status or "confirmed",
        total_amount=total,
        paid_amount=dp.money(tp.paid_amount),
        due_date=tp.due_date,
    )
    tp.status = derived
    await db.commit()
    bump_trade_read_caches_for_business(business_id)
    return await get_trade_purchase(db, business_id, purchase_id)


async def cancel_trade_purchase(
    db: AsyncSession, business_id: uuid.UUID, purchase_id: uuid.UUID
) -> TradePurchaseOut | None:
    res = await db.execute(
        select(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.id == purchase_id,
        )
        .options(*_trade_purchase_load_opts())
    )
    tp = res.scalar_one_or_none()
    if not tp:
        return None
    if (tp.status or "").lower() == "deleted":
        return None
    was_delivered = bool(getattr(tp, "is_delivered", False))
    old_lines = list(tp.lines) if was_delivered else []
    tp.status = "cancelled"
    tp.is_delivered = False
    tp.delivered_at = None
    tp.updated_at = utcnow()
    if was_delivered and old_lines:
        try:
            await revert_confirmed_purchase_stock(
                db,
                business_id,
                tp.user_id,
                old_lines,
                purchase_human_id=tp.human_id,
            )
        except ValueError:
            await db.rollback()
            raise
    await db.commit()
    bump_trade_read_caches_for_business(business_id)
    return await get_trade_purchase(db, business_id, purchase_id)


async def delete_trade_purchase(
    db: AsyncSession, business_id: uuid.UUID, purchase_id: uuid.UUID
) -> bool:
    res = await db.execute(
        select(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.id == purchase_id,
        )
        .options(selectinload(TradePurchase.lines))
    )
    tp = res.scalar_one_or_none()
    if not tp:
        return False
    if (tp.status or "").lower() == "deleted":
        return False
    was_delivered = bool(getattr(tp, "is_delivered", False))
    old_lines = list(tp.lines) if was_delivered else []
    tp.status = "deleted"
    tp.is_delivered = False
    tp.delivered_at = None
    tp.updated_at = utcnow()
    if was_delivered and old_lines:
        try:
            await revert_confirmed_purchase_stock(
                db,
                business_id,
                tp.user_id,
                old_lines,
                purchase_human_id=tp.human_id,
            )
        except ValueError:
            await db.rollback()
            raise
    await db.commit()
    bump_trade_read_caches_for_business(business_id)
    return True


def _line_item_code(li: TradePurchaseLine) -> str | None:
    raw = getattr(li, "item_code", None)
    if raw is not None and str(raw).strip():
        return str(raw).strip()
    ci = getattr(li, "catalog_item", None)
    if ci is None:
        return None
    ic = getattr(ci, "item_code", None)
    if ic is None:
        return None
    s = str(ic).strip()
    return s or None


def _line_hsn(li: TradePurchaseLine) -> str | None:
    raw = getattr(li, "hsn_code", None)
    if raw is not None and str(raw).strip():
        return str(raw).strip()
    ci = getattr(li, "catalog_item", None)
    if ci is None:
        return None
    h = getattr(ci, "hsn_code", None)
    if h is None:
        return None
    s = str(h).strip()
    return s or None


def _catalog_item_unit_hints(li: TradePurchaseLine) -> tuple[str | None, Decimal | None, str | None]:
    ci = getattr(li, "catalog_item", None)
    if ci is None:
        return None, None, None
    du = getattr(ci, "default_unit", None)
    dpu = getattr(ci, "default_purchase_unit", None)
    kpb = getattr(ci, "default_kg_per_bag", None)
    du_s = str(du).strip().lower() if du is not None and str(du).strip() else None
    dpu_s = str(dpu).strip().lower() if dpu is not None and str(dpu).strip() else None
    kpb_f = dp.weight(kpb) if kpb is not None else None
    return du_s, kpb_f, dpu_s


def _trade_purchase_line_in_from_db(li: TradePurchaseLine) -> TradePurchaseLineIn:
    """Rebuild [TradePurchaseLineIn] from ORM row (``model_construct`` skips BAG-only validators)."""
    pr = getattr(li, "purchase_rate", None) or li.landing_cost
    kpu = getattr(li, "weight_per_unit", None) or getattr(li, "kg_per_unit", None)
    sr = getattr(li, "selling_rate", None) or getattr(li, "selling_cost", None)
    sc = getattr(li, "selling_cost", None) or getattr(li, "selling_rate", None)
    return TradePurchaseLineIn.model_construct(
        catalog_item_id=li.catalog_item_id,
        item_name=(li.item_name or "").strip() or "—",
        qty=li.qty,
        unit=li.unit or "pcs",
        landing_cost=li.landing_cost,
        purchase_rate=pr,
        kg_per_unit=kpu,
        weight_per_unit=kpu,
        landing_cost_per_kg=getattr(li, "landing_cost_per_kg", None),
        selling_rate=sr,
        selling_cost=sc,
        freight_type=getattr(li, "freight_type", None),
        freight_value=getattr(li, "freight_value", None),
        delivered_rate=getattr(li, "delivered_rate", None),
        billty_rate=getattr(li, "billty_rate", None),
        box_mode=getattr(li, "box_mode", None),
        items_per_box=getattr(li, "items_per_box", None),
        weight_per_item=getattr(li, "weight_per_item", None),
        kg_per_box=getattr(li, "kg_per_box", None),
        weight_per_tin=getattr(li, "weight_per_tin", None),
        discount=li.discount,
        tax_percent=li.tax_percent,
        payment_days=getattr(li, "payment_days", None),
        hsn_code=getattr(li, "hsn_code", None),
        item_code=getattr(li, "item_code", None),
        description=getattr(li, "description", None),
    )


def _line_purchase_money_db(li: TradePurchaseLine, li_in: TradePurchaseLineIn) -> Decimal:
    """Tax/discount-inclusive line purchase (persisted ``line_total`` when present)."""
    raw = getattr(li, "line_total", None)
    if raw is not None:
        return dp.total(raw)
    return _line_money(li_in)


def _line_profit_dummy_trade_req() -> TradePurchaseCreateRequest:
    """``line_profit`` ignores header fields; stable placeholder for ORM → Out mapping."""
    return TradePurchaseCreateRequest(
        purchase_date=date.today(),
        supplier_id=uuid.UUID("00000000-0000-4000-8000-000000000000"),
        lines=[],
    )


def _line_selling_gross_db(li: TradePurchaseLine) -> Decimal:
    selling = getattr(li, "selling_rate", None)
    if selling is None:
        selling = li.selling_cost
    if selling is None:
        return Decimal("0")
    return dp.total(_dec(li.qty) * _dec(selling))


def trade_purchase_to_out(
    tp: TradePurchase,
    *,
    stock_updates: list[dict] | None = None,
) -> TradePurchaseOut:
    lines = []
    sum_land = Decimal("0")
    sum_sell = Decimal("0")
    for li in tp.lines:
        du_s, kpb_f, dpu_s = _catalog_item_unit_hints(li)
        li_in = _trade_purchase_line_in_from_db(li)
        lg = dp.total(_line_gross_base(li_in))
        lpm = _line_purchase_money_db(li, li_in)
        sg = _line_selling_gross_db(li)
        sum_land += lg
        sum_sell += sg
        stored_profit = getattr(li, "profit", None)
        if stored_profit is not None:
            lp = dp.total(stored_profit)
        elif getattr(li, "selling_rate", None) is not None or li.selling_cost is not None:
            lp = _line_profit(li_in, _line_profit_dummy_trade_req())
        else:
            lp = None
        kpu_raw = getattr(li, "weight_per_unit", None)
        if kpu_raw is None:
            kpu_raw = getattr(li, "kg_per_unit", None)
        kpu_val = dp.weight(kpu_raw) if kpu_raw is not None else None
        total_weight_raw = getattr(li, "total_weight", None)
        total_weight = dp.total_weight(total_weight_raw) if total_weight_raw is not None else (
            dp.total_weight(_dec(li.qty) * kpu_val) if kpu_val is not None else (
                dp.total_weight(li.qty) if str(li.unit or "").strip().lower() == "kg" else None
            )
        )
        purchase_rate = getattr(li, "purchase_rate", None) or li.landing_cost
        selling_rate = getattr(li, "selling_rate", None) or li.selling_cost
        raw_ut = getattr(li, "unit_type", None)
        out_ut = (
            raw_ut.strip().lower()
            if isinstance(raw_ut, str) and raw_ut.strip()
            else derive_trade_unit_type(li.unit)
        )
        urd = resolve_from_text(li.item_name or "").as_dict()
        rctx = build_rate_context(li_in, resolved_labels=urd)
        lines.append(
            TradePurchaseLineOut(
                id=li.id,
                catalog_item_id=li.catalog_item_id,
                item_name=li.item_name,
                qty=dp.qty(li.qty),
                unit=li.unit,
                unit_type=out_ut,
                landing_cost=dp.rate(li.landing_cost),
                purchase_rate=dp.rate(purchase_rate),
                kg_per_unit=kpu_val,
                weight_per_unit=kpu_val,
                landing_cost_per_kg=dp.rate(li.landing_cost_per_kg)
                if getattr(li, "landing_cost_per_kg", None) is not None
                else None,
                selling_cost=dp.rate(selling_rate) if selling_rate is not None else None,
                selling_rate=dp.rate(selling_rate) if selling_rate is not None else None,
                freight_type=getattr(li, "freight_type", None),
                freight_value=dp.money(getattr(li, "freight_value", None)) if getattr(li, "freight_value", None) is not None else None,
                delivered_rate=dp.money(getattr(li, "delivered_rate", None)) if getattr(li, "delivered_rate", None) is not None else None,
                billty_rate=dp.money(getattr(li, "billty_rate", None)) if getattr(li, "billty_rate", None) is not None else None,
                total_weight=total_weight,
                line_total=lpm,
                profit=lp,
                box_mode=getattr(li, "box_mode", None),
                items_per_box=dp.qty(getattr(li, "items_per_box", None)) if getattr(li, "items_per_box", None) is not None else None,
                weight_per_item=dp.weight(getattr(li, "weight_per_item", None)) if getattr(li, "weight_per_item", None) is not None else None,
                kg_per_box=dp.weight(getattr(li, "kg_per_box", None)) if getattr(li, "kg_per_box", None) is not None else None,
                weight_per_tin=dp.weight(getattr(li, "weight_per_tin", None)) if getattr(li, "weight_per_tin", None) is not None else None,
                discount=dp.percent(li.discount) if li.discount is not None else None,
                tax_percent=dp.percent(li.tax_percent) if li.tax_percent is not None else None,
                payment_days=getattr(li, "payment_days", None),
                hsn_code=_line_hsn(li),
                item_code=_line_item_code(li),
                description=getattr(li, "description", None),
                default_unit=du_s,
                default_kg_per_bag=kpb_f,
                default_purchase_unit=dpu_s,
                line_landing_gross=lg,
                line_selling_gross=sg,
                line_profit=lp,
                rate_context=rctx,
            )
        )
    total_dec = _dec(tp.total_amount)
    paid_dec = _dec(getattr(tp, "paid_amount", None))
    remaining = dp.money(max(total_dec - paid_dec, Decimal("0")))
    stored = tp.status or "confirmed"
    due = getattr(tp, "due_date", None)
    derived = compute_status(
        stored_status=stored,
        total_amount=total_dec,
        paid_amount=paid_dec,
        due_date=due,
    )
    sup_name: str | None = None
    bro_name: str | None = None
    supplier_gst: str | None = None
    supplier_address: str | None = None
    supplier_phone: str | None = None
    supplier_whatsapp: str | None = None
    broker_phone: str | None = None
    broker_location: str | None = None
    broker_image_url: str | None = None
    sr = getattr(tp, "supplier_row", None)
    if sr is not None:
        sup_name = getattr(sr, "name", None)
        supplier_gst = getattr(sr, "gst_number", None) or None
        supplier_address = getattr(sr, "address", None) or None
        supplier_phone = getattr(sr, "phone", None) or None
        supplier_whatsapp = getattr(sr, "whatsapp_number", None) or None
    br = getattr(tp, "broker_row", None)
    if br is not None:
        bro_name = getattr(br, "name", None)
        broker_phone = getattr(br, "phone", None) or None
        broker_location = getattr(br, "location", None) or None
        broker_image_url = getattr(br, "image_url", None) or None
    items_count = len(tp.lines) if tp.lines is not None else 0
    tls = getattr(tp, "total_landing_subtotal", None)
    tss = getattr(tp, "total_selling_subtotal", None)
    tlp = getattr(tp, "total_line_profit", None)
    if tls is None:
        tls = sum_land
    if tss is None and sum_sell > 0:
        tss = sum_sell
    if tlp is None and tss is not None:
        tlp = dp.total(_dec(tss) - _dec(tls))
    return TradePurchaseOut(
        id=tp.id,
        human_id=tp.human_id,
        invoice_number=getattr(tp, "invoice_number", None),
        purchase_date=tp.purchase_date,
        supplier_id=tp.supplier_id,
        broker_id=tp.broker_id,
        payment_days=tp.payment_days,
        due_date=due,
        paid_amount=dp.money(paid_dec),
        paid_at=getattr(tp, "paid_at", None),
        discount=dp.percent(tp.discount) if tp.discount is not None else None,
        commission_percent=dp.percent(tp.commission_percent) if tp.commission_percent is not None else None,
        commission_mode=(getattr(tp, "commission_mode", None) or "percent").strip().lower(),
        commission_money=dp.money(tp.commission_money) if getattr(tp, "commission_money", None) is not None else None,
        delivered_rate=dp.money(tp.delivered_rate) if tp.delivered_rate is not None else None,
        billty_rate=dp.money(tp.billty_rate) if tp.billty_rate is not None else None,
        freight_amount=dp.money(tp.freight_amount) if tp.freight_amount is not None else None,
        freight_type=getattr(tp, "freight_type", None),
        total_qty=dp.qty(tp.total_qty) if tp.total_qty is not None else None,
        total_amount=dp.total(tp.total_amount),
        total_landing_subtotal=dp.total(tls) if tls is not None else None,
        total_selling_subtotal=dp.total(tss) if tss is not None else None,
        total_line_profit=tlp,
        status=stored,
        remaining=remaining,
        derived_status=derived,
        items_count=items_count,
        supplier_name=sup_name,
        broker_name=bro_name,
        supplier_gst=supplier_gst,
        supplier_address=supplier_address,
        supplier_phone=supplier_phone,
        supplier_whatsapp=supplier_whatsapp,
        broker_phone=broker_phone,
        broker_location=broker_location,
        broker_image_url=broker_image_url,
        created_at=tp.created_at,
        updated_at=getattr(tp, "updated_at", None),
        lines=lines,
        header_discount=dp.percent(tp.discount) if tp.discount is not None else None,
        freight_value=dp.money(tp.freight_amount) if tp.freight_amount is not None else None,
        has_missing_details=_purchase_has_missing_optional_details(tp),
        is_delivered=bool(getattr(tp, "is_delivered", False)),
        delivered_at=getattr(tp, "delivered_at", None),
        delivery_notes=getattr(tp, "delivery_notes", None),
        stock_updates=[
            StockUpdateOut(
                catalog_item_id=u["catalog_item_id"],
                name=u["name"],
                unit=u.get("unit"),
                old_qty=dp.qty(u["old_qty"]),
                new_qty=dp.qty(u["new_qty"]),
                delta=dp.qty(u["delta"]),
            )
            for u in (stock_updates or [])
        ],
    )


async def get_draft(db: AsyncSession, business_id: uuid.UUID, user_id: uuid.UUID) -> TradeDraftOut | None:
    q = await db.execute(
        select(TradePurchaseDraft).where(
            TradePurchaseDraft.business_id == business_id,
            TradePurchaseDraft.user_id == user_id,
        )
    )
    d = q.scalar_one_or_none()
    if not d:
        return None
    try:
        payload = json.loads(d.payload_json or "{}")
    except json.JSONDecodeError:
        payload = {}
    return TradeDraftOut(step=d.step, payload=payload, updated_at=d.updated_at)


async def upsert_draft(
    db: AsyncSession, business_id: uuid.UUID, user_id: uuid.UUID, step: int, payload: dict
) -> TradeDraftOut:
    q = await db.execute(
        select(TradePurchaseDraft).where(
            TradePurchaseDraft.business_id == business_id,
            TradePurchaseDraft.user_id == user_id,
        )
    )
    d = q.scalar_one_or_none()
    body = json.dumps(payload, default=str)
    if d:
        d.step = step
        d.payload_json = body
        d.updated_at = utcnow()
    else:
        d = TradePurchaseDraft(
            business_id=business_id,
            user_id=user_id,
            step=step,
            payload_json=body,
        )
        db.add(d)
    await db.commit()
    await db.refresh(d)
    try:
        pl = json.loads(d.payload_json)
    except json.JSONDecodeError:
        pl = {}
    return TradeDraftOut(step=d.step, payload=pl, updated_at=d.updated_at)


async def delete_draft(db: AsyncSession, business_id: uuid.UUID, user_id: uuid.UUID) -> None:
    await db.execute(
        delete(TradePurchaseDraft).where(
            TradePurchaseDraft.business_id == business_id,
            TradePurchaseDraft.user_id == user_id,
        )
    )
    await db.commit()
