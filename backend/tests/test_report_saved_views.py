"""Report saved views API smoke tests."""

from __future__ import annotations

import uuid

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_report_saved_views_crud(
    client: AsyncClient,
    owner_headers: dict[str, str],
    business_id: uuid.UUID,
) -> None:
    base = f"/v1/businesses/{business_id}/report-views"
    create = await client.post(
        base,
        headers=owner_headers,
        json={
            "name": "High value items",
            "tab": "items",
            "filters_json": {"sort": "highestValue"},
            "is_default": True,
        },
    )
    assert create.status_code == 201, create.text
    view_id = create.json()["id"]

    listed = await client.get(base, headers=owner_headers)
    assert listed.status_code == 200
    assert any(r["id"] == view_id for r in listed.json())

    patched = await client.patch(
        f"{base}/{view_id}",
        headers=owner_headers,
        json={"name": "Top items"},
    )
    assert patched.status_code == 200
    assert patched.json()["name"] == "Top items"

    deleted = await client.delete(f"{base}/{view_id}", headers=owner_headers)
    assert deleted.status_code == 204
