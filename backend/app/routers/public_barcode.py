"""Public barcode lookup (no auth) — for camera apps and external scanners."""

from fastapi import APIRouter, HTTPException, Query, Request, status
from sqlalchemy import select
from starlette.responses import JSONResponse

from app.database import async_session_factory
from app.models import CatalogItem, ItemCategory
from app.routers.public_items import (
    _enforce_public_rate_limit,
    _latest_physical_qty,
    _resolve_business_id,
    _safe_item_payload,
    _supplier_name_for_item,
)
from app.services.stock_inventory import movement_delivered_qty_map

router = APIRouter(prefix="/public", tags=["public-barcode"])


@router.get("/barcode/{barcode}.json")
async def public_barcode_json(barcode: str, request: Request) -> JSONResponse:
    _enforce_public_rate_limit(request)
    clean = barcode.strip()
    async with async_session_factory() as db:
        row = await db.execute(
            select(CatalogItem, ItemCategory.name)
            .join(ItemCategory, ItemCategory.id == CatalogItem.category_id)
            .where(CatalogItem.barcode == clean, CatalogItem.deleted_at.is_(None))
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
