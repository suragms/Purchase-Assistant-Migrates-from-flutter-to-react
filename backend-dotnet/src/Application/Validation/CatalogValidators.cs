using FluentValidation;
using PurchaseAssistant.Application.DTOs.Catalog;

namespace PurchaseAssistant.Application.Validation;

public class CatalogItemCreateValidator : AbstractValidator<CatalogItemCreateRequest>
{
    public CatalogItemCreateValidator()
    {
        RuleFor(x => x.Name).NotEmpty().MaximumLength(512);
        RuleFor(x => x.CategoryId).NotEmpty();
        RuleFor(x => x.DefaultUnit).NotEmpty().Matches("^(kg|box|piece|bag|tin)$");
        RuleFor(x => x.DefaultKgPerBag).GreaterThan(0).When(x => x.DefaultUnit == "bag");
        RuleFor(x => x.DefaultItemsPerBox).GreaterThan(0).When(x => x.DefaultItemsPerBox.HasValue);
        RuleFor(x => x.DefaultWeightPerTin).GreaterThan(0).When(x => x.DefaultWeightPerTin.HasValue);
        RuleFor(x => x.DefaultLandingCost).GreaterThanOrEqualTo(0).When(x => x.DefaultLandingCost.HasValue);
        RuleFor(x => x.DefaultSellingCost).GreaterThanOrEqualTo(0).When(x => x.DefaultSellingCost.HasValue);
        RuleFor(x => x.TaxPercent).InclusiveBetween(0, 100).When(x => x.TaxPercent.HasValue);
        RuleFor(x => x.HsnCode).MaximumLength(32);
        RuleFor(x => x.ItemCode).MaximumLength(64);
        RuleFor(x => x.Barcode).MaximumLength(64);
        RuleFor(x => x.DefaultSupplierIds).NotEmpty();
    }
}
