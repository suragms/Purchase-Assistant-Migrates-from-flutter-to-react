import uuid
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import Date, DateTime, ForeignKey, Numeric, String, Text, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class StockAudit(Base):
    __tablename__ = "stock_audits"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    audit_date: Mapped[date] = mapped_column(Date, default=func.current_date(), nullable=False)
    auditor_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    business_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("businesses.id", ondelete="CASCADE"), nullable=True, index=True
    )
    status: Mapped[str] = mapped_column(
        String(32), default="draft", nullable=False
    )  # draft, pending_review, completed
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=func.now(), onupdate=func.now(), nullable=False
    )

    auditor = relationship("User")
    items = relationship(
        "StockAuditItem",
        back_populates="audit",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )


class StockAuditItem(Base):
    __tablename__ = "stock_audit_items"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    audit_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("stock_audits.id", ondelete="CASCADE"), nullable=False, index=True
    )
    item_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("catalog_items.id", ondelete="CASCADE"), nullable=False, index=True
    )
    system_qty: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    counted_qty: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    difference_qty: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    line_status: Mapped[str] = mapped_column(String(32), default="recorded", nullable=False)
    adjustment_type: Mapped[str | None] = mapped_column(String(32), nullable=True)
    reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    audit = relationship("StockAudit", back_populates="items")
    item = relationship("CatalogItem")
