"""CRUD for server-persisted report saved views."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user, require_membership
from app.models import Membership, User
from app.models.report_saved_view import ReportSavedView

router = APIRouter(prefix="/v1/businesses/{business_id}/report-views", tags=["report-views"])


class ReportViewIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    tab: str = Field(min_length=1, max_length=32)
    filters_json: dict[str, Any] = Field(default_factory=dict)
    is_default: bool = False


class ReportViewPatch(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    tab: str | None = Field(default=None, min_length=1, max_length=32)
    filters_json: dict[str, Any] | None = None
    is_default: bool | None = None


def _serialize(row: ReportSavedView) -> dict[str, Any]:
    return {
        "id": str(row.id),
        "business_id": str(row.business_id),
        "user_id": str(row.user_id),
        "name": row.name,
        "tab": row.tab,
        "filters_json": row.filters_json or {},
        "is_default": bool(row.is_default),
        "created_at": row.created_at.isoformat() if row.created_at else None,
        "updated_at": row.updated_at.isoformat() if row.updated_at else None,
    }


@router.get("")
async def list_report_views(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> list[dict[str, Any]]:
    del _m
    r = await db.execute(
        select(ReportSavedView)
        .where(
            ReportSavedView.business_id == business_id,
            ReportSavedView.user_id == user.id,
        )
        .order_by(ReportSavedView.updated_at.desc())
    )
    return [_serialize(row) for row in r.scalars().all()]


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_report_view(
    business_id: uuid.UUID,
    body: ReportViewIn,
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict[str, Any]:
    del _m
    if body.is_default:
        await db.execute(
            update(ReportSavedView)
            .where(
                ReportSavedView.business_id == business_id,
                ReportSavedView.user_id == user.id,
                ReportSavedView.tab == body.tab,
            )
            .values(is_default=False)
        )
    row = ReportSavedView(
        business_id=business_id,
        user_id=user.id,
        name=body.name.strip(),
        tab=body.tab.strip(),
        filters_json=body.filters_json,
        is_default=body.is_default,
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return _serialize(row)


@router.patch("/{view_id}")
async def patch_report_view(
    business_id: uuid.UUID,
    view_id: uuid.UUID,
    body: ReportViewPatch,
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict[str, Any]:
    del _m
    r = await db.execute(
        select(ReportSavedView).where(
            ReportSavedView.id == view_id,
            ReportSavedView.business_id == business_id,
            ReportSavedView.user_id == user.id,
        )
    )
    row = r.scalar_one_or_none()
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="view_not_found")
    if body.name is not None:
        row.name = body.name.strip()
    if body.tab is not None:
        row.tab = body.tab.strip()
    if body.filters_json is not None:
        row.filters_json = body.filters_json
    if body.is_default is not None:
        if body.is_default:
            tab = body.tab or row.tab
            await db.execute(
                update(ReportSavedView)
                .where(
                    ReportSavedView.business_id == business_id,
                    ReportSavedView.user_id == user.id,
                    ReportSavedView.tab == tab,
                    ReportSavedView.id != view_id,
                )
                .values(is_default=False)
            )
        row.is_default = body.is_default
    row.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(row)
    return _serialize(row)


@router.delete("/{view_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_report_view(
    business_id: uuid.UUID,
    view_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> None:
    del _m
    r = await db.execute(
        select(ReportSavedView).where(
            ReportSavedView.id == view_id,
            ReportSavedView.business_id == business_id,
            ReportSavedView.user_id == user.id,
        )
    )
    row = r.scalar_one_or_none()
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="view_not_found")
    await db.delete(row)
    await db.commit()
