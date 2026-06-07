"""Business data exports (CSV/ZIP) — no third-party storage; returns bytes."""

from __future__ import annotations

import io
import logging
import re
import uuid
import zipfile
from collections import defaultdict
from datetime import date
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from starlette.responses import Response

from app.database import get_db
from app.deps import require_permission
from app.models import Business, Membership, TradePurchase, TradePurchaseLine
from app.services import trade_query as tq
from app.services.export_files import (
    build_purchase_order_pdf,
    build_purchases_month_pdf,
    build_purchases_range_pdf,
    build_stock_inventory_xlsx,
    build_supplier_ledger_pdf,
    fetch_month_trade_purchases,
    fetch_stock_inventory_rows,
)

router = APIRouter(prefix="/v1/businesses/{business_id}/exports", tags=["exports"])
logger = logging.getLogger(__name__)


class BackupRequest(BaseModel):
    range_preset: Literal["month", "quarter", "all"] = Field(
        default="month",
        description="month = calendar month to date; quarter = 90d; all = eligible trade purchases",
    )


def _range_dates(preset: str, today: date) -> tuple[date | None, date]:
    """Inclusive end = today; start None means no lower bound."""
    if preset == "month":
        start = date(today.year, today.month, 1)
        return start, today
    if preset == "quarter":
        from datetime import timedelta

        return today - timedelta(days=89), today
    return None, today


def _zip_path_segment(s: str, max_len: int = 72) -> str:
    t = re.sub(r"[^\w\-.]+", "_", (s or "").strip(), flags=re.UNICODE)
    t = re.sub(r"_+", "_", t).strip("._") or "export"
    return t[:max_len]


@router.post("/backup")
async def post_backup_zip(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_permission("export_access"))],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: BackupRequest,
):
    del _m
    today = date.today()
    d_from, d_to = _range_dates(body.range_preset, today)

    conds = [
        TradePurchase.business_id == business_id,
        tq.trade_purchase_status_in_reports(),
    ]
    if d_from is not None:
        conds.append(TradePurchase.purchase_date >= d_from)
    conds.append(TradePurchase.purchase_date <= d_to)

    pr = await db.execute(
        select(TradePurchase)
        .where(*conds)
        .options(selectinload(TradePurchase.supplier_row))
        .order_by(TradePurchase.purchase_date.desc())
        .limit(5000)
    )
    purchases = list(pr.scalars().all())
    if not purchases:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            detail="No trade purchases in this range to export.",
        )

    purchase_ids = [p.id for p in purchases]
    lr = await db.execute(
        select(TradePurchaseLine).where(TradePurchaseLine.trade_purchase_id.in_(purchase_ids))
    )
    all_lines = list(lr.scalars().all())
    lines_by_purchase: dict[uuid.UUID, list[TradePurchaseLine]] = defaultdict(list)
    for ln in all_lines:
        lines_by_purchase[ln.trade_purchase_id].append(ln)

    br = await db.execute(select(Business.name).where(Business.id == business_id))
    business_label = (br.scalar_one_or_none() or "").strip() or str(business_id)
    range_start = d_from or min((p.purchase_date for p in purchases if p.purchase_date), default=d_to)
    preset_titles = {"month": "This month", "quarter": "Last 90 days", "all": "All purchases"}
    summary_title = f"Purchases — {preset_titles.get(body.range_preset, body.range_preset)}"

    try:
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.writestr(
                "purchases_summary.pdf",
                build_purchases_range_pdf(
                    business_label=business_label,
                    title=summary_title,
                    range_start=range_start,
                    range_end=d_to,
                    purchases=purchases,
                ),
            )

            stock_rows = await fetch_stock_inventory_rows(db, business_id)
            if stock_rows:
                zf.writestr(
                    f"stock/harisree_stock_{d_to.isoformat()}.xlsx",
                    build_stock_inventory_xlsx(stock_rows),
                )

            for p in purchases:
                lines = lines_by_purchase.get(p.id, [])
                zf.writestr(
                    f"orders/{_zip_path_segment(p.human_id)}.pdf",
                    build_purchase_order_pdf(
                        business_label=business_label,
                        purchase=p,
                        lines=lines,
                    ),
                )

            by_supplier: dict[uuid.UUID, list[TradePurchase]] = defaultdict(list)
            for p in purchases:
                by_supplier[p.supplier_id].append(p)

            for sid, plist in by_supplier.items():
                sup_name = ""
                if plist[0].supplier_row is not None:
                    sup_name = (plist[0].supplier_row.name or "").strip()
                stem = f"{_zip_path_segment(sup_name or str(sid))}"
                zf.writestr(
                    f"ledgers/{stem}.pdf",
                    build_supplier_ledger_pdf(
                        business_label=business_label,
                        supplier_name=sup_name or str(sid),
                        range_start=range_start,
                        range_end=d_to,
                        purchases=plist,
                    ),
                )

            sum_total = sum(float(p.total_amount or 0) for p in purchases)
            sum_paid = sum(float(p.paid_amount or 0) for p in purchases)
            sum_bal = sum(float(p.total_amount or 0) - float(p.paid_amount or 0) for p in purchases)
            summary = (
                "Purchase Assistant — backup summary\n"
                f"Business: {business_label}\n"
                f"Range preset: {body.range_preset} ({range_start.isoformat()} to {d_to.isoformat()})\n"
                f"Purchase rows: {len(purchases)}\n"
                f"Total billed: {sum_total:.2f}\n"
                f"Total paid: {sum_paid:.2f}\n"
                f"Outstanding: {sum_bal:.2f}\n"
            )
            zf.writestr("Summary.txt", summary)

            readme = (
                "Purchase Assistant backup\n"
                f"Business: {business_label}\n"
                f"Range: {body.range_preset} ({range_start.isoformat()} to {d_to.isoformat()})\n"
                "\n"
                "Contents:\n"
                "  purchases_summary.pdf   — all purchases in range\n"
                "  orders/*.pdf            — one PDF per purchase bill\n"
                "  ledgers/*.pdf           — per-supplier totals / paid / balance\n"
                "  stock/*.xlsx            — current inventory snapshot (when items exist)\n"
                "  Summary.txt             — range totals\n"
            )
            zf.writestr("README.txt", readme)

        buf.seek(0)
        fname = f"purchase_assistant_backup_{business_id}_{d_to.isoformat()}.zip"
        return Response(
            content=buf.getvalue(),
            media_type="application/zip",
            headers={"Content-Disposition": f'attachment; filename="{fname}"'},
        )
    except Exception as e:
        logger.error("Backup ZIP generation failed: %s", e, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "code": "BACKUP_FAILED",
                "message": "Could not generate backup. Please try again in a moment.",
            },
        ) from e


@router.get("/stock-inventory.xlsx")
async def get_stock_inventory_xlsx(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_permission("export_access"))],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Excel inventory snapshot: qty, reorder, category, supplier."""
    del _m
    rows = await fetch_stock_inventory_rows(db, business_id)
    if not rows:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            detail="No catalog items to export.",
        )
    stamp = date.today().isoformat()
    try:
        content = build_stock_inventory_xlsx(rows)
    except Exception as e:
        logger.error("Stock inventory XLSX export failed: %s", e, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "code": "STOCK_EXPORT_FAILED",
                "message": "Could not generate stock export. Please try again in a moment.",
            },
        ) from e
    fname = f"harisree_stock_{stamp}.xlsx"
    return Response(
        content=content,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{fname}"'},
    )


@router.get("/purchases-month.pdf")
async def get_purchases_month_pdf(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_permission("export_access"))],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """PDF rollup of trade purchases for the current calendar month."""
    del _m
    today = date.today()
    month_start = date(today.year, today.month, 1)
    purchases = await fetch_month_trade_purchases(
        db, business_id, month_start=month_start, month_end=today
    )
    if not purchases:
        purchases = []
    br = await db.execute(select(Business.name).where(Business.id == business_id))
    label = (br.scalar_one_or_none() or "").strip() or str(business_id)
    try:
        content = build_purchases_month_pdf(
            business_label=label,
            month_start=month_start,
            month_end=today,
            purchases=purchases,
        )
    except Exception as e:
        logger.error("Purchases month PDF export failed: %s", e, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "code": "PDF_EXPORT_FAILED",
                "message": "Could not generate PDF export. Please try again in a moment.",
            },
        ) from e
    fname = f"harisree_purchases_{today.year}-{today.month:02d}.pdf"
    return Response(
        content=content,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{fname}"'},
    )
