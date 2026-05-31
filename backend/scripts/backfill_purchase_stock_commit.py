"""One-off: commit stock for POs marked delivered but missing stock marker.

Usage (from backend/, with DATABASE_URL set):
  python -m scripts.backfill_purchase_stock_commit [--business-id UUID] [--dry-run]

Prefer per-item Recompute via API when only a few items are wrong.
"""

from __future__ import annotations

import argparse
import asyncio
import uuid

from sqlalchemy import select

from app.database import async_session_maker
from app.models import TradePurchase, User
from app.services.stock_inventory import purchase_delivery_stock_already_applied
from app.services.trade_purchase_service import commit_trade_purchase_delivery


async def run(*, business_id: uuid.UUID | None, dry_run: bool) -> None:
    async with async_session_maker() as db:
        q = select(TradePurchase).where(
            TradePurchase.delivery_status.in_(("staff_verified", "partial", "stock_committed")),
            TradePurchase.status.notin_(("cancelled", "deleted")),
        )
        if business_id:
            q = q.where(TradePurchase.business_id == business_id)
        rows = (await db.execute(q)).scalars().all()
        fixed = 0
        skipped = 0
        for tp in rows:
            if await purchase_delivery_stock_already_applied(db, tp.business_id, tp.id):
                skipped += 1
                continue
            if tp.delivery_status not in ("staff_verified", "partial", "stock_committed"):
                skipped += 1
                continue
            owner = await db.get(User, tp.user_id)
            if owner is None:
                skipped += 1
                continue
            print(f"{'[dry-run] ' if dry_run else ''}commit {tp.human_id} ({tp.id})")
            if not dry_run:
                if tp.delivery_status == "stock_committed":
                    tp.delivery_status = "staff_verified"
                    await db.flush()
                await commit_trade_purchase_delivery(
                    db, tp.business_id, tp.id, owner
                )
                fixed += 1
        print(f"done: fixed={fixed} skipped={skipped} scanned={len(rows)}")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--business-id", type=uuid.UUID, default=None)
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()
    asyncio.run(run(business_id=args.business_id, dry_run=args.dry_run))


if __name__ == "__main__":
    main()
