import uuid
from datetime import datetime, timezone
from decimal import Decimal

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, JSON, Numeric, String, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


def utcnow():
    return datetime.now(timezone.utc)


class ItemCategory(Base):
    __tablename__ = "item_categories"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    name: Mapped[str] = mapped_column(String(255))
    is_perishable: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    items = relationship("CatalogItem", back_populates="category", cascade="all, delete-orphan")
    category_types = relationship(
        "CategoryType", back_populates="category", cascade="all, delete-orphan"
    )


class CategoryType(Base):
    """Middle layer: Category (e.g. Rice) → Type (e.g. Biriyani rice) → catalog items / variants."""

    __tablename__ = "category_types"
    __table_args__ = (UniqueConstraint("category_id", "name", name="uq_category_types_name"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    category_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("item_categories.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    category = relationship("ItemCategory", back_populates="category_types")
    catalog_items = relationship("CatalogItem", back_populates="catalog_type")


class CatalogItem(Base):
    __tablename__ = "catalog_items"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    category_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("item_categories.id"), index=True)
    type_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("category_types.id", ondelete="SET NULL"), nullable=True, index=True
    )
    name: Mapped[str] = mapped_column(String(512))
    default_unit: Mapped[str | None] = mapped_column(String(32), nullable=True)
    default_kg_per_bag: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)
    default_items_per_box: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)
    default_weight_per_tin: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)
    hsn_code: Mapped[str | None] = mapped_column(String(32), nullable=True)
    # Packaging barcode (scanner / EAN); unique per business when set.
    barcode: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    # Internal business tracking code (shelf label, PDFs, reports).
    item_code: Mapped[str | None] = mapped_column(String(64), nullable=True)
    tax_percent: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    default_landing_cost: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    default_selling_cost: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    default_purchase_unit: Mapped[str | None] = mapped_column(String(32), nullable=True)
    default_sale_unit: Mapped[str | None] = mapped_column(String(32), nullable=True)
    last_purchase_price: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    # Snapshot from last **confirmed** trade line (search / item hero / autofill SSOT).
    last_selling_rate: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    last_supplier_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("suppliers.id", ondelete="SET NULL"), nullable=True, index=True
    )
    last_broker_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("brokers.id", ondelete="SET NULL"), nullable=True, index=True
    )
    last_trade_purchase_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("trade_purchases.id", ondelete="SET NULL"), nullable=True, index=True
    )
    last_line_qty: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)
    last_line_unit: Mapped[str | None] = mapped_column(String(32), nullable=True)
    last_line_weight_kg: Mapped[Decimal | None] = mapped_column(Numeric(14, 3), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    # Smart unit / packaging intelligence (nullable — backfilled by classifier + ops).
    normalized_name: Mapped[str | None] = mapped_column(String(512), nullable=True, index=True)
    selling_unit: Mapped[str | None] = mapped_column(String(32), nullable=True)
    stock_unit: Mapped[str | None] = mapped_column(String(32), nullable=True)
    display_unit: Mapped[str | None] = mapped_column(String(32), nullable=True)
    package_type: Mapped[str | None] = mapped_column(String(32), nullable=True)
    package_size: Mapped[Decimal | None] = mapped_column(Numeric(14, 4), nullable=True)
    package_measurement: Mapped[str | None] = mapped_column(String(16), nullable=True)
    package_volume: Mapped[Decimal | None] = mapped_column(Numeric(14, 4), nullable=True)
    package_weight: Mapped[Decimal | None] = mapped_column(Numeric(14, 4), nullable=True)
    conversion_factor: Mapped[Decimal | None] = mapped_column(Numeric(14, 6), nullable=True)
    ai_detected_unit: Mapped[str | None] = mapped_column(String(32), nullable=True)
    smart_classification: Mapped[str | None] = mapped_column(String(64), nullable=True)
    unit_confidence: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    packaging_confidence: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    is_loose_item: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    is_packaged_item: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    auto_detect_enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    ml_profile: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    validation_status: Mapped[str | None] = mapped_column(String(32), nullable=True)
    current_stock: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True, default=Decimal("0"))
    reorder_level: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True, default=Decimal("0"))
    rack_location: Mapped[str | None] = mapped_column(String(100), nullable=True)
    last_stock_updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_stock_updated_by: Mapped[str | None] = mapped_column(String(255), nullable=True)
    eviction_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    last_purchase_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_by_user_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    updated_by_user_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
    archived_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    category = relationship("ItemCategory", back_populates="items")
    catalog_type = relationship("CategoryType", back_populates="catalog_items")
    variants = relationship("CatalogVariant", back_populates="item", cascade="all, delete-orphan")
    default_supplier_links = relationship(
        "CatalogItemDefaultSupplier",
        back_populates="catalog_item",
        cascade="all, delete-orphan",
    )
    default_broker_links = relationship(
        "CatalogItemDefaultBroker",
        back_populates="catalog_item",
        cascade="all, delete-orphan",
    )
    packaging_profiles = relationship(
        "ItemPackagingProfile",
        back_populates="catalog_item",
        cascade="all, delete-orphan",
    )


class CatalogItemDefaultSupplier(Base):
    __tablename__ = "catalog_item_default_suppliers"
    __table_args__ = (UniqueConstraint("catalog_item_id", "supplier_id", name="uq_citem_def_supplier"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("businesses.id", ondelete="CASCADE"), index=True
    )
    catalog_item_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("catalog_items.id", ondelete="CASCADE"), index=True
    )
    supplier_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("suppliers.id", ondelete="CASCADE"), index=True
    )
    sort_order: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    catalog_item = relationship("CatalogItem", back_populates="default_supplier_links")


class CatalogItemDefaultBroker(Base):
    __tablename__ = "catalog_item_default_brokers"
    __table_args__ = (UniqueConstraint("catalog_item_id", "broker_id", name="uq_citem_def_broker"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("businesses.id", ondelete="CASCADE"), index=True
    )
    catalog_item_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("catalog_items.id", ondelete="CASCADE"), index=True
    )
    broker_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("brokers.id", ondelete="CASCADE"), index=True
    )
    sort_order: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    catalog_item = relationship("CatalogItem", back_populates="default_broker_links")


class CatalogVariant(Base):
    """Granular product under a catalog item (e.g. Grains → Rice → Basmati)."""

    __tablename__ = "catalog_variants"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    business_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("businesses.id"), index=True)
    catalog_item_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("catalog_items.id"), index=True
    )
    name: Mapped[str] = mapped_column(String(512))
    default_kg_per_bag: Mapped[Decimal | None] = mapped_column(Numeric(12, 3), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    item = relationship("CatalogItem", back_populates="variants")
