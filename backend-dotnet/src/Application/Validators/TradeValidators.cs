using FluentValidation;
using PurchaseAssistant.Application.DTOs.Trade;

namespace PurchaseAssistant.Application.Validators;

public class TradePurchaseCreateRequestValidator : AbstractValidator<TradePurchaseCreateRequest>
{
    public TradePurchaseCreateRequestValidator()
    {
        RuleFor(x => x.PurchaseDate).NotEmpty();
        RuleFor(x => x.SupplierId).NotEmpty();
        RuleFor(x => x.Status).Matches("^(draft|saved|confirmed)$");
        RuleFor(x => x.PaymentDays).InclusiveBetween(0, 3650).When(x => x.PaymentDays.HasValue);
        RuleFor(x => x.CommissionMode).Matches("^(percent|flat_invoice|flat_kg|flat_bag|flat_box|flat_tin)$");
        RuleFor(x => x.FreightType).Matches("^(included|separate)$").When(x => x.FreightType is not null);
    }
}

public class TradePurchaseLineInValidator : AbstractValidator<TradePurchaseLineIn>
{
    public TradePurchaseLineInValidator()
    {
        RuleFor(x => x.CatalogItemId).NotEmpty();
        RuleFor(x => x.ItemName).NotEmpty().MaximumLength(512);
        RuleFor(x => x.Qty).GreaterThan(0);
        RuleFor(x => x.Unit).NotEmpty().MaximumLength(32);
        RuleFor(x => x.LandingCost).GreaterThan(0);
        RuleFor(x => x.TaxMode).Matches("^(exclusive|inclusive)$").When(x => x.TaxMode is not null);
        RuleFor(x => x.FreightType).Matches("^(included|separate)$").When(x => x.FreightType is not null);
    }
}

public class TradePurchaseDeliveryPatchValidator : AbstractValidator<TradePurchaseDeliveryPatch>
{
    public TradePurchaseDeliveryPatchValidator()
    {
        RuleFor(x => x.DeliveryNotes).MaximumLength(2000);
    }
}

public class TradePurchaseVerifyInValidator : AbstractValidator<TradePurchaseVerifyIn>
{
    public TradePurchaseVerifyInValidator()
    {
        RuleFor(x => x.Notes).MaximumLength(2000);
    }
}

public class PurchaseLifecycleTransitionInValidator : AbstractValidator<PurchaseLifecycleTransitionIn>
{
    public PurchaseLifecycleTransitionInValidator()
    {
        RuleFor(x => x.ToStatus).NotEmpty()
            .Matches("^(draft|active|approved|ordered|supplier_confirmed|in_transit|arrived|verification_pending|verified|added_to_stock|completed|cancelled)$");
        RuleFor(x => x.Notes).MaximumLength(2000);
    }
}
