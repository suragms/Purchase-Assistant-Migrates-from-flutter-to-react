"""SQLite / local dev: create_all + incremental ALTERs for old DBs.

Production Postgres must use Alembic only; see `main.py` lifespan.
"""

from __future__ import annotations

import logging
import uuid

from sqlalchemy import inspect

from app.models import Base
from app.models.report_saved_view import ReportSavedView
from app.models.unit_intelligence import (
    AiItemProfile,
    ItemLearningHistory,
    ItemPackagingProfile,
    MasterUnit,
    OcrItemAlias,
    SmartPackageRule,
    SmartUnitRule,
    UnitConfidenceLog,
)

logger = logging.getLogger(__name__)


def apply_sqlite_bootstrap(sync_conn) -> None:
    """Build schema and patch legacy SQLite columns (create_all does not ALTER)."""
    Base.metadata.create_all(sync_conn)
    Base.metadata.create_all(
        sync_conn,
        tables=[
            MasterUnit.__table__,
            ItemPackagingProfile.__table__,
            OcrItemAlias.__table__,
            SmartUnitRule.__table__,
            ItemLearningHistory.__table__,
            UnitConfidenceLog.__table__,
            AiItemProfile.__table__,
            SmartPackageRule.__table__,
            ReportSavedView.__table__,
        ],
    )
    _ensure_entries_place(sync_conn)
    _ensure_suppliers_whatsapp_number(sync_conn)
    _ensure_entry_line_items_stock_note(sync_conn)
    _ensure_businesses_branding(sync_conn)
    _ensure_users_ai_budget_columns(sync_conn)
    _ensure_users_modern_columns(sync_conn)
    _ensure_memberships_columns(sync_conn)
    _ensure_catalog_items_type_id(sync_conn)
    _ensure_catalog_items_item_code(sync_conn)
    _ensure_catalog_items_barcode(sync_conn)
    _ensure_catalog_items_public_token(sync_conn)
    _ensure_catalog_items_opening_stock(sync_conn)
    _ensure_notifications_columns(sync_conn)
    _ensure_item_categories_columns(sync_conn)
    _ensure_stock_physical_counts(sync_conn)
    _ensure_stock_movements(sync_conn)
    _ensure_staff_purchase_logs(sync_conn)
    _ensure_supplier_wholesale_columns(sync_conn)
    _ensure_supplier_profile_columns(sync_conn)
    _ensure_broker_phone_column(sync_conn)
    _ensure_catalog_item_trade_columns(sync_conn)
    _ensure_trade_purchases_freight_type(sync_conn)
    _ensure_trade_purchases_lifecycle_columns(sync_conn)
    _ensure_trade_purchases_commission_mode_columns(sync_conn)
    _ensure_trade_purchases_delivery_columns(sync_conn)
    _ensure_trade_purchase_line_columns(sync_conn)
    _ensure_catalog_items_smart_unit_columns(sync_conn)
    _ensure_catalog_items_stock_columns(sync_conn)
    _ensure_box_default_items_per_box(sync_conn)
    logger.info("SQLite bootstrap: create_all + legacy column patches complete")


def _ensure_entries_place(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("entries"):
        return
    cols = {c["name"] for c in insp.get_columns("entries")}
    if "place" in cols:
        return
    sync_conn.exec_driver_sql("ALTER TABLE entries ADD COLUMN place VARCHAR(512)")


def _ensure_suppliers_whatsapp_number(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("suppliers"):
        return
    cols = {c["name"] for c in insp.get_columns("suppliers")}
    if "whatsapp_number" in cols:
        return
    sync_conn.exec_driver_sql("ALTER TABLE suppliers ADD COLUMN whatsapp_number VARCHAR(32)")


def _ensure_entry_line_items_stock_note(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("entry_line_items"):
        return
    cols = {c["name"] for c in insp.get_columns("entry_line_items")}
    if "stock_note" in cols:
        return
    sync_conn.exec_driver_sql("ALTER TABLE entry_line_items ADD COLUMN stock_note VARCHAR(512)")


def _ensure_businesses_branding(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("businesses"):
        return
    cols = {c["name"] for c in insp.get_columns("businesses")}
    dialect = sync_conn.dialect.name
    if "branding_title" not in cols:
        sync_conn.exec_driver_sql("ALTER TABLE businesses ADD COLUMN branding_title VARCHAR(128)")
    if "branding_logo_url" not in cols:
        sync_conn.exec_driver_sql("ALTER TABLE businesses ADD COLUMN branding_logo_url VARCHAR(512)")
    if "gst_number" not in cols:
        sync_conn.exec_driver_sql("ALTER TABLE businesses ADD COLUMN gst_number VARCHAR(20)")
    if "address" not in cols:
        sync_conn.exec_driver_sql("ALTER TABLE businesses ADD COLUMN address TEXT")
    if "phone" not in cols:
        sync_conn.exec_driver_sql("ALTER TABLE businesses ADD COLUMN phone VARCHAR(32)")
    if "contact_email" not in cols:
        if dialect == "postgresql":
            sync_conn.exec_driver_sql(
                "ALTER TABLE businesses ADD COLUMN IF NOT EXISTS contact_email VARCHAR(255) NULL"
            )
        else:
            sync_conn.exec_driver_sql("ALTER TABLE businesses ADD COLUMN contact_email VARCHAR(255) NULL")
    if "accounts_whatsapp_number" not in cols:
        sync_conn.exec_driver_sql(
            "ALTER TABLE businesses ADD COLUMN accounts_whatsapp_number VARCHAR(20) NULL"
        )
    if "default_currency" not in cols:
        if dialect == "postgresql":
            sync_conn.exec_driver_sql(
                "ALTER TABLE businesses ADD COLUMN IF NOT EXISTS default_currency VARCHAR(3) NOT NULL DEFAULT 'INR'"
            )
        else:
            sync_conn.exec_driver_sql(
                "ALTER TABLE businesses ADD COLUMN default_currency VARCHAR(3) NOT NULL DEFAULT 'INR'"
            )


def _ensure_users_ai_budget_columns(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("users"):
        return
    cols = {c["name"] for c in insp.get_columns("users")}
    if "ai_monthly_token_budget" not in cols:
        sync_conn.exec_driver_sql(
            "ALTER TABLE users ADD COLUMN ai_monthly_token_budget INTEGER DEFAULT 100000"
        )
    if "ai_tokens_used_month" not in cols:
        sync_conn.exec_driver_sql(
            "ALTER TABLE users ADD COLUMN ai_tokens_used_month INTEGER DEFAULT 0 NOT NULL"
        )


def _ensure_users_modern_columns(sync_conn):
    """Patch legacy SQLite users table for auth session fields."""
    insp = inspect(sync_conn)
    if not insp.has_table("users"):
        return
    cols = {c["name"] for c in insp.get_columns("users")}
    if "is_active" not in cols:
        sync_conn.exec_driver_sql(
            "ALTER TABLE users ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT 1"
        )
    if "last_login_at" not in cols:
        sync_conn.exec_driver_sql("ALTER TABLE users ADD COLUMN last_login_at DATETIME NULL")
    if "last_active_at" not in cols:
        sync_conn.exec_driver_sql("ALTER TABLE users ADD COLUMN last_active_at DATETIME NULL")
    if "device_info" not in cols:
        sync_conn.exec_driver_sql("ALTER TABLE users ADD COLUMN device_info JSON NULL")
    if "created_by" not in cols:
        sync_conn.exec_driver_sql("ALTER TABLE users ADD COLUMN created_by CHAR(32) NULL")
    if "is_blocked" not in cols:
        sync_conn.exec_driver_sql(
            "ALTER TABLE users ADD COLUMN is_blocked BOOLEAN NOT NULL DEFAULT 0"
        )
    if "notes" not in cols:
        sync_conn.exec_driver_sql("ALTER TABLE users ADD COLUMN notes VARCHAR(2000) NULL")
    if "deleted_at" not in cols:
        sync_conn.exec_driver_sql("ALTER TABLE users ADD COLUMN deleted_at DATETIME NULL")
    if "google_sub" not in cols:
        sync_conn.exec_driver_sql("ALTER TABLE users ADD COLUMN google_sub VARCHAR(128) NULL")


def _ensure_catalog_items_type_id(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("catalog_items"):
        return
    cols = {c["name"] for c in insp.get_columns("catalog_items")}
    if "type_id" in cols:
        return
    dialect = sync_conn.dialect.name
    if dialect == "postgresql":
        sync_conn.exec_driver_sql("ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS type_id UUID NULL")
        if insp.has_table("category_types"):
            sync_conn.exec_driver_sql(
                "CREATE INDEX IF NOT EXISTS ix_catalog_items_type_id ON catalog_items (type_id)"
            )
            sync_conn.exec_driver_sql(
                """
                DO $do$
                BEGIN
                  IF NOT EXISTS (
                    SELECT 1 FROM pg_constraint
                    WHERE conname = 'catalog_items_type_id_fkey'
                  ) THEN
                    ALTER TABLE catalog_items
                      ADD CONSTRAINT catalog_items_type_id_fkey
                      FOREIGN KEY (type_id) REFERENCES category_types(id) ON DELETE SET NULL;
                  END IF;
                END
                $do$;
                """
            )
    else:
        try:
            sync_conn.exec_driver_sql("ALTER TABLE catalog_items ADD COLUMN type_id VARCHAR(36) NULL")
        except Exception:  # noqa: BLE001
            pass


def _ensure_catalog_items_item_code(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("catalog_items"):
        return
    cols = {c["name"] for c in insp.get_columns("catalog_items")}
    if "item_code" in cols:
        return
    try:
        sync_conn.exec_driver_sql("ALTER TABLE catalog_items ADD COLUMN item_code VARCHAR(64) NULL")
    except Exception:  # noqa: BLE001
        pass


def _ensure_catalog_items_barcode(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("catalog_items"):
        return
    cols = {c["name"] for c in insp.get_columns("catalog_items")}
    if "barcode" in cols:
        return
    try:
        sync_conn.exec_driver_sql("ALTER TABLE catalog_items ADD COLUMN barcode VARCHAR(64) NULL")
    except Exception:  # noqa: BLE001
        pass


def _ensure_catalog_items_public_token(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("catalog_items"):
        return
    cols = {c["name"] for c in insp.get_columns("catalog_items")}
    if "public_token" not in cols:
        try:
            sync_conn.exec_driver_sql("ALTER TABLE catalog_items ADD COLUMN public_token VARCHAR(64) NULL")
        except Exception:  # noqa: BLE001
            pass
    rows = sync_conn.exec_driver_sql(
        "SELECT id FROM catalog_items WHERE public_token IS NULL OR public_token = ''"
    ).fetchall()
    for row in rows:
        sync_conn.exec_driver_sql(
            "UPDATE catalog_items SET public_token = ? WHERE id = ?",
            (uuid.uuid4().hex, row[0]),
        )


def _ensure_stock_physical_counts(sync_conn):
    insp = inspect(sync_conn)
    if insp.has_table("stock_physical_counts"):
        return
    sync_conn.exec_driver_sql(
        """
        CREATE TABLE stock_physical_counts (
            id CHAR(32) PRIMARY KEY,
            business_id CHAR(32) NOT NULL,
            item_id CHAR(32) NOT NULL,
            system_qty NUMERIC(12,3) NOT NULL,
            counted_qty NUMERIC(12,3) NOT NULL,
            difference_qty NUMERIC(12,3) NOT NULL,
            purchased_qty NUMERIC(12,3) NULL,
            stock_unit VARCHAR(32) NULL,
            period_start DATE NULL,
            period_end DATE NULL,
            notes TEXT NULL,
            counted_by CHAR(32) NULL,
            counted_by_name VARCHAR(255) NULL,
            counted_at DATETIME NULL
        )
        """
    )
    sync_conn.exec_driver_sql(
        "CREATE INDEX IF NOT EXISTS ix_stock_physical_counts_business_item_counted "
        "ON stock_physical_counts (business_id, item_id, counted_at)"
    )


def _ensure_catalog_items_opening_stock(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("catalog_items"):
        return
    cols = {c["name"] for c in insp.get_columns("catalog_items")}
    alters = []
    if "opening_stock_qty" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN opening_stock_qty NUMERIC(12,3) NULL")
    if "opening_stock_set_at" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN opening_stock_set_at DATETIME NULL")
    if "opening_stock_set_by" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN opening_stock_set_by VARCHAR(255) NULL")
    if "opening_stock_locked" not in cols:
        alters.append(
            "ALTER TABLE catalog_items ADD COLUMN opening_stock_locked BOOLEAN NOT NULL DEFAULT 0"
        )
    for sql in alters:
        try:
            sync_conn.exec_driver_sql(sql)
        except Exception:  # noqa: BLE001
            pass


def _ensure_notifications_columns(sync_conn):
    """Patch legacy SQLite notifications table for AppNotification ORM fields."""
    insp = inspect(sync_conn)
    if not insp.has_table("notifications"):
        return
    cols = {c["name"] for c in insp.get_columns("notifications")}
    alters = []
    if "priority" not in cols:
        alters.append(
            "ALTER TABLE notifications ADD COLUMN priority VARCHAR(16) NOT NULL DEFAULT 'medium'"
        )
    if "category" not in cols:
        alters.append(
            "ALTER TABLE notifications ADD COLUMN category VARCHAR(32) NOT NULL DEFAULT 'system'"
        )
    if "action_route" not in cols:
        alters.append("ALTER TABLE notifications ADD COLUMN action_route VARCHAR(256) NULL")
    if "triggered_by_user_id" not in cols:
        alters.append("ALTER TABLE notifications ADD COLUMN triggered_by_user_id CHAR(32) NULL")
    if "related_item_id" not in cols:
        alters.append("ALTER TABLE notifications ADD COLUMN related_item_id CHAR(32) NULL")
    if "related_purchase_id" not in cols:
        alters.append("ALTER TABLE notifications ADD COLUMN related_purchase_id CHAR(32) NULL")
    if "related_supplier_id" not in cols:
        alters.append("ALTER TABLE notifications ADD COLUMN related_supplier_id CHAR(32) NULL")
    if "metadata" not in cols:
        alters.append("ALTER TABLE notifications ADD COLUMN metadata JSON NULL")
    for sql in alters:
        try:
            sync_conn.exec_driver_sql(sql)
        except Exception:  # noqa: BLE001
            pass


def _ensure_item_categories_columns(sync_conn):
    """Patch legacy SQLite item_categories (e.g. is_perishable for stock alerts)."""
    insp = inspect(sync_conn)
    if not insp.has_table("item_categories"):
        return
    cols = {c["name"] for c in insp.get_columns("item_categories")}
    if "is_perishable" not in cols:
        try:
            sync_conn.exec_driver_sql(
                "ALTER TABLE item_categories ADD COLUMN is_perishable BOOLEAN NOT NULL DEFAULT 0"
            )
        except Exception:  # noqa: BLE001
            pass


def _ensure_staff_purchase_logs(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("staff_purchase_logs"):
        sync_conn.exec_driver_sql(
            """
            CREATE TABLE staff_purchase_logs (
                id CHAR(32) PRIMARY KEY,
                business_id CHAR(32) NOT NULL,
                item_id CHAR(32) NOT NULL,
                item_name VARCHAR(512) NOT NULL,
                qty NUMERIC(12,3) NOT NULL,
                unit VARCHAR(32) NULL,
                amount NUMERIC(12,2) NULL,
                supplier_id CHAR(32) NULL,
                supplier_name VARCHAR(255) NULL,
                broker_id CHAR(32) NULL,
                broker_name VARCHAR(255) NULL,
                notes TEXT NULL,
                idempotency_key VARCHAR(120) NULL,
                stock_movement_id CHAR(32) NULL,
                created_by CHAR(32) NULL,
                created_by_name VARCHAR(255) NULL,
                created_at DATETIME NULL
            )
            """
        )
    else:
        cols = {c["name"] for c in insp.get_columns("staff_purchase_logs")}
        alters = []
        if "supplier_id" not in cols:
            alters.append("ALTER TABLE staff_purchase_logs ADD COLUMN supplier_id CHAR(32) NULL")
        if "broker_id" not in cols:
            alters.append("ALTER TABLE staff_purchase_logs ADD COLUMN broker_id CHAR(32) NULL")
        if "broker_name" not in cols:
            alters.append("ALTER TABLE staff_purchase_logs ADD COLUMN broker_name VARCHAR(255) NULL")
        if "idempotency_key" not in cols:
            alters.append("ALTER TABLE staff_purchase_logs ADD COLUMN idempotency_key VARCHAR(120) NULL")
        if "stock_movement_id" not in cols:
            alters.append("ALTER TABLE staff_purchase_logs ADD COLUMN stock_movement_id CHAR(32) NULL")
        for sql in alters:
            try:
                sync_conn.exec_driver_sql(sql)
            except Exception:  # noqa: BLE001
                pass
    sync_conn.exec_driver_sql(
        "CREATE INDEX IF NOT EXISTS ix_staff_purchase_logs_business_created "
        "ON staff_purchase_logs (business_id, created_at)"
    )


def _ensure_stock_movements(sync_conn):
    insp = inspect(sync_conn)
    if insp.has_table("stock_movements"):
        return
    sync_conn.exec_driver_sql(
        """
        CREATE TABLE stock_movements (
            id CHAR(32) PRIMARY KEY,
            business_id CHAR(32) NOT NULL,
            item_id CHAR(32) NOT NULL,
            movement_kind VARCHAR(50) NOT NULL,
            delta_qty NUMERIC(12,3) NOT NULL,
            qty_before NUMERIC(12,3) NOT NULL,
            qty_after NUMERIC(12,3) NOT NULL,
            stock_unit VARCHAR(32) NULL,
            reason VARCHAR(255) NULL,
            notes TEXT NULL,
            source_type VARCHAR(50) NULL,
            source_id CHAR(32) NULL,
            idempotency_key VARCHAR(120) NOT NULL,
            actor_id CHAR(32) NULL,
            actor_name VARCHAR(255) NULL,
            metadata_json JSON NULL,
            created_at DATETIME NULL
        )
        """
    )
    sync_conn.exec_driver_sql(
        "CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_movements_business_idempotency "
        "ON stock_movements (business_id, idempotency_key)"
    )


def _ensure_supplier_wholesale_columns(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("suppliers"):
        return
    cols = {c["name"] for c in insp.get_columns("suppliers")}
    alters: list[str] = []
    if "gst_number" not in cols:
        alters.append("ALTER TABLE suppliers ADD COLUMN gst_number VARCHAR(20)")
    if "default_payment_days" not in cols:
        alters.append("ALTER TABLE suppliers ADD COLUMN default_payment_days INTEGER")
    if "default_discount" not in cols:
        alters.append("ALTER TABLE suppliers ADD COLUMN default_discount NUMERIC(5, 2)")
    if "default_delivered_rate" not in cols:
        alters.append("ALTER TABLE suppliers ADD COLUMN default_delivered_rate NUMERIC(12, 2)")
    if "default_billty_rate" not in cols:
        alters.append("ALTER TABLE suppliers ADD COLUMN default_billty_rate NUMERIC(12, 2)")
    for sql in alters:
        try:
            sync_conn.exec_driver_sql(sql)
        except Exception:  # noqa: BLE001
            pass


def _ensure_supplier_profile_columns(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("suppliers"):
        return
    cols = {c["name"] for c in insp.get_columns("suppliers")}
    alters: list[str] = []
    if "address" not in cols:
        alters.append("ALTER TABLE suppliers ADD COLUMN address TEXT")
    if "notes" not in cols:
        alters.append("ALTER TABLE suppliers ADD COLUMN notes TEXT")
    if "freight_type" not in cols:
        alters.append("ALTER TABLE suppliers ADD COLUMN freight_type VARCHAR(16)")
    if "ai_memory_enabled" not in cols:
        dialect = sync_conn.dialect.name
        if dialect == "postgresql":
            alters.append("ALTER TABLE suppliers ADD COLUMN ai_memory_enabled BOOLEAN NOT NULL DEFAULT false")
        else:
            alters.append("ALTER TABLE suppliers ADD COLUMN ai_memory_enabled INTEGER NOT NULL DEFAULT 0")
    if "preferences_json" not in cols:
        alters.append("ALTER TABLE suppliers ADD COLUMN preferences_json TEXT")
    for sql in alters:
        try:
            sync_conn.exec_driver_sql(sql)
        except Exception:  # noqa: BLE001
            pass


def _ensure_broker_phone_column(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("brokers"):
        return
    cols = {c["name"] for c in insp.get_columns("brokers")}
    alters: list[str] = []
    if "phone" not in cols:
        alters.append("ALTER TABLE brokers ADD COLUMN phone VARCHAR(15)")
    if "whatsapp_number" not in cols:
        alters.append("ALTER TABLE brokers ADD COLUMN whatsapp_number VARCHAR(32)")
    if "location" not in cols:
        alters.append("ALTER TABLE brokers ADD COLUMN location TEXT")
    if "notes" not in cols:
        alters.append("ALTER TABLE brokers ADD COLUMN notes TEXT")
    if "preferences_json" not in cols:
        alters.append("ALTER TABLE brokers ADD COLUMN preferences_json TEXT")
    if "default_payment_days" not in cols:
        alters.append("ALTER TABLE brokers ADD COLUMN default_payment_days INTEGER")
    if "default_discount" not in cols:
        alters.append("ALTER TABLE brokers ADD COLUMN default_discount NUMERIC(5, 2)")
    if "default_delivered_rate" not in cols:
        alters.append("ALTER TABLE brokers ADD COLUMN default_delivered_rate NUMERIC(12, 2)")
    if "default_billty_rate" not in cols:
        alters.append("ALTER TABLE brokers ADD COLUMN default_billty_rate NUMERIC(12, 2)")
    if "freight_type" not in cols:
        alters.append("ALTER TABLE brokers ADD COLUMN freight_type VARCHAR(16)")
    if "image_url" not in cols:
        alters.append("ALTER TABLE brokers ADD COLUMN image_url VARCHAR(1024)")
    for sql in alters:
        try:
            sync_conn.exec_driver_sql(sql)
        except Exception:  # noqa: BLE001
            pass


def _ensure_catalog_item_trade_columns(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("catalog_items"):
        return
    cols = {c["name"] for c in insp.get_columns("catalog_items")}
    alters: list[str] = []
    if "hsn_code" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN hsn_code VARCHAR(32)")
    if "tax_percent" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN tax_percent NUMERIC(5, 2)")
    if "default_landing_cost" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN default_landing_cost NUMERIC(12, 2)")
    if "default_selling_cost" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN default_selling_cost NUMERIC(12, 2)")
    if "default_purchase_unit" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN default_purchase_unit VARCHAR(32)")
    if "default_sale_unit" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN default_sale_unit VARCHAR(32)")
    if "last_purchase_price" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN last_purchase_price NUMERIC(12, 2)")
    if "default_items_per_box" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN default_items_per_box NUMERIC(12, 3)")
    if "default_weight_per_tin" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN default_weight_per_tin NUMERIC(12, 3)")
    if "last_selling_rate" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN last_selling_rate NUMERIC(12, 2)")
    if "last_supplier_id" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN last_supplier_id VARCHAR(36)")
    if "last_broker_id" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN last_broker_id VARCHAR(36)")
    if "last_trade_purchase_id" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN last_trade_purchase_id VARCHAR(36)")
    if "last_line_qty" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN last_line_qty NUMERIC(12, 3)")
    if "last_line_unit" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN last_line_unit VARCHAR(32)")
    if "last_line_weight_kg" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN last_line_weight_kg NUMERIC(14, 3)")
    for sql in alters:
        try:
            sync_conn.exec_driver_sql(sql)
        except Exception:  # noqa: BLE001
            pass


def _ensure_trade_purchases_freight_type(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("trade_purchases"):
        return
    cols = {c["name"] for c in insp.get_columns("trade_purchases")}
    if "freight_type" not in cols:
        try:
            sync_conn.exec_driver_sql("ALTER TABLE trade_purchases ADD COLUMN freight_type VARCHAR(16)")
        except Exception:  # noqa: BLE001
            pass


def _ensure_trade_purchases_lifecycle_columns(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("trade_purchases"):
        return
    cols = {c["name"] for c in insp.get_columns("trade_purchases")}
    dialect = sync_conn.dialect.name
    alters: list[str] = []
    if "due_date" not in cols:
        if dialect == "postgresql":
            alters.append("ALTER TABLE trade_purchases ADD COLUMN IF NOT EXISTS due_date DATE NULL")
        else:
            alters.append("ALTER TABLE trade_purchases ADD COLUMN due_date DATE")
    if "paid_amount" not in cols:
        if dialect == "postgresql":
            alters.append(
                "ALTER TABLE trade_purchases ADD COLUMN IF NOT EXISTS paid_amount NUMERIC(14,2) NOT NULL DEFAULT 0"
            )
        else:
            alters.append("ALTER TABLE trade_purchases ADD COLUMN paid_amount NUMERIC(14,2) NOT NULL DEFAULT 0")
    if "paid_at" not in cols:
        if dialect == "postgresql":
            alters.append("ALTER TABLE trade_purchases ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ NULL")
        else:
            alters.append("ALTER TABLE trade_purchases ADD COLUMN paid_at DATETIME")
    if "payment_days" not in cols:
        if dialect == "postgresql":
            alters.append("ALTER TABLE trade_purchases ADD COLUMN IF NOT EXISTS payment_days INTEGER NULL")
        else:
            alters.append("ALTER TABLE trade_purchases ADD COLUMN payment_days INTEGER")
    if "invoice_number" not in cols:
        if dialect == "postgresql":
            alters.append(
                "ALTER TABLE trade_purchases ADD COLUMN IF NOT EXISTS invoice_number VARCHAR(64) NULL"
            )
        else:
            alters.append("ALTER TABLE trade_purchases ADD COLUMN invoice_number VARCHAR(64) NULL")
    for sql in alters:
        try:
            sync_conn.exec_driver_sql(sql)
        except Exception:  # noqa: BLE001
            pass


def _ensure_trade_purchases_commission_mode_columns(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("trade_purchases"):
        return
    cols = {c["name"] for c in insp.get_columns("trade_purchases")}
    if "commission_mode" not in cols:
        try:
            sync_conn.exec_driver_sql(
                "ALTER TABLE trade_purchases ADD COLUMN commission_mode VARCHAR(24) NULL"
            )
        except Exception:  # noqa: BLE001
            pass
        cols = {c["name"] for c in insp.get_columns("trade_purchases")}
    if "commission_money" not in cols:
        try:
            sync_conn.exec_driver_sql(
                "ALTER TABLE trade_purchases ADD COLUMN commission_money NUMERIC(14,4) NULL"
            )
        except Exception:  # noqa: BLE001
            pass


def _ensure_trade_purchases_delivery_columns(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("trade_purchases"):
        return
    cols = {c["name"] for c in insp.get_columns("trade_purchases")}
    if "is_delivered" not in cols:
        try:
            sync_conn.exec_driver_sql(
                "ALTER TABLE trade_purchases ADD COLUMN is_delivered BOOLEAN NOT NULL DEFAULT 0"
            )
        except Exception:  # noqa: BLE001
            pass
        cols = {c["name"] for c in insp.get_columns("trade_purchases")}
    if "delivered_at" not in cols:
        try:
            sync_conn.exec_driver_sql(
                "ALTER TABLE trade_purchases ADD COLUMN delivered_at DATETIME NULL"
            )
        except Exception:  # noqa: BLE001
            pass
    if "delivery_notes" not in cols:
        try:
            sync_conn.exec_driver_sql(
                "ALTER TABLE trade_purchases ADD COLUMN delivery_notes TEXT NULL"
            )
        except Exception:  # noqa: BLE001
            pass
    for col, ddl in (
        ("delivery_status", "VARCHAR(32) NULL"),
        ("dispatched_at", "DATETIME NULL"),
        ("arrived_at", "DATETIME NULL"),
        ("staff_verified_at", "DATETIME NULL"),
        ("staff_verified_by", "CHAR(32) NULL"),
        ("staff_verified_by_name", "VARCHAR(255) NULL"),
        ("stock_committed_at", "DATETIME NULL"),
        ("staff_verified_qty", "NUMERIC(14,3) NULL"),
        ("delivered_qty_committed", "NUMERIC(14,3) NULL"),
        ("dispatch_note", "TEXT NULL"),
        ("truck_number", "VARCHAR(64) NULL"),
        ("driver_contact", "VARCHAR(64) NULL"),
    ):
        cols = {c["name"] for c in insp.get_columns("trade_purchases")}
        if col not in cols:
            try:
                sync_conn.exec_driver_sql(
                    f"ALTER TABLE trade_purchases ADD COLUMN {col} {ddl}"
                )
            except Exception:  # noqa: BLE001
                pass


def _ensure_memberships_columns(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("memberships"):
        return
    cols = {c["name"] for c in insp.get_columns("memberships")}
    if "permissions_json" not in cols:
        sync_conn.exec_driver_sql("ALTER TABLE memberships ADD COLUMN permissions_json JSON NULL")


def _ensure_catalog_items_smart_unit_columns(sync_conn):
    """Patch legacy SQLite DBs with smart-unit / packaging columns (Postgres uses Alembic)."""
    insp = inspect(sync_conn)
    if not insp.has_table("catalog_items"):
        return
    cols = {c["name"] for c in insp.get_columns("catalog_items")}
    dialect = sync_conn.dialect.name
    alters: list[str] = []
    if "normalized_name" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN normalized_name VARCHAR(512) NULL")
    if "selling_unit" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN selling_unit VARCHAR(32) NULL")
    if "stock_unit" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN stock_unit VARCHAR(32) NULL")
    if "display_unit" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN display_unit VARCHAR(32) NULL")
    if "package_type" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN package_type VARCHAR(32) NULL")
    if "package_size" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN package_size NUMERIC(14,4) NULL")
    if "package_measurement" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN package_measurement VARCHAR(16) NULL")
    if "package_volume" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN package_volume NUMERIC(14,4) NULL")
    if "package_weight" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN package_weight NUMERIC(14,4) NULL")
    if "conversion_factor" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN conversion_factor NUMERIC(14,6) NULL")
    if "ai_detected_unit" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN ai_detected_unit VARCHAR(32) NULL")
    if "smart_classification" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN smart_classification VARCHAR(64) NULL")
    if "unit_confidence" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN unit_confidence NUMERIC(5,2) NULL")
    if "packaging_confidence" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN packaging_confidence NUMERIC(5,2) NULL")
    if "is_loose_item" not in cols:
        if dialect == "postgresql":
            alters.append("ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS is_loose_item BOOLEAN NULL")
        else:
            alters.append("ALTER TABLE catalog_items ADD COLUMN is_loose_item INTEGER NULL")
    if "is_packaged_item" not in cols:
        if dialect == "postgresql":
            alters.append("ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS is_packaged_item BOOLEAN NULL")
        else:
            alters.append("ALTER TABLE catalog_items ADD COLUMN is_packaged_item INTEGER NULL")
    if "auto_detect_enabled" not in cols:
        if dialect == "postgresql":
            alters.append(
                "ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS auto_detect_enabled BOOLEAN NOT NULL DEFAULT true"
            )
        else:
            alters.append(
                "ALTER TABLE catalog_items ADD COLUMN auto_detect_enabled INTEGER NOT NULL DEFAULT 1"
            )
    if "ml_profile" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN ml_profile TEXT NULL")
    if "validation_status" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN validation_status VARCHAR(32) NULL")
    if "deleted_at" not in cols:
        if dialect == "postgresql":
            alters.append("ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ NULL")
        else:
            alters.append("ALTER TABLE catalog_items ADD COLUMN deleted_at DATETIME NULL")
    if "archived_at" not in cols:
        if dialect == "postgresql":
            alters.append("ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ NULL")
        else:
            alters.append("ALTER TABLE catalog_items ADD COLUMN archived_at DATETIME NULL")
    for sql in alters:
        try:
            sync_conn.exec_driver_sql(sql)
        except Exception:  # noqa: BLE001
            pass


def _ensure_catalog_items_stock_columns(sync_conn):
    """Stock inventory columns on catalog_items (see sql/021_stock_inventory.sql)."""
    insp = inspect(sync_conn)
    if not insp.has_table("catalog_items"):
        return
    cols = {c["name"] for c in insp.get_columns("catalog_items")}
    alters: list[str] = []
    if "current_stock" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN current_stock NUMERIC(12,3) DEFAULT 0")
    if "stock_version" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN stock_version INTEGER NOT NULL DEFAULT 0")
    if "reorder_level" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN reorder_level NUMERIC(12,3) DEFAULT 0")
    if "rack_location" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN rack_location VARCHAR(100) NULL")
    if "last_stock_updated_at" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN last_stock_updated_at DATETIME NULL")
    if "last_stock_updated_by" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN last_stock_updated_by VARCHAR(255) NULL")
    if "eviction_days" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN eviction_days INTEGER NULL")
    if "last_purchase_at" not in cols:
        alters.append("ALTER TABLE catalog_items ADD COLUMN last_purchase_at DATETIME NULL")
    import logging

    log = logging.getLogger(__name__)
    for sql in alters:
        try:
            sync_conn.exec_driver_sql(sql)
        except Exception as exc:  # noqa: BLE001
            log.warning("sqlite bootstrap catalog_items stock column failed: %s — %s", sql, exc)


def _ensure_box_default_items_per_box(sync_conn):
    """Backfill box rows: default_items_per_box=1 when missing."""
    insp = inspect(sync_conn)
    if not insp.has_table("catalog_items"):
        return
    try:
        sync_conn.exec_driver_sql(
            """
            UPDATE catalog_items
            SET default_items_per_box = 1,
                package_type = COALESCE(NULLIF(TRIM(package_type), ''), 'BOX'),
                stock_unit = COALESCE(NULLIF(TRIM(stock_unit), ''), 'BOX')
            WHERE deleted_at IS NULL
              AND LOWER(COALESCE(default_unit, '')) = 'box'
              AND (default_items_per_box IS NULL OR default_items_per_box <= 0)
            """
        )
        sync_conn.exec_driver_sql(
            """
            UPDATE catalog_items
            SET default_unit = 'box',
                default_items_per_box = 1,
                package_type = 'BOX',
                stock_unit = 'BOX'
            WHERE deleted_at IS NULL
              AND LOWER(COALESCE(default_unit, 'piece')) IN ('piece', 'pcs')
              AND UPPER(name) LIKE '% BOX%'
              AND (default_items_per_box IS NULL OR default_items_per_box <= 0)
            """
        )
    except Exception as exc:  # noqa: BLE001
        import logging

        logging.getLogger(__name__).warning(
            "sqlite bootstrap box ipb backfill failed: %s", exc
        )


def _ensure_trade_purchase_line_columns(sync_conn):
    insp = inspect(sync_conn)
    if not insp.has_table("trade_purchase_lines"):
        return
    cols = {c["name"] for c in insp.get_columns("trade_purchase_lines")}
    dialect = sync_conn.dialect.name
    alters: list[str] = []
    if "payment_days" not in cols:
        alters.append("ALTER TABLE trade_purchase_lines ADD COLUMN payment_days INTEGER NULL")
    if "hsn_code" not in cols:
        alters.append("ALTER TABLE trade_purchase_lines ADD COLUMN hsn_code VARCHAR(32) NULL")
    if "description" not in cols:
        if dialect == "postgresql":
            alters.append("ALTER TABLE trade_purchase_lines ADD COLUMN IF NOT EXISTS description VARCHAR(512) NULL")
        else:
            alters.append("ALTER TABLE trade_purchase_lines ADD COLUMN description VARCHAR(512) NULL")
    if "kg_per_unit" not in cols:
        if dialect == "postgresql":
            alters.append(
                "ALTER TABLE trade_purchase_lines ADD COLUMN IF NOT EXISTS kg_per_unit NUMERIC(12,3) NULL"
            )
        else:
            alters.append("ALTER TABLE trade_purchase_lines ADD COLUMN kg_per_unit NUMERIC(12,3) NULL")
    if "landing_cost_per_kg" not in cols:
        if dialect == "postgresql":
            alters.append(
                "ALTER TABLE trade_purchase_lines ADD COLUMN IF NOT EXISTS landing_cost_per_kg NUMERIC(12,2) NULL"
            )
        else:
            alters.append("ALTER TABLE trade_purchase_lines ADD COLUMN landing_cost_per_kg NUMERIC(12,2) NULL")
    if "item_code" not in cols:
        if dialect == "postgresql":
            alters.append("ALTER TABLE trade_purchase_lines ADD COLUMN IF NOT EXISTS item_code VARCHAR(64) NULL")
        else:
            alters.append("ALTER TABLE trade_purchase_lines ADD COLUMN item_code VARCHAR(64) NULL")
    decimal_columns = {
        "purchase_rate": "NUMERIC(12,2)",
        "selling_rate": "NUMERIC(12,2)",
        "freight_value": "NUMERIC(12,2)",
        "delivered_rate": "NUMERIC(12,2)",
        "billty_rate": "NUMERIC(12,2)",
        "weight_per_unit": "NUMERIC(12,3)",
        "total_weight": "NUMERIC(14,3)",
        "line_total": "NUMERIC(14,2)",
        "profit": "NUMERIC(14,2)",
        "items_per_box": "NUMERIC(12,3)",
        "weight_per_item": "NUMERIC(12,3)",
        "kg_per_box": "NUMERIC(12,3)",
        "weight_per_tin": "NUMERIC(12,3)",
    }
    for name, ddl in decimal_columns.items():
        if name not in cols:
            if dialect == "postgresql":
                alters.append(f"ALTER TABLE trade_purchase_lines ADD COLUMN IF NOT EXISTS {name} {ddl} NULL")
            else:
                alters.append(f"ALTER TABLE trade_purchase_lines ADD COLUMN {name} {ddl} NULL")
    if "freight_type" not in cols:
        if dialect == "postgresql":
            alters.append("ALTER TABLE trade_purchase_lines ADD COLUMN IF NOT EXISTS freight_type VARCHAR(16) NULL")
        else:
            alters.append("ALTER TABLE trade_purchase_lines ADD COLUMN freight_type VARCHAR(16) NULL")
    if "box_mode" not in cols:
        if dialect == "postgresql":
            alters.append("ALTER TABLE trade_purchase_lines ADD COLUMN IF NOT EXISTS box_mode VARCHAR(24) NULL")
        else:
            alters.append("ALTER TABLE trade_purchase_lines ADD COLUMN box_mode VARCHAR(24) NULL")
    if "unit_type" not in cols:
        if dialect == "postgresql":
            alters.append(
                "ALTER TABLE trade_purchase_lines ADD COLUMN IF NOT EXISTS unit_type VARCHAR(16) NULL"
            )
        else:
            alters.append("ALTER TABLE trade_purchase_lines ADD COLUMN unit_type VARCHAR(16) NULL")
    for sql in alters:
        try:
            sync_conn.exec_driver_sql(sql)
        except Exception:  # noqa: BLE001
            pass
