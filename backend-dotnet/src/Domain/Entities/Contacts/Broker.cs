using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Contacts;

[Table("brokers")]
public class Broker : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("name")]
    public string Name { get; set; } = string.Empty;

    [Column("phone")]
    public string? Phone { get; set; }

    [Column("location")]
    public string? Location { get; set; }

    [Column("notes")]
    public string? Notes { get; set; }

    [Column("commission_type")]
    public string? CommissionType { get; set; } = "percent";

    [Column("commission_value")]
    public decimal? CommissionValue { get; set; }

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

    [Column("image_url")]
    public string? ImageUrl { get; set; }

    [Column("preferences_json")]
    public string? PreferencesJson { get; set; }
}
