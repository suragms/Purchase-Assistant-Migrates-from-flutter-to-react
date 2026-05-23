"""Business data exports (CSV/ZIP) — no third-party storage; returns bytes."""

from __future__ import annotations

import csv
import io
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
from app.models import Membership, TradePurchase, TradePurchaseLine
from app.services import trade_query as tq

router = APIRouter(prefix="/v1/businesses/{business_id}/exports", tags=["exports"])


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


def _write_purchase_lines_csv(w: csv.writer, p: TradePurchase, lines: list[TradePurchaseLine]) -> None:
    if not lines:
        w.writerow(
            [
                p.human_id,
                p.purchase_date.isoformat() if p.purchase_date else "",
                str(p.supplier_id) if p.supplier_id else "",
                p.status,
                float(p.total_amount or 0),
                (p.invoice_number or "").strip(),
                "",
                "",
                "",
                "",
            ]
        )
        return
    for ln in lines:
        w.writerow(
            [
                p.human_id,
                p.purchase_date.isoformat() if p.purchase_date else "",
                str(p.supplier_id) if p.supplier_id else "",
                p.status,
                float(p.total_amount or 0),
                (p.invoice_number or "").strip(),
                (ln.item_name or "").strip(),
                float(ln.qty or 0),
                (ln.unit or "").strip(),
                float(ln.line_total or 0) if ln.line_total is not None else "",
            ]
        )


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

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        csv_io = io.StringIO()
        w = csv.writer(csv_io)
        w.writerow(
            [
                "human_id",
                "purchase_date",
                "supplier_id",
                "status",
                "total_amount",
                "invoice_number",
                "line_item",
                "qty",
                "unit",
                "line_total",
            ]
        )
        for p in purchases:
            lines = lines_by_purchase.get(p.id, [])
            _write_purchase_lines_csv(w, p, lines)
        zf.writestr("purchases.csv", csv_io.getvalue())

        for p in purchases:
            lines = lines_by_purchase.get(p.id, [])
            one = io.StringIO()
            ow = csv.writer(one)
            ow.writerow(
                [
                    "human_id",
                    "purchase_date",
                    "supplier_id",
                    "status",
                    "total_amount",
                    "invoice_number",
                    "line_item",
                    "qty",
                    "unit",
                    "line_total",
                ]
            )
            _write_purchase_lines_csv(ow, p, lines)
            zf.writestr(f"orders/{_zip_path_segment(p.human_id)}.csv", one.getvalue())

        by_supplier: dict[uuid.UUID, list[TradePurchase]] = defaultdict(list)
        for p in purchases:
            by_supplier[p.supplier_id].append(p)

        for sid, plist in by_supplier.items():
            sup_name = ""
            if plist[0].supplier_row is not None:
                sup_name = (plist[0].supplier_row.name or "").strip()
            stem = f"{sid}_{_zip_path_segment(sup_name)}"
            lb = io.StringIO()
            lw = csv.writer(lb)
            lw.writerow(
                [
                    "human_id",
                    "purchase_date",
                    "invoice_number",
                    "status",
                    "total_amount",
                    "paid_amount",
                    "balance",
                    "due_date",
                ]
            )
            for p in sorted(plist, key=lambda x: x.purchase_date, reverse=True):
                tot = float(p.total_amount or 0)
                paid = float(p.paid_amount or 0)
                bal = tot - paid
                lw.writerow(
                    [
                        p.human_id,
                        p.purchase_date.isoformat() if p.purchase_date else "",
                        (p.invoice_number or "").strip(),
                        p.status,
                        tot,
                        paid,
                        bal,
                        p.due_date.isoformat() if p.due_date else "",
                    ]
                )
            zf.writestr(f"ledgers/{stem}.csv", lb.getvalue())

        sum_total = sum(float(p.total_amount or 0) for p in purchases)
        sum_paid = sum(float(p.paid_amount or 0) for p in purchases)
        sum_bal = sum(float(p.total_amount or 0) - float(p.paid_amount or 0) for p in purchases)
        summary = (
            "Purchase Assistant — summary (text)\n"
            f"Business: {business_id}\n"
            f"Range preset: {body.range_preset} (through {d_to.isoformat()})\n"
            f"Purchase rows: {len(purchases)}\n"
            f"Total billed: {sum_total:.2f}\n"
            f"Total paid: {sum_paid:.2f}\n"
            f"Outstanding: {sum_bal:.2f}\n"
            "\n"
            "Formatted PDF invoices and supplier statements are generated in the mobile app "
            "(Share on a purchase or supplier statement). This ZIP includes CSV line data under "
            "orders/ and per-supplier rollups under ledgers/.\n"
        )
        zf.writestr("Summary_Statement.txt", summary)

        readme = (
            "Purchase Assistant backup\n"
            f"Business: {business_id}\n"
            f"Range: {body.range_preset} (through {d_to.isoformat()})\n"
            "\n"
            "Contents:\n"
            "  purchases.csv       — flat export (all purchases in range)\n"
            "  orders/*.csv        — one file per purchase (line detail)\n"
            "  ledgers/*.csv       — per supplier: purchase totals / paid / balance\n"
            "  Summary_Statement.txt — range totals (text; use app Share for PDFs)\n"
            "\n"
            "Open CSV files in Excel or Google Sheets.\n"
        )
        zf.writestr("README.txt", readme)

    buf.seek(0)
    fname = f"purchase_assistant_backup_{business_id}_{d_to.isoformat()}.zip"
    return Response(
        content=buf.getvalue(),
        media_type="application/zip",
        headers={"Content-Disposition": f'attachment; filename="{fname}"'},
    )
