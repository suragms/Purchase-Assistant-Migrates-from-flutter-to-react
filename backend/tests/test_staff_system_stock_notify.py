"""Staff system stock patch notifies owners."""

import asyncio
from decimal import Decimal
from unittest.mock import AsyncMock, patch
import uuid

from app.services.stock_variance_notifications import maybe_notify_staff_system_stock_edit


def test_staff_system_stock_edit_notifies_owners():
    async def _run():
        db = AsyncMock()
        bid = uuid.uuid4()
        iid = uuid.uuid4()
        uid = uuid.uuid4()
        with patch(
            "app.services.stock_variance_notifications.emit_notification",
            new_callable=AsyncMock,
        ) as emit:
            await maybe_notify_staff_system_stock_edit(
                db,
                business_id=bid,
                item_id=iid,
                item_name="Rice",
                unit="bag",
                old_qty=Decimal("10"),
                new_qty=Decimal("8"),
                actor_user_id=uid,
                actor_display="krishna",
                actor_role="staff",
            )
            emit.assert_awaited_once()
            kwargs = emit.await_args.kwargs
            assert kwargs["kind"] == "stock_correction"
            assert kwargs["owner_only"] is True
            assert "krishna" in kwargs["body"]

    asyncio.run(_run())


def test_owner_edit_skips_staff_notify():
    async def _run():
        db = AsyncMock()
        with patch(
            "app.services.stock_variance_notifications.emit_notification",
            new_callable=AsyncMock,
        ) as emit:
            await maybe_notify_staff_system_stock_edit(
                db,
                business_id=uuid.uuid4(),
                item_id=uuid.uuid4(),
                item_name="Rice",
                unit="bag",
                old_qty=Decimal("10"),
                new_qty=Decimal("8"),
                actor_user_id=uuid.uuid4(),
                actor_display="Owner",
                actor_role="owner",
            )
            emit.assert_not_awaited()

    asyncio.run(_run())
