"""In-process coarse realtime invalidation events.

This is intentionally lightweight: Render runs one API process today, and the
events only tell clients which surfaces to refresh. Database state remains the
source of truth.
"""

from __future__ import annotations

import asyncio
import uuid
from collections import defaultdict, deque
from datetime import datetime, timezone
from typing import Any

_queues: dict[uuid.UUID, set[asyncio.Queue[dict[str, Any]]]] = defaultdict(set)
_recent: dict[uuid.UUID, deque[dict[str, Any]]] = defaultdict(lambda: deque(maxlen=100))


def publish_business_event(
    business_id: uuid.UUID,
    event_type: str,
    payload: dict[str, Any] | None = None,
) -> None:
    event = {
        "type": event_type,
        "business_id": str(business_id),
        "payload": payload or {},
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    _recent[business_id].append(event)
    for queue in list(_queues.get(business_id, ())):
        try:
            queue.put_nowait(event)
        except asyncio.QueueFull:
            pass


async def subscribe_business_events(business_id: uuid.UUID):
    queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=50)
    _queues[business_id].add(queue)
    try:
        yield queue
    finally:
        _queues[business_id].discard(queue)


def recent_business_events(
    business_id: uuid.UUID,
    *,
    limit: int = 50,
) -> list[dict[str, Any]]:
    n = max(1, min(limit, 100))
    rows = list(_recent.get(business_id, ()))
    return rows[-n:]
