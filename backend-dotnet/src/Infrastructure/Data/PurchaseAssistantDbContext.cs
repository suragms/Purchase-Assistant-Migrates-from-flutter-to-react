using Microsoft.EntityFrameworkCore;
using PurchaseAssistant.Domain.Entities.Activity;
using PurchaseAssistant.Domain.Entities.Catalog;
using PurchaseAssistant.Domain.Entities.Config;
using PurchaseAssistant.Domain.Entities.Contacts;
using PurchaseAssistant.Domain.Entities.Core;
using PurchaseAssistant.Domain.Entities.Notifications;
using PurchaseAssistant.Domain.Entities.Operations;
using PurchaseAssistant.Domain.Entities.Reports;
using PurchaseAssistant.Domain.Entities.Stock;
using PurchaseAssistant.Domain.Entities.Trade;
using PurchaseAssistant.Domain.Entities.Units;

namespace PurchaseAssistant.Infrastructure.Data;

public class PurchaseAssistantDbContext : DbContext
{
    public PurchaseAssistantDbContext(DbContextOptions<PurchaseAssistantDbContext> options) : base(options) { }

    // Core
    public DbSet<Business> Businesses => Set<Business>();
    public DbSet<User> Users => Set<User>();
    public DbSet<Membership> Memberships => Set<Membership>();
    public DbSet<UserSession> UserSessions => Set<UserSession>();
    public DbSet<PasswordResetToken> PasswordResetTokens => Set<PasswordResetToken>();

    // Catalog
    public DbSet<ItemCategory> ItemCategories => Set<ItemCategory>();
    public DbSet<CategoryType> CategoryTypes => Set<CategoryType>();
    public DbSet<CatalogItem> CatalogItems => Set<CatalogItem>();
    public DbSet<CatalogVariant> CatalogVariants => Set<CatalogVariant>();
    public DbSet<CatalogItemDefaultSupplier> CatalogItemDefaultSuppliers => Set<CatalogItemDefaultSupplier>();
    public DbSet<CatalogItemDefaultBroker> CatalogItemDefaultBrokers => Set<CatalogItemDefaultBroker>();
    public DbSet<SupplierItemDefault> SupplierItemDefaults => Set<SupplierItemDefault>();

    // Contacts
    public DbSet<Supplier> Suppliers => Set<Supplier>();
    public DbSet<Broker> Brokers => Set<Broker>();
    public DbSet<BrokerSupplierM2M> BrokerSupplierM2Ms => Set<BrokerSupplierM2M>();

    // Trade
    public DbSet<TradePurchase> TradePurchases => Set<TradePurchase>();
    public DbSet<TradePurchaseLine> TradePurchaseLines => Set<TradePurchaseLine>();
    public DbSet<TradePurchaseDraft> TradePurchaseDrafts => Set<TradePurchaseDraft>();
    public DbSet<PurchaseLifecycleEvent> PurchaseLifecycleEvents => Set<PurchaseLifecycleEvent>();
    public DbSet<PurchaseDamageReport> PurchaseDamageReports => Set<PurchaseDamageReport>();

    // Stock
    public DbSet<StockAdjustmentLog> StockAdjustmentLogs => Set<StockAdjustmentLog>();
    public DbSet<StockMovement> StockMovements => Set<StockMovement>();
    public DbSet<StockPhysicalCount> StockPhysicalCounts => Set<StockPhysicalCount>();
    public DbSet<StockAudit> StockAudits => Set<StockAudit>();
    public DbSet<StockAuditItem> StockAuditItems => Set<StockAuditItem>();
    public DbSet<StockDisputeCase> StockDisputeCases => Set<StockDisputeCase>();
    public DbSet<ReorderList> ReorderLists => Set<ReorderList>();

    // Operations
    public DbSet<DailyUsageLog> DailyUsageLogs => Set<DailyUsageLog>();
    public DbSet<StaffChecklistTemplate> StaffChecklistTemplates => Set<StaffChecklistTemplate>();
    public DbSet<StaffChecklistCompletion> StaffChecklistCompletions => Set<StaffChecklistCompletion>();
    public DbSet<StaffPurchaseLog> StaffPurchaseLogs => Set<StaffPurchaseLog>();

    // Notifications
    public DbSet<Notification> Notifications => Set<Notification>();

    // Activity
    public DbSet<StaffActivityLog> StaffActivityLogs => Set<StaffActivityLog>();
    public DbSet<AdminAuditLog> AdminAuditLogs => Set<AdminAuditLog>();
    public DbSet<ApiUsageLog> ApiUsageLogs => Set<ApiUsageLog>();
    public DbSet<WebhookEventLog> WebhookEventLogs => Set<WebhookEventLog>();

    // Reports
    public DbSet<ReportSavedView> ReportSavedViews => Set<ReportSavedView>();

    // Units
    public DbSet<MasterUnit> MasterUnits => Set<MasterUnit>();
    public DbSet<ItemPackagingProfile> ItemPackagingProfiles => Set<ItemPackagingProfile>();
    public DbSet<OcrItemAlias> OcrItemAliases => Set<OcrItemAlias>();
    public DbSet<SmartUnitRule> SmartUnitRules => Set<SmartUnitRule>();
    public DbSet<SmartPackageRule> SmartPackageRules => Set<SmartPackageRule>();
    public DbSet<ItemLearningHistory> ItemLearningHistories => Set<ItemLearningHistory>();
    public DbSet<UnitConfidenceLog> UnitConfidenceLogs => Set<UnitConfidenceLog>();
    public DbSet<AiItemProfile> AiItemProfiles => Set<AiItemProfile>();

    // Config
    public DbSet<BusinessGoal> BusinessGoals => Set<BusinessGoal>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // ---- Core ----
        modelBuilder.Entity<Business>(e =>
        {
            e.ToTable("businesses");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.Name).HasMaxLength(255).IsRequired();
            e.Property(x => x.BrandingTitle).HasMaxLength(128);
            e.Property(x => x.BrandingLogoUrl).HasMaxLength(512);
            e.Property(x => x.GstNumber).HasMaxLength(20);
            e.Property(x => x.Phone).HasMaxLength(32);
            e.Property(x => x.ContactEmail).HasMaxLength(255);
            e.Property(x => x.DefaultCurrency).HasMaxLength(3).IsRequired().HasDefaultValue("INR");
        });

        modelBuilder.Entity<User>(e =>
        {
            e.ToTable("users");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.Email).HasMaxLength(320).IsRequired();
            e.Property(x => x.Username).HasMaxLength(64).IsRequired();
            e.Property(x => x.PasswordHash).HasMaxLength(255);
            e.Property(x => x.Name).HasMaxLength(255);
            e.Property(x => x.Phone).HasMaxLength(32);
            e.Property(x => x.GoogleSub).HasMaxLength(128);
            e.Property(x => x.AiMonthlyTokenBudget).HasDefaultValue(100000);
            e.Property(x => x.AiTokensUsedMonth).HasDefaultValue(0);
            e.Property(x => x.Notes).HasMaxLength(2000);
            e.Property(x => x.DeviceInfo).HasColumnType("jsonb");
            e.Property(x => x.TokenVersion).HasDefaultValue(0);
            e.HasIndex(x => x.Email).HasDatabaseName("ix_users_email");
            e.HasIndex(x => x.GoogleSub).HasDatabaseName("ix_users_google_sub");
            e.HasIndex(x => x.Username).HasDatabaseName("ix_users_username");
        });

        modelBuilder.Entity<Membership>(e =>
        {
            e.ToTable("memberships");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.Role).HasMaxLength(32).IsRequired();
            e.Property(x => x.PermissionsJson).HasColumnType("jsonb");
            e.HasIndex(x => x.UserId).HasDatabaseName("ix_memberships_user_id");
            e.HasIndex(x => x.BusinessId).HasDatabaseName("ix_memberships_business_id");
            e.HasIndex(x => new { x.UserId, x.BusinessId }).IsUnique();
        });

        modelBuilder.Entity<UserSession>(e =>
        {
            e.ToTable("user_sessions");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
        });

        modelBuilder.Entity<PasswordResetToken>(e =>
        {
            e.ToTable("password_reset_tokens");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.TokenHash).HasMaxLength(255).IsRequired();
        });

        // ---- Catalog ----
        modelBuilder.Entity<ItemCategory>(e =>
        {
            e.ToTable("item_categories");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.Name).HasMaxLength(255).IsRequired();
        });

        modelBuilder.Entity<CategoryType>(e =>
        {
            e.ToTable("category_types");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.Name).HasMaxLength(255).IsRequired();
        });

        modelBuilder.Entity<CatalogItem>(e =>
        {
            e.ToTable("catalog_items");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.Name).HasMaxLength(512).IsRequired();
            e.Property(x => x.NormalizedName).HasMaxLength(512);
            e.Property(x => x.DefaultUnit).HasMaxLength(32);
            e.Property(x => x.DefaultPurchaseUnit).HasMaxLength(32);
            e.Property(x => x.DefaultSaleUnit).HasMaxLength(32);
            e.Property(x => x.SellingUnit).HasMaxLength(32);
            e.Property(x => x.StockUnit).HasMaxLength(32);
            e.Property(x => x.DisplayUnit).HasMaxLength(32);
            e.Property(x => x.PackageType).HasMaxLength(32);
            e.Property(x => x.PackageSize).HasColumnType("numeric(14,4)");
            e.Property(x => x.PackageMeasurement).HasMaxLength(16);
            e.Property(x => x.PackageVolume).HasColumnType("numeric(14,4)");
            e.Property(x => x.PackageWeight).HasColumnType("numeric(14,4)");
            e.Property(x => x.ConversionFactor).HasColumnType("numeric(14,6)");
            e.Property(x => x.DefaultKgPerBag).HasColumnType("numeric(12,3)");
            e.Property(x => x.DefaultItemsPerBox).HasColumnType("numeric(12,3)");
            e.Property(x => x.DefaultWeightPerTin).HasColumnType("numeric(12,3)");
            e.Property(x => x.HsnCode).HasMaxLength(32);
            e.Property(x => x.ItemCode).HasMaxLength(64);
            e.Property(x => x.Barcode).HasMaxLength(64);
            e.Property(x => x.PublicToken).HasMaxLength(64);
            e.Property(x => x.TaxPercent).HasColumnType("numeric(5,2)");
            e.Property(x => x.DefaultLandingCost).HasColumnType("numeric(12,2)");
            e.Property(x => x.DefaultSellingCost).HasColumnType("numeric(12,2)");
            e.Property(x => x.ReorderLevel).HasColumnType("numeric(12,3)").HasDefaultValue(0);
            e.Property(x => x.CurrentStock).HasColumnType("numeric(12,3)").HasDefaultValue(0);
            e.Property(x => x.OpeningStockQty).HasColumnType("numeric(12,3)");
            e.Property(x => x.LastLineQty).HasColumnType("numeric(12,3)");
            e.Property(x => x.LastLineWeightKg).HasColumnType("numeric(14,3)");
            e.Property(x => x.LastPurchasePrice).HasColumnType("numeric(12,2)");
            e.Property(x => x.LastSellingRate).HasColumnType("numeric(12,2)");
            e.Property(x => x.MlProfile).HasColumnType("json");
            e.Property(x => x.UnitConfidence).HasColumnType("numeric(5,2)");
            e.Property(x => x.PackagingConfidence).HasColumnType("numeric(5,2)");
            e.Property(x => x.RackLocation).HasMaxLength(100);
            e.Property(x => x.StockVersion).HasDefaultValue(0);
            e.Property(x => x.OpeningStockSetBy).HasMaxLength(255);
            e.Property(x => x.LastLineUnit).HasMaxLength(32);
            e.Property(x => x.LastStockUpdatedBy).HasMaxLength(255);
            e.Property(x => x.AiDetectedUnit).HasMaxLength(32);
            e.Property(x => x.SmartClassification).HasMaxLength(64);
            e.Property(x => x.ValidationStatus).HasMaxLength(32);
            e.Property(x => x.LastLineUnit).HasMaxLength(32);
            e.HasIndex(x => x.BusinessId).HasDatabaseName("ix_catalog_items_business_id");
            e.HasIndex(x => x.CategoryId).HasDatabaseName("ix_catalog_items_category_id");
            e.HasIndex(x => x.Barcode).HasDatabaseName("ix_catalog_items_barcode");
            e.HasIndex(x => x.ItemCode).HasDatabaseName("ix_catalog_items_item_code");
            e.HasIndex(x => x.PublicToken).HasDatabaseName("ix_catalog_items_public_token");
            e.HasIndex(x => x.LastSupplierId).HasDatabaseName("ix_catalog_items_last_supplier_id");
            e.HasIndex(x => x.LastBrokerId).HasDatabaseName("ix_catalog_items_last_broker_id");
            e.HasIndex(x => x.LastTradePurchaseId).HasDatabaseName("ix_catalog_items_last_trade_purchase_id");
            e.HasIndex(x => x.Name).HasDatabaseName("ix_catalog_items_name_lower");
        });

        modelBuilder.Entity<CatalogVariant>(e =>
        {
            e.ToTable("catalog_variants");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.Name).HasMaxLength(512).IsRequired();
            e.Property(x => x.DefaultKgPerBag).HasColumnType("numeric(10,3)");
        });

        modelBuilder.Entity<CatalogItemDefaultSupplier>(e =>
        {
            e.ToTable("catalog_item_default_suppliers");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        });

        modelBuilder.Entity<CatalogItemDefaultBroker>(e =>
        {
            e.ToTable("catalog_item_default_brokers");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        });

        modelBuilder.Entity<SupplierItemDefault>(e =>
        {
            e.ToTable("supplier_item_defaults");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.LastPrice).HasColumnType("numeric(12,2)");
            e.Property(x => x.LastDiscount).HasColumnType("numeric(5,2)");
        });

        // ---- Contacts ----
        modelBuilder.Entity<Supplier>(e =>
        {
            e.ToTable("suppliers");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.Name).HasMaxLength(255).IsRequired();
            e.Property(x => x.Phone).HasMaxLength(32);
            e.Property(x => x.Location).HasMaxLength(255);
            e.Property(x => x.GstNumber).HasMaxLength(15);
            e.Property(x => x.DefaultDiscount).HasColumnType("numeric(5,2)");
            e.Property(x => x.DefaultDeliveredRate).HasColumnType("numeric(12,2)");
            e.Property(x => x.DefaultBilltyRate).HasColumnType("numeric(12,2)");
            e.Property(x => x.FreightType).HasMaxLength(16);
        });

        modelBuilder.Entity<Broker>(e =>
        {
            e.ToTable("brokers");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.Name).HasMaxLength(255).IsRequired();
            e.Property(x => x.Phone).HasMaxLength(15);
            e.Property(x => x.Location).HasMaxLength(255);
            e.Property(x => x.CommissionType).HasMaxLength(16).HasDefaultValue("percent");
            e.Property(x => x.CommissionValue).HasColumnType("numeric(12,2)");
            e.Property(x => x.DefaultDiscount).HasColumnType("numeric(5,2)");
            e.Property(x => x.DefaultDeliveredRate).HasColumnType("numeric(12,2)");
            e.Property(x => x.DefaultBilltyRate).HasColumnType("numeric(12,2)");
            e.Property(x => x.FreightType).HasMaxLength(16);
            e.Property(x => x.ImageUrl).HasMaxLength(1024);
        });

        modelBuilder.Entity<BrokerSupplierM2M>(e =>
        {
            e.ToTable("broker_supplier_m2m");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.HasIndex(x => new { x.BrokerId, x.SupplierId }).IsUnique();
        });

        // ---- Trade ----
        modelBuilder.Entity<TradePurchase>(e =>
        {
            e.ToTable("trade_purchases");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.HumanId).HasMaxLength(64).IsRequired();
            e.Property(x => x.TotalAmount).HasColumnType("numeric(14,2)");
            e.Property(x => x.PaidAmount).HasColumnType("numeric(14,2)").HasDefaultValue(0);
            e.Property(x => x.Discount).HasColumnType("numeric(5,2)");
            e.Property(x => x.CommissionValue).HasColumnType("numeric(12,2)");
            e.Property(x => x.CommissionMoney).HasColumnType("numeric(12,2)");
            e.Property(x => x.FreightCharge).HasColumnType("numeric(12,2)");
            e.Property(x => x.CommissionType).HasMaxLength(16);
            e.Property(x => x.FreightType).HasMaxLength(16);
            e.Property(x => x.DeliveryStatus).HasMaxLength(32);
            e.Property(x => x.DeliveredBy).HasMaxLength(128);
            e.Property(x => x.ReceivedBy).HasMaxLength(128);
            e.Property(x => x.VehicleNumber).HasMaxLength(32);
            e.Property(x => x.DispatchNote).HasColumnType("text");
            e.Property(x => x.Notes).HasColumnType("text");
            e.Property(x => x.Status).HasMaxLength(32).IsRequired();
        });

        modelBuilder.Entity<TradePurchaseLine>(e =>
        {
            e.ToTable("trade_purchase_lines");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.ItemName).HasMaxLength(512).IsRequired();
            e.Property(x => x.Qty).HasColumnType("numeric(12,3)").IsRequired();
            e.Property(x => x.Unit).HasMaxLength(16).IsRequired();
            e.Property(x => x.QtyInStockUnit).HasColumnType("numeric(12,3)");
            e.Property(x => x.LandingCost).HasColumnType("numeric(12,2)").IsRequired();
            e.Property(x => x.SellingRate).HasColumnType("numeric(12,2)");
            e.Property(x => x.SellingCost).HasColumnType("numeric(12,2)");
            e.Property(x => x.LineTotal).HasColumnType("numeric(14,2)");
            e.Property(x => x.Profit).HasColumnType("numeric(14,2)");
            e.Property(x => x.DiscountPct).HasColumnType("numeric(5,2)");
            e.Property(x => x.TaxMode).HasMaxLength(8);
            e.Property(x => x.TaxPercent).HasColumnType("numeric(5,2)");
            e.Property(x => x.KgPerUnit).HasColumnType("numeric(12,4)");
            e.Property(x => x.TotalWeight).HasColumnType("numeric(14,4)");
            e.Property(x => x.LandingCostPerKg).HasColumnType("numeric(14,4)");
            e.Property(x => x.ReceivedQty).HasColumnType("numeric(12,3)");
            e.Property(x => x.DamagedQty).HasColumnType("numeric(12,3)");
            e.Property(x => x.ReturnQty).HasColumnType("numeric(12,3)");
        });

        modelBuilder.Entity<TradePurchaseDraft>(e =>
        {
            e.ToTable("trade_purchase_drafts");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.Step).HasMaxLength(32);
            e.Property(x => x.Payload).HasColumnType("jsonb");
            e.HasIndex(x => new { x.BusinessId, x.UserId }).IsUnique();
        });

        modelBuilder.Entity<PurchaseLifecycleEvent>(e =>
        {
            e.ToTable("purchase_lifecycle_events");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.FromStatus).HasMaxLength(32);
            e.Property(x => x.ToStatus).HasMaxLength(32);
            e.Property(x => x.Metadata).HasColumnType("jsonb");
        });

        modelBuilder.Entity<PurchaseDamageReport>(e =>
        {
            e.ToTable("purchase_damage_reports");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.ItemName).HasMaxLength(512);
            e.Property(x => x.QtyDamaged).HasColumnType("numeric(12,3)");
            e.Property(x => x.Unit).HasMaxLength(16);
            e.Property(x => x.DamageType).HasMaxLength(32);
            e.Property(x => x.Status).HasMaxLength(32).HasDefaultValue("pending");
            e.Property(x => x.PhotoUrl).HasMaxLength(1024);
            e.Property(x => x.DamageItemsInBatch).HasColumnType("jsonb");
        });

        // ---- Stock ----
        modelBuilder.Entity<StockAdjustmentLog>(e =>
        {
            e.ToTable("stock_adjustment_log");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.OldQty).HasColumnType("numeric(12,3)");
            e.Property(x => x.NewQty).HasColumnType("numeric(12,3)");
            e.Property(x => x.AdjustmentType).HasMaxLength(32);
            e.Property(x => x.Reason).HasMaxLength(512);
        });

        modelBuilder.Entity<StockMovement>(e =>
        {
            e.ToTable("stock_movements");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.FromLocation).HasMaxLength(128);
            e.Property(x => x.ToLocation).HasMaxLength(128);
            e.Property(x => x.Qty).HasColumnType("numeric(12,3)");
            e.Property(x => x.Unit).HasMaxLength(16);
        });

        modelBuilder.Entity<StockPhysicalCount>(e =>
        {
            e.ToTable("stock_physical_counts");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.CountedQty).HasColumnType("numeric(12,3)");
            e.Property(x => x.SystemQty).HasColumnType("numeric(12,3)");
            e.Property(x => x.Unit).HasMaxLength(16);
            e.Property(x => x.Variance).HasColumnType("numeric(12,3)");
            e.Property(x => x.IdempotencyKey).HasMaxLength(64);
        });

        modelBuilder.Entity<StockAudit>(e =>
        {
            e.ToTable("stock_audits");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.Title).HasMaxLength(255);
            e.Property(x => x.Status).HasMaxLength(32).HasDefaultValue("in_progress");
        });

        modelBuilder.Entity<StockAuditItem>(e =>
        {
            e.ToTable("stock_audit_items");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.ExpectedQty).HasColumnType("numeric(12,3)");
            e.Property(x => x.ActualQty).HasColumnType("numeric(12,3)");
            e.Property(x => x.Variance).HasColumnType("numeric(12,3)");
        });

        modelBuilder.Entity<StockDisputeCase>(e =>
        {
            e.ToTable("stock_dispute_cases");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.ExpectedQty).HasColumnType("numeric(12,3)");
            e.Property(x => x.ActualQty).HasColumnType("numeric(12,3)");
            e.Property(x => x.Status).HasMaxLength(32).HasDefaultValue("open");
        });

        modelBuilder.Entity<ReorderList>(e =>
        {
            e.ToTable("reorder_list");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.SuggestedQty).HasColumnType("numeric(12,3)");
        });

        // ---- Operations ----
        modelBuilder.Entity<DailyUsageLog>(e =>
        {
            e.ToTable("daily_usage_logs");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.QtyUsed).HasColumnType("numeric(12,3)");
            e.Property(x => x.Unit).HasMaxLength(16);
        });

        modelBuilder.Entity<StaffChecklistTemplate>(e =>
        {
            e.ToTable("staff_checklist_templates");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.Title).HasMaxLength(255);
            e.Property(x => x.Frequency).HasMaxLength(32);
        });

        modelBuilder.Entity<StaffChecklistCompletion>(e =>
        {
            e.ToTable("staff_checklist_completions");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
        });

        modelBuilder.Entity<StaffPurchaseLog>(e =>
        {
            e.ToTable("staff_purchase_logs");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.ItemName).HasMaxLength(512);
            e.Property(x => x.Qty).HasColumnType("numeric(12,3)");
            e.Property(x => x.Unit).HasMaxLength(16);
            e.Property(x => x.Amount).HasColumnType("numeric(12,2)");
        });

        // ---- Notifications ----
        modelBuilder.Entity<Notification>(e =>
        {
            e.ToTable("notifications");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.Kind).HasMaxLength(64);
            e.Property(x => x.Title).HasMaxLength(500);
            e.Property(x => x.Priority).HasMaxLength(16);
            e.Property(x => x.Category).HasMaxLength(32);
            e.Property(x => x.ActionRoute).HasMaxLength(255);
            e.Property(x => x.DedupeKey).HasMaxLength(128);
            e.Property(x => x.Payload).HasColumnType("jsonb");
        });

        // ---- Activity ----
        modelBuilder.Entity<StaffActivityLog>(e =>
        {
            e.ToTable("staff_activity_log");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.UserName).HasMaxLength(255);
            e.Property(x => x.ActionType).HasMaxLength(64).IsRequired();
            e.Property(x => x.ItemName).HasMaxLength(512);
            e.Property(x => x.Details).HasColumnType("jsonb");
        });

        modelBuilder.Entity<AdminAuditLog>(e =>
        {
            e.ToTable("admin_audit_logs");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.Action).HasMaxLength(64);
            e.Property(x => x.TargetType).HasMaxLength(64);
            e.Property(x => x.Details).HasColumnType("jsonb");
        });

        modelBuilder.Entity<ApiUsageLog>(e =>
        {
            e.ToTable("api_usage_logs");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.Endpoint).HasMaxLength(255);
            e.Property(x => x.Method).HasMaxLength(8);
        });

        modelBuilder.Entity<WebhookEventLog>(e =>
        {
            e.ToTable("webhook_event_logs");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.EventType).HasMaxLength(64);
            e.Property(x => x.Payload).HasColumnType("jsonb");
            e.Property(x => x.Status).HasMaxLength(32);
        });

        // ---- Reports ----
        modelBuilder.Entity<ReportSavedView>(e =>
        {
            e.ToTable("report_saved_views");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.Name).HasMaxLength(255);
            e.Property(x => x.ReportType).HasMaxLength(64);
            e.Property(x => x.Filters).HasColumnType("jsonb");
        });

        // ---- Units ----
        modelBuilder.Entity<MasterUnit>(e =>
        {
            e.ToTable("master_units");
            e.HasKey(x => x.Code);
            e.Property(x => x.Code).HasMaxLength(16);
            e.Property(x => x.LabelPlural).HasMaxLength(32);
            e.Property(x => x.Category).HasMaxLength(32);
            e.Property(x => x.BaseUnit).HasMaxLength(16);
            e.Property(x => x.ConversionToBase).HasColumnType("numeric(12,6)");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
        });

        modelBuilder.Entity<ItemPackagingProfile>(e =>
        {
            e.ToTable("item_packaging_profiles");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.ProfileType).HasMaxLength(32);
            e.Property(x => x.DisplayUnit).HasMaxLength(16);
            e.Property(x => x.StockUnit).HasMaxLength(16);
            e.Property(x => x.PackageSize).HasColumnType("numeric(12,4)");
            e.Property(x => x.PackageMeasurement).HasMaxLength(8);
        });

        modelBuilder.Entity<OcrItemAlias>(e =>
        {
            e.ToTable("ocr_item_aliases");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.AliasText).HasMaxLength(512);
            e.Property(x => x.Source).HasMaxLength(32);
        });

        modelBuilder.Entity<SmartUnitRule>(e =>
        {
            e.ToTable("smart_unit_rules");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.Keyword).HasMaxLength(128);
            e.Property(x => x.UnitCode).HasMaxLength(16);
            e.Property(x => x.PackageType).HasMaxLength(32);
        });

        modelBuilder.Entity<SmartPackageRule>(e =>
        {
            e.ToTable("smart_package_rules");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.Keyword).HasMaxLength(128);
            e.Property(x => x.UnitCode).HasMaxLength(16);
            e.Property(x => x.PackageType).HasMaxLength(32);
        });

        modelBuilder.Entity<ItemLearningHistory>(e =>
        {
            e.ToTable("item_learning_history");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.CorrectedUnit).HasMaxLength(16);
            e.Property(x => x.CorrectedPackageType).HasMaxLength(32);
        });

        modelBuilder.Entity<UnitConfidenceLog>(e =>
        {
            e.ToTable("unit_confidence_logs");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.Source).HasMaxLength(32);
            e.Property(x => x.UnitCode).HasMaxLength(16);
        });

        modelBuilder.Entity<AiItemProfile>(e =>
        {
            e.ToTable("ai_item_profiles");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.ProfileData).HasColumnType("jsonb");
            e.Property(x => x.GeneratedBy).HasMaxLength(64);
        });

        // ---- Config ----
        modelBuilder.Entity<BusinessGoal>(e =>
        {
            e.ToTable("business_goals");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
            e.Property(x => x.Metric).HasMaxLength(64);
            e.Property(x => x.TargetValue).HasColumnType("numeric(14,2)");
            e.Property(x => x.Period).HasMaxLength(16);
        });
    }
}
