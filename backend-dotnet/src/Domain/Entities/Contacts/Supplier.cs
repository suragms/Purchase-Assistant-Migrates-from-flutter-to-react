using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Contacts;

[Table("suppliers")]
public class Supplier : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("name")]
    public string Name { get; set; } = string.Empty;

    [Column("phone")]
    public string? Phone { get; set; }

    [Column("location")]
    public string? Location { get; set; }

    [Column("broker_id")]
    public Guid? BrokerId { get; set; }

    [Column("gst_number")]
    public string? GstNumber { get; set; }

    [Column("address")]
    public string? Address { get; set; }

    [Column("notes")]
    public string? Notes { get; set; }

    [Column("default_payment_days")]
    public int? DefaultPaymentDays { get; set; }

    [Column("default_discount")]
    public decimal? DefaultDiscount { get; set; }

    [Column("default_delivered_rate")]
    public decimal? DefaultDeliveredRate { get; set; }

    [Column("default_billty_rate")]
    public decimal? DefaultBilltyRate { get; set; }

    [Column("freight_type")]
    public string? FreightType { get; set; }

    [Column("ai_memory_enabled")]
    public bool AiMemoryEnabled { get; set; } = false;

    [Column("preferences_json")]
    public string? PreferencesJson { get; set; }
}
