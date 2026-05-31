"""Wholesale purchase documents (PUR-YYYY-XXXX) separate from legacy `entries`."""

import uuid
from datetime import date, datetime, timezone
from decimal import Decimal

from sqlalchemy import Date, DateTime, ForeignKey, Integer, Numeric, String, Text, UniqueConstraint, Uuid, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base
from app.models.contacts import Broker, Supplier


def utcnow():
    return datetime.now(timezone.utc)


class BrokerSupplierLink(Base):
    """M2M: broker can serve multiple suppliers (beyond legacy single broker_id on supplier)."""

    # Physical name avoids clashing with an existing pg_type named broker_supplier_links
    # (e.g. stray ENUM) on some managed Postgres instances.
    __tablename__ = "broker_supplier_m2m"
    __table_args__ = (UniqueConstraint("broker_id", "supplier_id", name="uq_broker_supplier_m2m_pair"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    broker_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("brokers.id"), index=True)
    supplier_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("suppliers.id"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class TradePurchase(Base):
    __tablename__ = "trade_purchases"
    __table_args__ = (UniqueConstraint("business_id", "human_id", name="uq_trade_purchases_business_human"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("users.id"), index=True)
    human_id: Mapped[str] = mapped_column(String(32), index=True)
    invoice_number: Mapped[str | None] = mapped_column(String(64), nullable=True)
    purchase_date: Mapped[date] = mapped_column(Date, index=True)
    supplier_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("suppliers.id"), index=True
    )
    broker_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("brokers.id"), nullable=True, index=True
    )
    payment_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    due_date: Mapped[date | None] = mapped_column(Date, nullable=True, index=True)
    paid_amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0)
    paid_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    discount: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    commission_percent: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    commission_mode: Mapped[str | None] = mapped_column(String(24), nullable=True)
    commission_money: Mapped[Decimal | None] = mapped_column(Numeric(14, 4), nullable=True)
    delivered_rate: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    billty_rate: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    freight_amount: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    freight_type: Mapped[str | None] = mapped_column(String(16), nullable=True)
    total_qty: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)
    total_amount: Mapped[Decimal] = mapped_column(Numeric(14, 2))
    # Pre-header charges: subtotals from lines (gross base; excludes header freight/commission in total_amount)
    total_landing_subtotal: Mapped[Decimal | None] = mapped_column(Numeric(14, 2), nullable=True)
    total_selling_subtotal: Mapped[Decimal | None] = mapped_column(Numeric(14, 2), nullable=True)
    total_line_profit: Mapped[Decimal | None] = mapped_column(Numeric(14, 2), nullable=True)
    status: Mapped[str] = mapped_column(String(24), default="confirmed")
    is_delivered: Mapped[bool] = mapped_column(default=False)
    delivery_status: Mapped[str] = mapped_column(String(30), default="pending")
    delivered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    delivery_notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    dispatched_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    arrived_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    staff_verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    staff_verified_by: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    staff_verified_by_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    stock_committed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    staff_verified_qty: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)
    delivered_qty_committed: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)
    dispatch_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    truck_number: Mapped[str | None] = mapped_column(String(100), nullable=True)
    driver_contact: Mapped[str | None] = mapped_column(String(100), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    lines = relationship("TradePurchaseLine", back_populates="purchase", cascade="all, delete-orphan")
    supplier_row = relationship(Supplier, foreign_keys=[supplier_id], lazy="selectin")
    broker_row = relationship(Broker, foreign_keys=[broker_id], lazy="selectin")


class TradePurchaseLine(Base):
    __tablename__ = "trade_purchase_lines"
    __table_args__ = (
        Index("ix_trade_purchase_lines_tp_id_item_name", "trade_purchase_id", "item_name"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    trade_purchase_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("trade_purchases.id", ondelete="CASCADE"), index=True
    )
    catalog_item_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("catalog_items.id"), index=True
    )
    item_name: Mapped[str] = mapped_column(String(512))
    qty: Mapped[Decimal] = mapped_column(Numeric(12, 3))
    unit: Mapped[str] = mapped_column(String(32))
    # Snapshot at confirm: qty converted to catalog stock_unit (bags for SUGAR 50 KG).
    qty_in_stock_unit: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)
    unit_type: Mapped[str | None] = mapped_column(String(16), nullable=True)
    # Canonical purchase-accounting fields. Legacy aliases below are kept during
    # rollout so older clients can still read/write the same purchase lines.
    purchase_rate: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    selling_rate: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    freight_type: Mapped[str | None] = mapped_column(String(16), nullable=True)
    freight_value: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    delivered_rate: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    billty_rate: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    weight_per_unit: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)
    total_weight: Mapped[Decimal | None] = mapped_column(Numeric(14, 3), nullable=True)
    line_total: Mapped[Decimal | None] = mapped_column(Numeric(14, 2), nullable=True)
    profit: Mapped[Decimal | None] = mapped_column(Numeric(14, 2), nullable=True)
    box_mode: Mapped[str | None] = mapped_column(String(24), nullable=True)
    items_per_box: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)
    weight_per_item: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)
    kg_per_box: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)
    weight_per_tin: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)
    landing_cost: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    # Weight lines (e.g. bag + per-kg): snapshot at purchase time. Totals use
    # qty * kg_per_unit * landing_cost_per_kg; landing_cost = kg_per_unit * landing_cost_per_kg per line unit.
    kg_per_unit: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)
    landing_cost_per_kg: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    selling_cost: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    discount: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    tax_percent: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    tax_mode: Mapped[str | None] = mapped_column(String(16), nullable=True, default="exclusive")
    payment_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    hsn_code: Mapped[str | None] = mapped_column(String(32), nullable=True)
    # Snapshot or override; falls back to catalog item_code in API when unset.
    item_code: Mapped[str | None] = mapped_column(String(64), nullable=True)
    description: Mapped[str | None] = mapped_column(String(512), nullable=True)
    received_qty: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)
    damaged_qty: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)
    return_qty: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)

    purchase = relationship("TradePurchase", back_populates="lines")
    catalog_item = relationship("CatalogItem", foreign_keys=[catalog_item_id], lazy="selectin")


class TradePurchaseDraft(Base):
    __tablename__ = "trade_purchase_drafts"
    __table_args__ = (UniqueConstraint("business_id", "user_id", name="uq_trade_purchase_drafts_biz_user"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("users.id"), index=True)
    step: Mapped[int] = mapped_column(default=0)
    payload_json: Mapped[str] = mapped_column(Text, default="{}")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)
