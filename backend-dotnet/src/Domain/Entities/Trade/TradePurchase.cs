using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Trade;

[Table("trade_purchases")]
public class TradePurchase : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("user_id")]
    public Guid UserId { get; set; }

    [Column("human_id")]
    public string HumanId { get; set; } = string.Empty;

    [Column("purchase_date")]
    public DateOnly PurchaseDate { get; set; }

    [Column("supplier_id")]
    public Guid? SupplierId { get; set; }

    [Column("broker_id")]
    public Guid? BrokerId { get; set; }

    [Column("total_amount")]
    public decimal? TotalAmount { get; set; }

    [Column("paid_amount")]
    public decimal PaidAmount { get; set; } = 0;

    [Column("discount")]
    public decimal? Discount { get; set; }

    [Column("payment_days")]
    public int? PaymentDays { get; set; }

    [Column("commission_type")]
    public string? CommissionType { get; set; }

    [Column("commission_value")]
    public decimal? CommissionValue { get; set; }

    [Column("commission_money")]
    public decimal? CommissionMoney { get; set; }

    [Column("freight_type")]
    public string? FreightType { get; set; }

    [Column("freight_charge")]
    public decimal? FreightCharge { get; set; }

    [Column("notes")]
    public string? Notes { get; set; }

    [Column("delivery_status")]
    public string? DeliveryStatus { get; set; }

    [Column("delivery_date")]
    public DateOnly? DeliveryDate { get; set; }

    [Column("dispatch_date")]
    public DateOnly? DispatchDate { get; set; }

    [Column("dispatch_note")]
    public string? DispatchNote { get; set; }

    [Column("delivered_by")]
    public string? DeliveredBy { get; set; }

    [Column("received_by")]
    public string? ReceivedBy { get; set; }

    [Column("vehicle_number")]
    public string? VehicleNumber { get; set; }

    [Column("verified_by")]
    public Guid? VerifiedBy { get; set; }

    [Column("status")]
    public string Status { get; set; } = string.Empty;

    [Column("deleted_at")]
    public DateTime? DeletedAt { get; set; }
}
