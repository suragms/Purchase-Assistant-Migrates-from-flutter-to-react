"""In-process generation counter invalidates TTL read caches after trade mutations (per business)."""

from __future__ import annotations

import threading
import uuid

_lock = threading.Lock()
_by_business: dict[str, int] = {}


def bump_trade_read_caches_for_business(business_id: uuid.UUID | str) -> None:
    k = str(business_id)
    with _lock:
        _by_business[k] = _by_business.get(k, 0) + 1
    from app.services.app_cache import invalidate_business

    invalidate_business(business_id)


def trade_read_cache_generation(business_id: uuid.UUID | str) -> int:
    k = str(business_id)
    with _lock:
        return _by_business.get(k, 0)
