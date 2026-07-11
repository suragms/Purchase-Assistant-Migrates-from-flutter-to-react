using FluentValidation;
using PurchaseAssistant.Application.DTOs.Stock;

namespace PurchaseAssistant.Application.Validators;

public class StockPatchInValidator : AbstractValidator<StockPatchIn>
{
    public StockPatchInValidator()
    {
        RuleFor(x => x.NewQty).GreaterThanOrEqualTo(0);
        RuleFor(x => x.AdjustmentType).NotEmpty().Matches("^(purchase|sale|usage|transfer|manual|damaged|expired|correction|verification|opening_stock)$");
        RuleFor(x => x.IdempotencyKey).MaximumLength(120);
    }
}

public class StockPhysicalUpdateInValidator : AbstractValidator<StockPhysicalUpdateIn>
{
    public StockPhysicalUpdateInValidator()
    {
        RuleFor(x => x.CountedQty).GreaterThanOrEqualTo(0);
        RuleFor(x => x.AdjustmentType).Matches("^(verification|damaged|correction|sale)$");
        RuleFor(x => x.Reason).NotEmpty().MaximumLength(255);
        RuleFor(x => x.Notes).MaximumLength(500);
        RuleFor(x => x.IdempotencyKey).MaximumLength(120);
    }
}

public class PhysicalStockCountInValidator : AbstractValidator<PhysicalStockCountIn>
{
    public PhysicalStockCountInValidator()
    {
        RuleFor(x => x.CountedQty).GreaterThanOrEqualTo(0);
        RuleFor(x => x.Notes).MaximumLength(500);
        RuleFor(x => x.IdempotencyKey).MaximumLength(120);
    }
}

public class StaffPurchaseLogInValidator : AbstractValidator<StaffPurchaseLogIn>
{
    public StaffPurchaseLogInValidator()
    {
        RuleFor(x => x.ItemId).NotEmpty();
        RuleFor(x => x.Qty).GreaterThan(0);
        RuleFor(x => x.Notes).MaximumLength(500);
        RuleFor(x => x.IdempotencyKey).MaximumLength(120);
    }
}
