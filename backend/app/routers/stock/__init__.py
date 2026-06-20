"""Stock router package — combines sub-routers under /v1/businesses/{business_id}/stock."""
from fastapi import APIRouter

from app.routers.stock import stock_audit, stock_barcode, stock_detail, stock_list, stock_ops
from app.services.stock_helpers import fetch_low_stock_top_rows
from app.routers.stock.stock_list import (
    _fetch_low_stock_candidates,
    stock_alerts_summary,
    warehouse_alerts_from_stock,
)
from app.services.stock_helpers import (
    _classify_delivery_indicator,
    _parse_period_dates,
    _resolve_period_query,
)
from app.routers.stock.stock_barcode import _barcode_lookup_cache

router = APIRouter(prefix="/v1/businesses/{business_id}/stock", tags=["stock"])
router.include_router(stock_list.router)
router.include_router(stock_barcode.router)
router.include_router(stock_audit.router)
# Static paths (inventory-summary, totals, opening/*) must register before
# stock_detail `/{item_id}` or FastAPI treats the segment as a UUID → 422.
router.include_router(stock_ops.router)
router.include_router(stock_detail.router)

__all__ = [
    "router",
    "fetch_low_stock_top_rows",
    "stock_alerts_summary",
    "warehouse_alerts_from_stock",
    "_classify_delivery_indicator",
    "_fetch_low_stock_candidates",
    "_parse_period_dates",
    "_resolve_period_query",
    "_barcode_lookup_cache",
]
