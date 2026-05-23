"""Harisree AI — chat stub + structured intent (OpenAI / Groq / Gemini optional; keys stay on server)."""

from datetime import date, datetime, timedelta, timezone
import uuid
from typing import Annotated, Any, Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from rapidfuzz import fuzz
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.database import get_db
from app.deps import charge_ai_turn_for_business, require_membership
from app.models import (
    ApiUsageLog,
    AssistantDecision,
    AssistantSession,
    CatalogAlias,
    CatalogItem,
    CategoryType,
    Entry,
    EntryLineItem,
    ItemCategory,
    Membership,
    Supplier,
    User,
)
from app.services.app_assistant_chat import run_app_assistant_turn
from app.services.assistant_business_context import build_compact_business_snapshot
from app.services.intent_stub import stub_intent_from_text
from app.services.llm_intent import extract_intent_json
from app.services.usage_logging import log_usage

router = APIRouter(prefix="/v1/businesses/{business_id}/ai", tags=["ai"])
# Structured intent system prompt: app.services.assistant_system_prompt.SYSTEM_PROMPT


class ChatMessage(BaseModel):
    role: Literal["user", "assistant", "system"]
    content: str = Field(min_length=1, max_length=8000)


class ChatRequest(BaseModel):
    messages: list[ChatMessage] = Field(min_length=1, max_length=40)
    preview_token: str | None = None
    entry_draft: dict[str, Any] | None = None


class ChatResponse(BaseModel):
    reply: str
    model: str = "assistant"
    tokens_used_month: int = 0
    intent: str = "help"
    preview_token: str | None = None
    entry_draft: dict[str, Any] | None = None
    saved_entry: dict[str, Any] | None = None
    missing_fields: list[str] = Field(default_factory=list)
    missing_items: list[dict[str, Any]] | None = None
    # Assistant LLM observability (no secrets)
    reply_source: str = "rules"
    llm_provider: str | None = None
    llm_failover_used: bool = False
    llm_failover_attempts: list[dict[str, Any]] | None = None


class IntentRequest(BaseModel):
    text: str = Field(min_length=1, max_length=8000)


class IntentResponse(BaseModel):
    intent: str = "create_entry"
    data: dict[str, Any]
    missing_fields: list[str] = Field(default_factory=list)
    reply_text: str
    tokens_used_month: int = 0


class DecisionOut(BaseModel):
    action: Literal["create_purchase", "create_item", "create_supplier", "report"]
    data: dict[str, Any] = Field(default_factory=dict)
    warnings: list[str] = Field(default_factory=list)
    suggestions: list[str] = Field(default_factory=list)
    missing_fields: list[str] = Field(default_factory=list)
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)
    session_id: uuid.UUID | None = None
    decision_id: uuid.UUID | None = None


class DecisionRequest(BaseModel):
    message: str = Field(min_length=1, max_length=8000)
    session_id: uuid.UUID | None = None


class ValidateRequest(BaseModel):
    action: Literal["create_purchase", "create_item", "create_supplier", "report"]
    data: dict[str, Any] = Field(default_factory=dict)
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)


class ValidateResponse(BaseModel):
    valid: bool
    errors: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    suggestions: list[str] = Field(default_factory=list)
    missing_fields: list[str] = Field(default_factory=list)


class CommitRequest(BaseModel):
    decision_id: uuid.UUID


class CommitResponse(BaseModel):
    committed: bool
    action: str
    record_id: str | None = None
    message: str = "ok"


def _norm(s: str) -> str:
    return " ".join((s or "").strip().lower().split())


def _score(a: str, b: str) -> float:
    return float(fuzz.token_sort_ratio(_norm(a), _norm(b)) / 100.0)


def _coerce_decision(raw: dict[str, Any]) -> DecisionOut:
    action = str(raw.get("action") or "").strip().lower()
    if action not in {"create_purchase", "create_item", "create_supplier", "report"}:
        action = "report"
    data = raw.get("data")
    data_map = data if isinstance(data, dict) else {}
    warnings = raw.get("warnings") if isinstance(raw.get("warnings"), list) else []
    suggestions = raw.get("suggestions") if isinstance(raw.get("suggestions"), list) else []
    missing = raw.get("missing_fields") if isinstance(raw.get("missing_fields"), list) else []
    try:
        conf = float(raw.get("confidence", 0.0))
    except Exception:  # noqa: BLE001
        conf = 0.0
    conf = max(0.0, min(1.0, conf))
    return DecisionOut(
        action=action,
        data=data_map,
        warnings=[str(x) for x in warnings],
        suggestions=[str(x) for x in suggestions],
        missing_fields=[str(x) for x in missing],
        confidence=conf,
    )


async def _get_or_create_session(
    db: AsyncSession,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    session_id: uuid.UUID | None = None,
) -> AssistantSession:
    if session_id is not None:
        r = await db.execute(
            select(AssistantSession).where(
                AssistantSession.id == session_id,
                AssistantSession.business_id == business_id,
                AssistantSession.user_id == user_id,
            )
        )
        s = r.scalar_one_or_none()
        if s is not None:
            return s
    r = await db.execute(
        select(AssistantSession)
        .where(
            AssistantSession.business_id == business_id,
            AssistantSession.user_id == user_id,
        )
        .order_by(AssistantSession.updated_at.desc())
        .limit(1)
    )
    s = r.scalar_one_or_none()
    if s is not None:
        return s
    s = AssistantSession(business_id=business_id, user_id=user_id, flow="idle", state_json={})
    db.add(s)
    await db.flush()
    return s


async def _validate_decision(
    db: AsyncSession,
    business_id: uuid.UUID,
    decision: DecisionOut,
) -> ValidateResponse:
    errors: list[str] = []
    warnings: list[str] = list(decision.warnings)
    suggestions: list[str] = list(decision.suggestions)
    missing_fields: list[str] = list(decision.missing_fields)
    d = decision.data

    if decision.confidence < 0.7:
        errors.append("confidence_below_threshold")

    if decision.action == "create_supplier":
        name = str(d.get("name") or "").strip()
        if not name:
            missing_fields.append("name")
        else:
            r = await db.execute(select(Supplier.id, Supplier.name).where(Supplier.business_id == business_id))
            for sid, sname in r.all():
                sim = _score(name, sname or "")
                if sim >= 0.85:
                    errors.append("duplicate_supplier")
                    suggestions.append(f"Use existing supplier '{sname}' ({sid})")
                    break
    elif decision.action == "create_item":
        name = str(d.get("name") or "").strip()
        category_id_raw = d.get("category_id")
        if not name:
            missing_fields.append("name")
        if not category_id_raw:
            missing_fields.append("category_id")
        if name and category_id_raw:
            try:
                category_id = uuid.UUID(str(category_id_raw))
            except ValueError:
                errors.append("invalid_category_id")
                category_id = None
            if category_id is not None:
                r = await db.execute(
                    select(CatalogItem.id, CatalogItem.name).where(
                        CatalogItem.business_id == business_id, CatalogItem.category_id == category_id
                    )
                )
                for iid, iname in r.all():
                    sim = _score(name, iname or "")
                    if sim >= 0.85:
                        errors.append("duplicate_item")
                        suggestions.append(f"Use existing item '{iname}' ({iid})")
                        break
    elif decision.action == "create_purchase":
        item_name = str(d.get("item_name") or "").strip()
        supplier_name = str(d.get("supplier_name") or "").strip()
        qty = d.get("qty")
        price = d.get("landing_cost")
        if not item_name:
            missing_fields.append("item_name")
        if not supplier_name:
            missing_fields.append("supplier_name")
        if qty is None:
            missing_fields.append("qty")
        if price is None:
            missing_fields.append("landing_cost")

        if item_name:
            aliases = await db.execute(
                select(CatalogAlias.name, CatalogAlias.ref_id).where(
                    CatalogAlias.business_id == business_id, CatalogAlias.alias_type == "item"
                )
            )
            for alias_name, ref_id in aliases.all():
                sim = _score(item_name, alias_name or "")
                if sim >= 0.85:
                    suggestions.append(f"Matched item alias '{alias_name}' -> {ref_id}")
                    break

        if item_name and price is not None:
            try:
                landing = float(price)
            except Exception:  # noqa: BLE001
                errors.append("invalid_landing_cost")
            else:
                avg_r = await db.execute(
                    select(func.avg(EntryLineItem.landing_cost))
                    .select_from(EntryLineItem)
                    .join(Entry, Entry.id == EntryLineItem.entry_id)
                    .where(
                        Entry.business_id == business_id,
                        func.lower(EntryLineItem.item_name) == _norm(item_name),
                    )
                )
                avg_val = avg_r.scalar()
                if avg_val is not None:
                    avg_float = float(avg_val)
                    if avg_float > 0 and landing > (avg_float * 1.08):
                        warnings.append("Price higher than usual")
                        suggestions.append(f"Historical avg for {item_name}: {avg_float:.2f}")

        if supplier_name:
            s_r = await db.execute(
                select(Supplier.id, Supplier.name).where(Supplier.business_id == business_id)
            )
            for sid, sname in s_r.all():
                sim = _score(supplier_name, sname or "")
                if sim >= 0.85:
                    suggestions.append(f"Best match supplier '{sname}' ({sid})")
                    break

    dedup_missing = sorted(set(missing_fields))
    valid = (len(errors) == 0) and (len(dedup_missing) == 0)
    return ValidateResponse(
        valid=valid,
        errors=errors,
        warnings=warnings,
        suggestions=suggestions,
        missing_fields=dedup_missing,
    )

@router.post("/chat", response_model=ChatResponse)
async def ai_chat(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(charge_ai_turn_for_business)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    body: ChatRequest,
):
    msgs = body.messages
    last = msgs[-1].content.strip()
    prior: str | None = None
    if len(msgs) > 1:
        parts: list[str] = []
        for cm in msgs[:-1][-10:]:
            c = (cm.content or "").strip()
            if not c:
                continue
            parts.append(f"{cm.role}: {c[:2000]}")
        prior = "\n".join(parts) if parts else None
    out = await run_app_assistant_turn(
        db=db,
        business_id=business_id,
        user_id=user.id,
        message=last,
        settings=settings,
        preview_token=body.preview_token,
        entry_draft=body.entry_draft,
        conversation_context=prior,
    )
    await log_usage(
        db,
        provider="ai",
        action="ai_chat",
        business_id=business_id,
        user_id=user.id,
        units=1,
    )
    prov = (settings.ai_provider or "stub").strip().lower()
    return ChatResponse(
        reply=out["reply"],
        model=prov if prov != "stub" else "assistant",
        tokens_used_month=user.ai_tokens_used_month,
        intent=out.get("intent") or "help",
        preview_token=out.get("preview_token"),
        entry_draft=out.get("entry_draft"),
        saved_entry=out.get("saved_entry"),
        missing_fields=out.get("missing_fields") or [],
        missing_items=out.get("missing_items"),
        reply_source=str(out.get("reply_source") or "rules"),
        llm_provider=out.get("llm_provider"),
        llm_failover_used=bool(out.get("llm_failover_used")),
        llm_failover_attempts=out.get("llm_failover_attempts"),
    )


@router.post("/intent", response_model=IntentResponse)
async def ai_intent(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(charge_ai_turn_for_business)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    body: IntentRequest,
):
    snap = await build_compact_business_snapshot(db, business_id) if settings.enable_ai else None
    llm = await extract_intent_json(
        user_text=body.text,
        settings=settings,
        db=db,
        business_snapshot=snap,
    )
    if llm is not None:
        await log_usage(
            db,
            provider=settings.ai_provider or "stub",
            action="ai_intent_llm",
            business_id=business_id,
            user_id=user.id,
            units=1,
        )
        return IntentResponse(
            intent=llm["intent"],
            data=llm["data"],
            missing_fields=llm["missing_fields"],
            reply_text=llm["reply_text"],
            tokens_used_month=user.ai_tokens_used_month,
        )
    await log_usage(
        db,
        provider="stub",
        action="ai_intent_stub",
        business_id=business_id,
        user_id=user.id,
        units=1,
    )
    data, missing = stub_intent_from_text(body.text)
    reply = (
        "Got a draft from your text. Review numbers — nothing is saved until you confirm in Entries."
        if not missing
        else "I need: " + ", ".join(missing) + ". Tap Entries and fill, or add detail to your message."
    )
    return IntentResponse(
        intent="create_entry",
        data=data,
        missing_fields=missing,
        reply_text=reply,
        tokens_used_month=user.ai_tokens_used_month,
    )


@router.post("/decision", response_model=DecisionOut)
async def ai_decision(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(charge_ai_turn_for_business)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    body: DecisionRequest,
):
    session = await _get_or_create_session(db, business_id, user.id, body.session_id)
    snapshot = await build_compact_business_snapshot(db, business_id) if settings.enable_ai else None
    llm = await extract_intent_json(
        user_text=body.message,
        settings=settings,
        db=db,
        business_snapshot=snapshot,
    )
    if llm is not None:
        decision_raw: dict[str, Any] = {
            "action": "create_purchase" if llm.get("intent") == "create_entry" else str(llm.get("intent") or "report"),
            "data": llm.get("data") or {},
            "missing_fields": llm.get("missing_fields") or [],
            "warnings": [],
            "suggestions": [],
            "confidence": 0.82 if not (llm.get("missing_fields") or []) else 0.66,
        }
    else:
        data, missing = stub_intent_from_text(body.message)
        decision_raw = {
            "action": "create_purchase",
            "data": data,
            "missing_fields": missing,
            "warnings": [],
            "suggestions": [],
            "confidence": 0.74 if not missing else 0.62,
        }

    decision = _coerce_decision(decision_raw)
    validation = await _validate_decision(db, business_id, decision)
    decision.warnings = validation.warnings
    decision.suggestions = validation.suggestions
    decision.missing_fields = validation.missing_fields

    session.flow = decision.action
    session.state_json = {
        "last_message": body.message,
        "last_action": decision.action,
        "missing_fields": decision.missing_fields,
    }
    rec = AssistantDecision(
        session_id=session.id,
        action=decision.action,
        payload_json=decision.data,
        validation_json=validation.model_dump(),
        status="validated" if validation.valid else "needs_input",
    )
    db.add(rec)
    await db.commit()
    decision.session_id = session.id
    decision.decision_id = rec.id
    return decision


@router.post("/validate", response_model=ValidateResponse)
async def ai_validate(
    business_id: uuid.UUID,
    _user: Annotated[User, Depends(charge_ai_turn_for_business)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: ValidateRequest,
):
    decision = DecisionOut(
        action=body.action,
        data=body.data,
        confidence=body.confidence,
        warnings=[],
        suggestions=[],
        missing_fields=[],
    )
    return await _validate_decision(db, business_id, decision)


@router.post("/commit", response_model=CommitResponse)
async def ai_commit(
    business_id: uuid.UUID,
    _user: Annotated[User, Depends(charge_ai_turn_for_business)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: CommitRequest,
):
    r = await db.execute(
        select(AssistantDecision, AssistantSession)
        .join(AssistantSession, AssistantSession.id == AssistantDecision.session_id)
        .where(
            AssistantDecision.id == body.decision_id,
            AssistantSession.business_id == business_id,
        )
    )
    row = r.one_or_none()
    if row is None:
        return CommitResponse(committed=False, action="unknown", message="decision_not_found")
    decision, session = row
    validation = decision.validation_json or {}
    if not bool(validation.get("valid")):
        return CommitResponse(committed=False, action=decision.action, message="validation_failed")

    payload = decision.payload_json or {}
    record_id: str | None = None

    if decision.action == "create_supplier":
        name = str(payload.get("name") or "").strip()
        supplier = Supplier(business_id=business_id, name=name)
        db.add(supplier)
        await db.flush()
        db.add(
            CatalogAlias(
                business_id=business_id,
                alias_type="supplier",
                ref_id=supplier.id,
                name=name,
                normalized_name=_norm(name),
            )
        )
        record_id = str(supplier.id)
    elif decision.action == "create_item":
        name = str(payload.get("name") or "").strip()
        category_id = uuid.UUID(str(payload.get("category_id")))
        type_id_raw = payload.get("type_id")
        type_id = uuid.UUID(str(type_id_raw)) if type_id_raw else None
        item = CatalogItem(
            business_id=business_id,
            category_id=category_id,
            type_id=type_id,
            name=name,
        )
        db.add(item)
        await db.flush()
        db.add(
            CatalogAlias(
                business_id=business_id,
                alias_type="item",
                ref_id=item.id,
                name=name,
                normalized_name=_norm(name),
            )
        )
        record_id = str(item.id)
    elif decision.action == "create_purchase":
        item_name = str(payload.get("item_name") or "").strip()
        supplier_name = str(payload.get("supplier_name") or "").strip()
        qty = float(payload.get("qty"))
        landing_cost = float(payload.get("landing_cost"))

        s = await db.execute(
            select(Supplier).where(
                Supplier.business_id == business_id,
                func.lower(Supplier.name) == _norm(supplier_name),
            )
        )
        supplier = s.scalar_one_or_none()
        if supplier is None:
            supplier = Supplier(business_id=business_id, name=supplier_name)
            db.add(supplier)
            await db.flush()

        e = Entry(
            business_id=business_id,
            user_id=session.user_id,
            supplier_id=supplier.id,
            entry_date=date.today(),
            status="confirmed",
            source="assistant",
        )
        db.add(e)
        await db.flush()

        line = EntryLineItem(
            entry_id=e.id,
            item_name=item_name,
            qty=qty,
            unit=str(payload.get("unit") or "kg"),
            buy_price=landing_cost,
            landing_cost=landing_cost,
        )
        db.add(line)
        record_id = str(e.id)
    elif decision.action == "report":
        decision.status = "committed"
        await db.commit()
        return CommitResponse(committed=True, action=decision.action, message="report_no_commit")
    else:
        return CommitResponse(committed=False, action=decision.action, message="unsupported_action")

    decision.status = "committed"
    await db.commit()
    return CommitResponse(committed=True, action=decision.action, record_id=record_id)


@router.get("/usage")
async def ai_usage_summary(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
) -> dict[str, Any]:
    """Owner-facing assistant API usage (today + last 7 days)."""
    del _m
    now = datetime.now(timezone.utc)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    week_start = today_start - timedelta(days=6)
    base = ApiUsageLog.business_id == business_id
    openai_filter = ApiUsageLog.provider.ilike("%openai%")
    r_today = await db.execute(
        select(
            func.count(ApiUsageLog.id),
            func.coalesce(func.sum(ApiUsageLog.units), 0),
            func.coalesce(func.sum(ApiUsageLog.cost_estimate_inr_paise), 0),
        ).where(base, openai_filter, ApiUsageLog.created_at >= today_start)
    )
    today_row = r_today.one()
    daily: list[dict[str, Any]] = []
    for offset in range(6, -1, -1):
        day = today_start - timedelta(days=offset)
        nxt = day + timedelta(days=1)
        r = await db.execute(
            select(func.count(ApiUsageLog.id)).where(
                base,
                openai_filter,
                ApiUsageLog.created_at >= day,
                ApiUsageLog.created_at < nxt,
            )
        )
        daily.append(
            {
                "date": day.date().isoformat(),
                "requests": int(r.scalar_one() or 0),
            }
        )
    paise = int(today_row[2] or 0)
    return {
        "requests_today": int(today_row[0] or 0),
        "tokens_used": int(today_row[1] or 0),
        "estimated_cost_inr": round(paise / 100.0, 2),
        "daily": daily,
    }
