"""Server-Sent Events stub for live dashboard updates (Phase 4 full implementation)."""

import asyncio
import json
import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from fastapi.responses import StreamingResponse

from app.deps import require_membership, require_realtime_effective
from app.models import Membership
from app.services.realtime_events import recent_business_events, subscribe_business_events

router = APIRouter(prefix="/v1/businesses/{business_id}/realtime", tags=["realtime"])


@router.get("/events")
async def sse_events(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    _rt: Annotated[None, Depends(require_realtime_effective)],
):
    del _m, _rt

    async def gen():
        async for queue in subscribe_business_events(business_id):
            while True:
                try:
                    event = await asyncio.wait_for(queue.get(), timeout=30)
                except asyncio.TimeoutError:
                    event = {"type": "ping", "business_id": str(business_id)}
                yield f"data: {json.dumps(event)}\n\n"

    return StreamingResponse(gen(), media_type="text/event-stream")


@router.get("/recent")
async def recent_events(
    business_id: uuid.UUID,
    m: Annotated[Membership, Depends(require_membership)],
    limit: int = Query(50, ge=1, le=100),
):
    if m.role not in ("owner", "admin", "super_admin", "manager"):
        return []
    return recent_business_events(business_id, limit=limit)
