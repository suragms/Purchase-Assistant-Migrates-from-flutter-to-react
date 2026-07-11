using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Core;

[Table("businesses")]
public class Business : BaseEntity
{
    [Column("name")]
    public string Name { get; set; } = string.Empty;

    [Column("branding_title")]
    public string? BrandingTitle { get; set; }

    [Column("branding_logo_url")]
    public string? BrandingLogoUrl { get; set; }

    [Column("gst_number")]
    public string? GstNumber { get; set; }

    [Column("address")]
    public string? Address { get; set; }

    [Column("phone")]
    public string? Phone { get; set; }

    [Column("contact_email")]
    public string? ContactEmail { get; set; }

    [Column("default_currency")]
    public string DefaultCurrency { get; set; } = "INR";
}
