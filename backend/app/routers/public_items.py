import html
import uuid

from fastapi import APIRouter, HTTPException, Query, Request, status
from sqlalchemy import String, desc, func, select
from starlette.responses import HTMLResponse, JSONResponse

from app.database import async_session_factory
from app.models import Business, CatalogItem, ItemCategory, Supplier
from app.models.stock_physical_count import StockPhysicalCount
from app.services.stock_inventory import (
    movement_delivered_qty_map,
    stock_status,
)
from app.middleware.rate_limit import SlidingWindowLimiter

router = APIRouter(prefix="/public/items", tags=["public-items"])
_PUBLIC_IP_LIMITER = SlidingWindowLimiter(max_requests=60, window_seconds=60.0)


def _enforce_public_rate_limit(request: Request) -> None:
    xff = request.headers.get("x-forwarded-for", "")
    ip = xff.split(",")[0].strip() if xff else ""
    if not ip:
        ip = request.client.host if request.client else "unknown"
    if not _PUBLIC_IP_LIMITER.allow(f"public:{ip}"):
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many requests. Please try again shortly.",
        )


async def _latest_physical_qty(
    db,
    business_id,
    item_id,
) -> tuple[float | None, str | None]:
    r = await db.execute(
        select(StockPhysicalCount)
        .where(
            StockPhysicalCount.business_id == business_id,
            StockPhysicalCount.item_id == item_id,
        )
        .order_by(desc(StockPhysicalCount.counted_at))
        .limit(1)
    )
    row = r.scalar_one_or_none()
    if row is None:
        return None, None
    when = (
        row.counted_at.isoformat()
        if row.counted_at
        else None
    )
    return float(row.counted_qty or 0), when


async def _supplier_name_for_item(db, item: CatalogItem) -> str | None:
    if not item.last_supplier_id:
        return None
    r = await db.execute(
        select(Supplier.name).where(Supplier.id == item.last_supplier_id)
    )
    return r.scalar_one_or_none()


def _safe_item_payload(
    item: CatalogItem,
    category_name: str | None,
    *,
    delivered_qty: float | None = None,
    physical_qty: float | None = None,
    physical_counted_at: str | None = None,
    supplier_name: str | None = None,
) -> dict:
    current = float(item.current_stock or 0)
    reorder = float(item.reorder_level or 0)
    unit = item.stock_unit or item.default_unit or item.selling_unit or "unit"
    opening = float(getattr(item, "opening_stock_qty", None) or 0)
    delivered = delivered_qty if delivered_qty is not None else 0.0
    return {
        "name": item.name,
        "category": category_name,
        "item_code": item.item_code,
        "barcode": item.barcode,
        "current_stock": current,
        "opening_stock_qty": opening,
        "total_delivered_qty": delivered,
        "stock_unit": unit,
        "status": stock_status(item.current_stock, item.reorder_level),
        "rack_location": item.rack_location,
        "last_stock_updated_at": item.last_stock_updated_at.isoformat()
        if item.last_stock_updated_at
        else None,
        "physical_stock_qty": physical_qty,
        "physical_stock_counted_at": physical_counted_at,
        "last_purchase_date": item.last_purchase_at.isoformat()
        if item.last_purchase_at
        else None,
        "last_purchase_rate": float(item.last_purchase_price)
        if item.last_purchase_price is not None
        else None,
        "last_purchase_qty": float(item.last_line_qty)
        if item.last_line_qty is not None
        else None,
        "last_purchase_unit": item.last_line_unit or unit,
        "supplier_name": supplier_name,
    }


async def _load_public_item(
    token: str,
) -> tuple[CatalogItem, str | None, float, float | None, str | None, str | None]:
    clean = token.strip()
    if not clean or len(clean) > 64:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    try:
        parsed = uuid.UUID(clean)
        if parsed.version != 4:
            raise ValueError("non-v4")
    except Exception:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    async with async_session_factory() as db:
        by_token = await db.execute(
            select(CatalogItem, ItemCategory.name)
            .join(ItemCategory, ItemCategory.id == CatalogItem.category_id)
            .where(
                CatalogItem.public_token == clean,
                CatalogItem.deleted_at.is_(None),
            )
        )
        row = by_token.first()
        if row is None:
            raise HTTPException(
                status.HTTP_404_NOT_FOUND,
                detail="Item not found — scan the QR on the label",
            )
        item, category_name = row[0], row[1]
        delivered_map = await movement_delivered_qty_map(
            db, item.business_id, [item.id]
        )
        delivered = float(delivered_map.get(item.id, 0))
        phys_qty, phys_at = await _latest_physical_qty(db, item.business_id, item.id)
        supplier = await _supplier_name_for_item(db, item)
        return item, category_name, delivered, phys_qty, phys_at, supplier


async def _resolve_business_id(db, business: str) -> str:
    raw = business.strip()
    if not raw:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Business not found")
    by_id = await db.execute(select(Business.id).where(func.cast(Business.id, String) == raw))
    bid = by_id.scalar_one_or_none()
    if bid is not None:
        return str(bid)
    slug = raw.replace("-", " ").strip().lower()
    by_name = await db.execute(
        select(Business.id).where(func.lower(Business.name) == slug)
    )
    bid = by_name.scalar_one_or_none()
    if bid is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Business not found")
    return str(bid)


@router.get("/{token}.json")
async def public_item_json(token: str, request: Request) -> JSONResponse:
    _enforce_public_rate_limit(request)
    item, category_name, delivered, phys_qty, phys_at, supplier = await _load_public_item(
        token
    )
    payload = _safe_item_payload(
        item,
        category_name,
        delivered_qty=delivered,
        physical_qty=phys_qty,
        physical_counted_at=phys_at,
        supplier_name=supplier,
    )
    return JSONResponse(
        payload,
        headers={"Cache-Control": "public, max-age=60"},
    )


@router.get("/lookup")
async def public_lookup(
    request: Request,
    barcode: str = Query(..., min_length=1, max_length=100),
    business: str = Query(..., min_length=1, max_length=255),
) -> JSONResponse:
    _enforce_public_rate_limit(request)
    clean = barcode.strip()
    async with async_session_factory() as db:
        business_id = await _resolve_business_id(db, business)
        row = await db.execute(
            select(CatalogItem, ItemCategory.name)
            .join(ItemCategory, ItemCategory.id == CatalogItem.category_id)
            .where(
                CatalogItem.business_id == business_id,
                CatalogItem.barcode == clean,
                CatalogItem.deleted_at.is_(None),
            )
            .limit(2)
        )
        rows = row.all()
        if len(rows) != 1:
            raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
        item, category_name = rows[0][0], rows[0][1]
        delivered_map = await movement_delivered_qty_map(db, item.business_id, [item.id])
        delivered = float(delivered_map.get(item.id, 0))
        phys_qty, phys_at = await _latest_physical_qty(db, item.business_id, item.id)
        supplier = await _supplier_name_for_item(db, item)
        payload = _safe_item_payload(
            item,
            category_name,
            delivered_qty=delivered,
            physical_qty=phys_qty,
            physical_counted_at=phys_at,
            supplier_name=supplier,
        )
    return JSONResponse(payload, headers={"Cache-Control": "public, max-age=60"})


@router.get("/{token}", response_class=HTMLResponse)
async def public_item_page(token: str, request: Request) -> HTMLResponse:
    _enforce_public_rate_limit(request)
    item, category_name, delivered, phys_qty, phys_at, supplier = await _load_public_item(
        token
    )
    payload = _safe_item_payload(
        item,
        category_name,
        delivered_qty=delivered,
        physical_qty=phys_qty,
        physical_counted_at=phys_at,
        supplier_name=supplier,
    )
    status_label = str(payload["status"]).replace("_", " ").title()
    stock_qty = payload["current_stock"]
    body = f"""
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(payload["name"])}</title>
  <style>
    body {{ font-family: system-ui, -apple-system, Segoe UI, sans-serif; margin: 0; background: #f7f9f6; color: #0f172a; }}
    .card {{ margin: 24px auto; max-width: 420px; background: white; border-radius: 20px; padding: 24px; box-shadow: 0 12px 40px rgba(15, 23, 42, .10); }}
    .brand {{ color: #0e4f46; font-weight: 800; letter-spacing: .02em; }}
    h1 {{ margin: 12px 0 4px; font-size: 26px; }}
    .muted {{ color: #64748b; }}
    .stock {{ margin-top: 18px; padding: 16px; border-radius: 16px; background: #e8f5f2; }}
    .qty {{ font-size: 34px; font-weight: 900; color: #0e4f46; }}
    .status {{ display: inline-block; margin-top: 10px; padding: 6px 10px; border-radius: 999px; background: #fff7ed; color: #c2410c; font-weight: 800; }}
  </style>
</head>
<body>
  <main class="card">
    <div class="brand">Harisree Warehouse</div>
    <h1>{html.escape(payload["name"])}</h1>
    <div class="muted">{html.escape(payload.get("category") or "Catalog item")}</div>
    <div class="stock">
      <div class="muted">System stock</div>
      <div class="qty">{stock_qty:g} {html.escape(str(payload["stock_unit"]).upper())}</div>
      <div class="status">{html.escape(status_label)}</div>
    </div>
    <p class="muted">Item code: {html.escape(payload.get("item_code") or "-")}</p>
    <p class="muted">Rack: {html.escape(payload.get("rack_location") or "-")}</p>
  </main>
</body>
</html>
"""
    return HTMLResponse(body)
