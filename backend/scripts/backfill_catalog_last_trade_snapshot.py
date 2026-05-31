"""One-time repair: repoint catalog last-trade snapshots away from deleted/cancelled purchases.

Usage (from backend/):
  python -m scripts.backfill_catalog_last_trade_snapshot [--business-id UUID]
"""

from __future__ import annotations

import argparse
import asyncio
import uuid

from sqlalchemy import select

from app.database import async_session_maker
from app.models import CatalogItem
from app.services.trade_purchase_service import refresh_catalog_last_trade_snapshots


async def run(business_id: uuid.UUID | None) -> None:
    async with async_session_maker() as db:
        q = select(CatalogItem.id, CatalogItem.business_id).where(
            CatalogItem.deleted_at.is_(None),
            CatalogItem.last_trade_purchase_id.isnot(None),
        )
        if business_id is not None:
            q = q.where(CatalogItem.business_id == business_id)
        rows = (await db.execute(q)).all()
        by_biz: dict[uuid.UUID, list[uuid.UUID]] = {}
        for cid, bid in rows:
            by_biz.setdefault(bid, []).append(cid)
        total = 0
        for bid, ids in by_biz.items():
            await refresh_catalog_last_trade_snapshots(db, bid, ids)
            total += len(ids)
        await db.commit()
        print(f"Refreshed last-trade snapshot for {total} catalog item(s).")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--business-id", type=uuid.UUID, default=None)
    args = p.parse_args()
    asyncio.run(run(args.business_id))


if __name__ == "__main__":
    main()
