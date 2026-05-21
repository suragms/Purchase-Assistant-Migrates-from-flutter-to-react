"""Role templates and per-membership permission overrides."""

from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Membership

PERMISSION_KEYS = (
    "stock_edit",
    "purchase_create",
    "reports_access",
    "barcode_print",
    "user_manage",
    "delete_items",
)

ROLE_DEFAULTS: dict[str, dict[str, bool]] = {
    "owner": {k: True for k in PERMISSION_KEYS},
    "manager": {
        "stock_edit": True,
        "purchase_create": True,
        "reports_access": True,
        "barcode_print": True,
        "user_manage": False,
        "delete_items": False,
    },
    "staff": {
        "stock_edit": True,
        "purchase_create": True,
        "reports_access": False,
        "barcode_print": True,
        "user_manage": False,
        "delete_items": False,
    },
}


def effective_permissions(role: str, overrides: dict[str, Any] | None) -> dict[str, bool]:
    base = dict(ROLE_DEFAULTS.get(role, ROLE_DEFAULTS["staff"]))
    if overrides:
        for k in PERMISSION_KEYS:
            if k in overrides and isinstance(overrides[k], bool):
                base[k] = overrides[k]
    return base


async def membership_permissions(
    membership: Membership,
) -> dict[str, bool]:
    raw = getattr(membership, "permissions_json", None) or {}
    return effective_permissions(membership.role, raw if isinstance(raw, dict) else None)


def require_permission_key(key: str, perms: dict[str, bool]) -> None:
    from fastapi import HTTPException, status

    if not perms.get(key, False):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            detail=f"Permission denied: {key}",
        )
