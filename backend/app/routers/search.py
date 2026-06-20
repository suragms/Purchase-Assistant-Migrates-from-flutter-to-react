"""Unified search: catalog items, suppliers, trade purchases (substring + fuzzy fallback)."""

from __future__ import annotations

import logging
import re
import uuid
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from rapidfuzz import fuzz
from sqlalchemy import and_, func, or_, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession

from app.db_schema_compat import catalog_items_has_type_id_column
from app.database import get_db
from app.db_resilience import execute_with_retry
from app.deps import require_membership
from app.models import (
    Broker,
    CatalogItem,
    CategoryType,
    ItemCategory,
    Membership,
    Supplier,
    TradePurchase,
    TradePurchaseLine,
)
from app.services import trade_purchase_service as tps
from app.services.staff_view import (
    redact_catalog_items,
    redact_trade_purchase_dict,
    should_redact_financials,
)
from app.services.fuzzy_catalog import rank_ids_by_token_sort
from app.services.trade_query import trade_purchase_status_in_reports

router = APIRouter(prefix="/v1/businesses/{business_id}", tags=["search"])
logger = logging.getLogger(__name__)

_PAIR_CAP = 5000
"""Fetch many SQL substring hits, then rank in-process (alphabetical SQL order is poor for short queries)."""
_CATALOG_FETCH_LIMIT = 160
"""API keeps a compact catalog_items array."""
_CATALOG_RETURN_LIMIT = 40
_SUPPLIER_HISTORY_CATALOG_CAP = 4000

_QUERY_ALIASES = {
    "suger": "sugar",
    "shugar": "sugar",
    "sugr": "sugar",
}


def _search_terms(q: str) -> list[str]:
    base = q.strip().lower()
    terms = [base] if base else []
    alias = _QUERY_ALIASES.get(base)
    if alias and alias not in terms:
        terms.append(alias)
    return terms


class UnifiedSearchOut(BaseModel):
    catalog_items: list[dict[str, Any]] = Field(default_factory=list)
    suppliers: list[dict[str, Any]] = Field(default_factory=list)
    brokers: list[dict[str, Any]] = Field(
        default_factory=list,
        description="Brokers whose name matches the query (same family as Contacts search).",
    )
    entries: list[dict[str, Any]] = Field(default_factory=list)
    """Legacy entry rows (old Entry model); often empty when the business only uses trade purchases."""
    catalog_subcategories: list[dict[str, Any]] = Field(
        default_factory=list,
        description="Catalog types (subcategories) matching the query by type or parent category name.",
    )
    recent_purchases: list[dict[str, Any]] = Field(
        default_factory=list,
        description="Recent trade purchases whose bill / supplier / line text matches q.",
    )
    fuzzy_catalog_used: bool = False
    fuzzy_suppliers_used: bool = False
    fuzzy_brokers_used: bool = False


def _hydrate_catalog_rows(rows: list[tuple[Any, ...]]) -> list[dict[str, Any]]:
    """Map SQL row tuples to API dicts (supports legacy 10/11-col rows pre-migration)."""
    out: list[dict[str, Any]] = []
    for row in rows:
        icode: str | None
        dsc = lsr = lq = lu = lwg = None
        lsid = lbid = None
        ltp_id = None
        su = st = pt = psz = pmeas = None
        if len(row) >= 24:
            (
                _id,
                name,
                cat,
                tname,
                du,
                dkg,
                hsn,
                icode,
                tax,
                dlc,
                dsc,
                lpp,
                lsr,
                lsid,
                lbid,
                lq,
                lu,
                lwg,
                ltp_id,
                su,
                st,
                pt,
                psz,
                pmeas,
            ) = row[:24]
        elif len(row) >= 19:
            (
                _id,
                name,
                cat,
                tname,
                du,
                dkg,
                hsn,
                icode,
                tax,
                dlc,
                dsc,
                lpp,
                lsr,
                lsid,
                lbid,
                lq,
                lu,
                lwg,
                ltp_id,
            ) = row[:19]
        elif len(row) >= 18:
            (
                _id,
                name,
                cat,
                tname,
                du,
                dkg,
                hsn,
                icode,
                tax,
                dlc,
                dsc,
                lpp,
                lsr,
                lsid,
                lbid,
                lq,
                lu,
                lwg,
            ) = row[:18]
        elif len(row) == 11:
            _id, name, cat, tname, du, dkg, hsn, icode, tax, dlc, lpp = row
        elif len(row) == 10:
            _id, name, cat, tname, du, dkg, hsn, tax, dlc, lpp = row
            icode = None
        else:
            _id, name, cat, tname, du, dkg, hsn, tax, dlc, lpp = (
                row[0],
                row[1],
                row[2],
                None,
                row[3],
                row[4],
                row[5],
                row[6],
                row[7],
                row[8],
            )
            icode = None
        icode_s = str(icode).strip() if icode is not None and str(icode).strip() else None
        out.append(
            {
                "id": str(_id),
                "name": name,
                "category_name": cat,
                "type_name": tname,
                "default_unit": du,
                "default_kg_per_bag": float(dkg) if dkg is not None else None,
                "hsn_code": hsn,
                "item_code": icode_s,
                "tax_percent": float(tax) if tax is not None else None,
                "default_landing_cost": float(dlc) if dlc is not None else None,
                "default_selling_cost": float(dsc) if dsc is not None else None,
                "last_purchase_price": float(lpp) if lpp is not None else None,
                "last_selling_rate": float(lsr) if lsr is not None else None,
                "last_supplier_id": str(lsid) if lsid is not None else None,
                "last_broker_id": str(lbid) if lbid is not None else None,
                "last_line_qty": float(lq) if lq is not None else None,
                "last_line_unit": lu,
                "last_line_weight_kg": float(lwg) if lwg is not None else None,
                "last_trade_purchase_id": str(ltp_id) if ltp_id is not None else None,
                "selling_unit": su,
                "stock_unit": st,
                "package_type": pt,
                "package_size": float(psz) if psz is not None else None,
                "package_measurement": pmeas,
                "last_purchase_human_id": None,
                "last_supplier_name": None,
                "last_broker_name": None,
                "last_supplier_phone": None,
                "last_broker_phone": None,
            }
        )
    return out


async def _attach_last_party_names(
    db: AsyncSession,
    business_id: uuid.UUID,
    items: list[dict[str, Any]],
) -> None:
    s_ids: set[uuid.UUID] = set()
    b_ids: set[uuid.UUID] = set()
    for m in items:
        raw = m.get("last_supplier_id")
        if raw:
            try:
                s_ids.add(uuid.UUID(str(raw)))
            except ValueError:
                pass
        rawb = m.get("last_broker_id")
        if rawb:
            try:
                b_ids.add(uuid.UUID(str(rawb)))
            except ValueError:
                pass
    sm: dict[uuid.UUID, str] = {}
    sphone: dict[uuid.UUID, str] = {}
    bm: dict[uuid.UUID, str] = {}
    bphone: dict[uuid.UUID, str] = {}
    if s_ids:
        sr = await execute_with_retry(
            lambda: db.execute(
                select(Supplier.id, Supplier.name, Supplier.phone).where(
                    Supplier.business_id == business_id,
                    Supplier.id.in_(s_ids),
                )
            )
        )
        for row in sr.all():
            sm[row[0]] = row[1]
            p = row[2]
            if p is not None and str(p).strip():
                sphone[row[0]] = str(p).strip()
    if b_ids:
        br = await execute_with_retry(
            lambda: db.execute(
                select(Broker.id, Broker.name, Broker.phone).where(
                    Broker.business_id == business_id,
                    Broker.id.in_(b_ids),
                )
            )
        )
        for row in br.all():
            bm[row[0]] = row[1]
            p = row[2]
            if p is not None and str(p).strip():
                bphone[row[0]] = str(p).strip()
    for m in items:
        sid = m.get("last_supplier_id")
        if sid:
            try:
                uid = uuid.UUID(str(sid))
                if uid in sm:
                    m["last_supplier_name"] = sm.get(uid)
                ph = sphone.get(uid)
                if ph:
                    m["last_supplier_phone"] = ph
            except ValueError:
                pass
        bid = m.get("last_broker_id")
        if bid:
            try:
                uid = uuid.UUID(str(bid))
                if uid in bm:
                    m["last_broker_name"] = bm.get(uid)
                ph = bphone.get(uid)
                if ph:
                    m["last_broker_phone"] = ph
            except ValueError:
                pass


async def _attach_last_purchase_human_ids(
    db: AsyncSession,
    business_id: uuid.UUID,
    items: list[dict[str, Any]],
) -> None:
    p_ids: set[uuid.UUID] = set()
    for m in items:
        raw = m.get("last_trade_purchase_id")
        if raw:
            try:
                p_ids.add(uuid.UUID(str(raw)))
            except ValueError:
                pass
    if not p_ids:
        return
    pr = await execute_with_retry(
        lambda: db.execute(
            select(TradePurchase.id, TradePurchase.human_id).where(
                TradePurchase.business_id == business_id,
                TradePurchase.id.in_(p_ids),
            )
        )
    )
    hm = {row[0]: row[1] for row in pr.all()}
    for m in items:
        raw = m.get("last_trade_purchase_id")
        if not raw:
            continue
        try:
            uid = uuid.UUID(str(raw))
        except ValueError:
            continue
        hid = hm.get(uid)
        if hid:
            m["last_purchase_human_id"] = hid


async def _supplier_exists_in_business(
    db: AsyncSession,
    business_id: uuid.UUID,
    supplier_id: uuid.UUID,
) -> bool:
    r = await execute_with_retry(
        lambda: db.execute(
            select(Supplier.id).where(
                Supplier.business_id == business_id,
                Supplier.id == supplier_id,
            )
        )
    )
    return r.scalar_one_or_none() is not None


async def _supplier_history_catalog_ids(
    db: AsyncSession,
    business_id: uuid.UUID,
    supplier_id: uuid.UUID,
) -> set[uuid.UUID]:
    rr = await execute_with_retry(
        lambda: db.execute(
            select(TradePurchaseLine.catalog_item_id)
            .join(
                TradePurchase,
                TradePurchase.id == TradePurchaseLine.trade_purchase_id,
            )
            .where(
                TradePurchase.business_id == business_id,
                TradePurchase.supplier_id == supplier_id,
                trade_purchase_status_in_reports(),
            )
            .distinct()
            .limit(_SUPPLIER_HISTORY_CATALOG_CAP)
        )
    )
    out: set[uuid.UUID] = set()
    for row in rr.all():
        cid = row[0]
        if cid is not None:
            out.add(cid)
    return out


def _rank_catalog_items_for_query(
    items: list[dict[str, Any]],
    needle: str,
    supplier_id: uuid.UUID | None,
    supplier_history_ids: set[uuid.UUID],
    *,
    limit: int,
) -> list[dict[str, Any]]:
    """Order catalog hits by fuzzy name score + prefix tokens + optional supplier signals."""
    nl = needle.strip().lower()
    if not nl:
        return items[:limit]
    scored: list[tuple[float, str, dict[str, Any]]] = []
    for m in items:
        name = (m.get("name") or "").strip()
        if not name:
            continue
        nm = name.lower()
        base = float(fuzz.token_sort_ratio(nl, nm))
        bonus = 0.0
        if nm.startswith(nl):
            bonus += 12.0
        else:
            for part in re.split(r"[^a-z0-9]+", nm):
                if part.startswith(nl):
                    bonus += 8.0
                    break
        if supplier_id is not None:
            ls = m.get("last_supplier_id")
            if ls is not None and str(supplier_id) == str(ls):
                bonus += 18.0
            try:
                cid = uuid.UUID(str(m["id"]))
                if cid in supplier_history_ids:
                    bonus += 14.0
            except (ValueError, KeyError):
                pass
        scored.append((base + bonus, nm, m))
    scored.sort(key=lambda t: (-t[0], t[1]))
    return [t[2] for t in scored[:limit]]


@router.get("/search", response_model=UnifiedSearchOut)
async def unified_search(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    q: str = Query(..., min_length=1, max_length=200),
    supplier_id: uuid.UUID | None = Query(
        None,
        description=(
            "Boost catalog items tied to this supplier: last_supplier_id snapshot "
            "and catalog_item_id on trade purchases counted in reports."
        ),
    ),
):
    redact = should_redact_financials(_m.role)

    try:
        needle = q.strip().lower()
        if len(needle) < 1:
            return UnifiedSearchOut()
        terms = _search_terms(needle)

        supplier_for_boost: uuid.UUID | None = None
        supplier_hist_ids: set[uuid.UUID] = set()
        if supplier_id is not None:
            if await _supplier_exists_in_business(db, business_id, supplier_id):
                supplier_for_boost = supplier_id
                supplier_hist_ids = await _supplier_history_catalog_ids(
                    db, business_id, supplier_id
                )
            else:
                logger.debug(
                    "unified_search ignoring unknown supplier_id=%s business_id=%s",
                    supplier_id,
                    business_id,
                )

        ic = ItemCategory
        ct = CategoryType
        has_type = await catalog_items_has_type_id_column(db)
        extra_cols = (
            CatalogItem.default_unit,
            CatalogItem.default_kg_per_bag,
            CatalogItem.hsn_code,
            CatalogItem.item_code,
            CatalogItem.tax_percent,
            CatalogItem.default_landing_cost,
            CatalogItem.default_selling_cost,
            CatalogItem.last_purchase_price,
            CatalogItem.last_selling_rate,
            CatalogItem.last_supplier_id,
            CatalogItem.last_broker_id,
            CatalogItem.last_line_qty,
            CatalogItem.last_line_unit,
            CatalogItem.last_line_weight_kg,
            CatalogItem.last_trade_purchase_id,
            CatalogItem.selling_unit,
            CatalogItem.stock_unit,
            CatalogItem.package_type,
            CatalogItem.package_size,
            CatalogItem.package_measurement,
        )
        item_name_cat_hsn = or_(
            *[
                or_(
                    func.lower(CatalogItem.name).contains(term),
                    func.lower(ic.name).contains(term),
                    and_(
                        CatalogItem.hsn_code.isnot(None),
                        func.lower(CatalogItem.hsn_code).contains(term),
                    ),
                    and_(
                        CatalogItem.item_code.isnot(None),
                        func.lower(CatalogItem.item_code).contains(term),
                    ),
                )
                for term in terms
            ]
        )
        if has_type:
            item_name_cat_hsn = or_(
                item_name_cat_hsn,
                *[
                    and_(
                        CatalogItem.type_id.isnot(None),
                        func.lower(ct.name).contains(term),
                    )
                    for term in terms
                ],
            )
            sq_items = (
                select(
                    CatalogItem.id,
                    CatalogItem.name,
                    ic.name.label("category_name"),
                    ct.name.label("type_name"),
                    *extra_cols,
                )
                .join(ic, ic.id == CatalogItem.category_id)
                .outerjoin(ct, ct.id == CatalogItem.type_id)
                .where(
                    CatalogItem.business_id == business_id,
                    CatalogItem.deleted_at.is_(None),
                    item_name_cat_hsn,
                )
                .order_by(func.lower(CatalogItem.name))
                .limit(_CATALOG_FETCH_LIMIT)
            )
        else:
            sq_items = (
                select(
                    CatalogItem.id,
                    CatalogItem.name,
                    ic.name.label("category_name"),
                    *extra_cols,
                )
                .join(ic, ic.id == CatalogItem.category_id)
                .where(
                    CatalogItem.business_id == business_id,
                    CatalogItem.deleted_at.is_(None),
                    item_name_cat_hsn,
                )
                .order_by(func.lower(CatalogItem.name))
                .limit(_CATALOG_FETCH_LIMIT)
            )
        ir = await execute_with_retry(lambda: db.execute(sq_items))
        catalog_rows = list(ir.all())
        if not has_type:
            catalog_rows = [(*r[:3], None, *r[3:]) for r in catalog_rows]
        fuzzy_catalog_used = False
        if not catalog_rows:
            pairs_r = await execute_with_retry(
                lambda: db.execute(
                    select(CatalogItem.id, CatalogItem.name).where(
                        CatalogItem.business_id == business_id,
                        CatalogItem.deleted_at.is_(None),
                    ).limit(_PAIR_CAP)
                )
            )
            pairs = [(row[0], row[1]) for row in pairs_r.all() if row[1]]
            fuzzy_cut = 40 if len(needle) < 2 else 52
            ranked = rank_ids_by_token_sort(
                needle, pairs, limit=_CATALOG_FETCH_LIMIT, score_cutoff=fuzzy_cut
            )
            if ranked:
                fuzzy_catalog_used = True
                ids = [uid for uid, _sc in ranked]
                if has_type:
                    sq_h = (
                        select(
                            CatalogItem.id,
                            CatalogItem.name,
                            ic.name.label("category_name"),
                            ct.name.label("type_name"),
                            *extra_cols,
                        )
                        .join(ic, ic.id == CatalogItem.category_id)
                        .outerjoin(ct, ct.id == CatalogItem.type_id)
                        .where(CatalogItem.id.in_(ids), CatalogItem.deleted_at.is_(None))
                    )
                else:
                    sq_h = (
                        select(
                            CatalogItem.id,
                            CatalogItem.name,
                            ic.name.label("category_name"),
                            *extra_cols,
                        )
                        .join(ic, ic.id == CatalogItem.category_id)
                        .where(CatalogItem.id.in_(ids), CatalogItem.deleted_at.is_(None))
                    )
                hr = await execute_with_retry(lambda: db.execute(sq_h))
                by_id = {row[0]: row for row in hr.all()}
                catalog_rows = []
                for i in ids:
                    if i not in by_id:
                        continue
                    row = by_id[i]
                    if has_type:
                        catalog_rows.append(row)
                    else:
                        catalog_rows.append((*row[:3], None, *row[3:]))

        catalog_items = _hydrate_catalog_rows(catalog_rows)
        await _attach_last_party_names(db, business_id, catalog_items)
        await _attach_last_purchase_human_ids(db, business_id, catalog_items)
        catalog_items = _rank_catalog_items_for_query(
            catalog_items,
            needle,
            supplier_for_boost,
            supplier_hist_ids,
            limit=_CATALOG_RETURN_LIMIT,
        )

        sup_match = or_(
            func.lower(Supplier.name).contains(needle),
            and_(
                Supplier.gst_number.isnot(None),
                func.lower(Supplier.gst_number).contains(needle),
            ),
        )
        sq_sup = (
            select(Supplier.id, Supplier.name)
            .where(
                Supplier.business_id == business_id,
                sup_match,
            )
            .order_by(func.lower(Supplier.name))
            .limit(12)
        )
        sr = await execute_with_retry(lambda: db.execute(sq_sup))
        sup_rows = list(sr.all())
        fuzzy_suppliers_used = False
        if not sup_rows:
            pairs_r = await execute_with_retry(
                lambda: db.execute(
                    select(Supplier.id, Supplier.name)
                        .where(Supplier.business_id == business_id)
                        .limit(_PAIR_CAP),
                )
            )
            pairs = [(row[0], row[1]) for row in pairs_r.all() if row[1]]
            sup_fuzzy_cut = 40 if len(needle) < 2 else 52
            ranked = rank_ids_by_token_sort(needle, pairs, limit=12, score_cutoff=sup_fuzzy_cut)
            if ranked:
                fuzzy_suppliers_used = True
                ids = [uid for uid, _sc in ranked]
                hr = await execute_with_retry(
                    lambda: db.execute(select(Supplier.id, Supplier.name).where(Supplier.id.in_(ids)))
                )
                by_id = {row[0]: row for row in hr.all()}
                sup_rows = [by_id[i] for i in ids if i in by_id]
        suppliers = [{"id": str(row[0]), "name": row[1]} for row in sup_rows]

        br_match = func.lower(Broker.name).contains(needle)
        sq_br = (
            select(Broker.id, Broker.name)
            .where(
                Broker.business_id == business_id,
                br_match,
            )
            .order_by(func.lower(Broker.name))
            .limit(12)
        )
        brr = await execute_with_retry(lambda: db.execute(sq_br))
        bro_rows = list(brr.all())
        fuzzy_brokers_used = False
        if not bro_rows:
            pairs_br = await execute_with_retry(
                lambda: db.execute(
                    select(Broker.id, Broker.name)
                    .where(Broker.business_id == business_id)
                    .limit(_PAIR_CAP),
                )
            )
            pairs_b = [(row[0], row[1]) for row in pairs_br.all() if row[1]]
            bro_fuzzy_cut = 40 if len(needle) < 2 else 52
            ranked_b = rank_ids_by_token_sort(needle, pairs_b, limit=12, score_cutoff=bro_fuzzy_cut)
            if ranked_b:
                fuzzy_brokers_used = True
                ids_b = [uid for uid, _sc in ranked_b]
                hr_b = await execute_with_retry(
                    lambda: db.execute(select(Broker.id, Broker.name).where(Broker.id.in_(ids_b)))
                )
                by_id_b = {row[0]: row for row in hr_b.all()}
                bro_rows = [by_id_b[i] for i in ids_b if i in by_id_b]
        brokers = [{"id": str(row[0]), "name": row[1]} for row in bro_rows]

        entries_out: list[dict[str, Any]] = []

        catalog_subcategories_out: list[dict[str, Any]] = []
        if has_type:
            rsub = await execute_with_retry(
                lambda: db.execute(
                    select(
                        CategoryType.id,
                        CategoryType.name,
                        ItemCategory.id,
                        ItemCategory.name,
                    )
                    .join(ItemCategory, ItemCategory.id == CategoryType.category_id)
                    .where(
                        ItemCategory.business_id == business_id,
                        or_(
                            func.lower(CategoryType.name).contains(needle),
                            func.lower(ItemCategory.name).contains(needle),
                        ),
                    )
                    .distinct()
                    .limit(20)
                )
            )
            for row in rsub.all():
                cname = row[3]
                catalog_subcategories_out.append(
                    {
                        "id": str(row[0]),
                        "name": row[1],
                        "category_id": str(row[2]),
                        "category_name": cname,
                        "parent_name": cname,
                    }
                )
            # Types linked to catalog hits (user-created types match items even if the
            # standalone type substring query missed a row).
            if catalog_rows:
                ci_ids = [row[0] for row in catalog_rows[: _CATALOG_FETCH_LIMIT]]
                if ci_ids:
                    r_types = await execute_with_retry(
                        lambda: db.execute(
                            select(
                                CategoryType.id,
                                CategoryType.name,
                                ItemCategory.id,
                                ItemCategory.name,
                            )
                            .select_from(CatalogItem)
                            .join(
                                CategoryType,
                                and_(
                                    CategoryType.id == CatalogItem.type_id,
                                ),
                            )
                            .join(ItemCategory, ItemCategory.id == CategoryType.category_id)
                            .where(
                                CatalogItem.id.in_(ci_ids),
                                CatalogItem.business_id == business_id,
                                CatalogItem.deleted_at.is_(None),
                                ItemCategory.business_id == business_id,
                            )
                            .distinct()
                        )
                    )
                    seen_type = {d["id"] for d in catalog_subcategories_out}
                    for trow in r_types.all():
                        tid = str(trow[0])
                        if tid in seen_type:
                            continue
                        seen_type.add(tid)
                        pname = trow[3]
                        catalog_subcategories_out.append(
                            {
                                "id": tid,
                                "name": trow[1],
                                "category_id": str(trow[2]),
                                "category_name": pname,
                                "parent_name": pname,
                            }
                        )

        # User-created types + typos: substring ILIKE can miss rows; fuzzy ranks
        # all (type, parent) pairs for the business (same cap as catalog fuzzy).
        if has_type and not catalog_subcategories_out:
            pairs_r = await execute_with_retry(
                lambda: db.execute(
                    select(
                        CategoryType.id,
                        CategoryType.name,
                        ItemCategory.id,
                        ItemCategory.name,
                    )
                    .join(ItemCategory, ItemCategory.id == CategoryType.category_id)
                    .where(ItemCategory.business_id == business_id)
                    .limit(_PAIR_CAP)
                )
            )
            type_pairs: list[tuple[uuid.UUID, str]] = []
            type_meta: dict[uuid.UUID, tuple[str, uuid.UUID, str]] = {}
            for row in pairs_r.all():
                tid, tname, cid, cname = row[0], row[1], row[2], row[3]
                hay = f"{tname} {cname}".strip()
                if not hay:
                    continue
                type_pairs.append((tid, hay))
                type_meta[tid] = (tname, cid, cname)
            fuzzy_sub_cut = 40 if len(needle) < 2 else 52
            ranked_sub = rank_ids_by_token_sort(
                needle, type_pairs, limit=20, score_cutoff=fuzzy_sub_cut
            )
            for uid, _sc in ranked_sub:
                tname, cid, cname = type_meta[uid]
                catalog_subcategories_out.append(
                    {
                        "id": str(uid),
                        "name": tname,
                        "category_id": str(cid),
                        "category_name": cname,
                        "parent_name": cname,
                    }
                )

        recent_purchases_out: list[dict[str, Any]] = []
        try:
            recent_rows = await execute_with_retry(
                lambda: tps.list_trade_purchases(
                    db,
                    business_id,
                    limit=10,
                    offset=0,
                    status_filter="all",
                    q=q.strip(),
                    reports_eligible_only=True,
                )
            )
            recent_purchases_out = [r.model_dump(mode="json") for r in recent_rows]
            if redact:
                recent_purchases_out = [
                    redact_trade_purchase_dict(p) for p in recent_purchases_out
                ]
        except Exception:
            logger.exception(
                "unified_search recent_purchases failed business_id=%s q=%s",
                business_id,
                q,
            )

        catalog_out = redact_catalog_items(catalog_items) if redact else catalog_items

        return UnifiedSearchOut(
            catalog_items=catalog_out,
            suppliers=suppliers,
            brokers=brokers,
            entries=entries_out,
            catalog_subcategories=catalog_subcategories_out,
            recent_purchases=recent_purchases_out,
            fuzzy_catalog_used=fuzzy_catalog_used,
            fuzzy_suppliers_used=fuzzy_suppliers_used,
            fuzzy_brokers_used=fuzzy_brokers_used,
        )
    except SQLAlchemyError:
        logger.exception("unified_search failed business_id=%s q=%s", business_id, q)
        return UnifiedSearchOut()
