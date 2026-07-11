using FluentValidation;
using PurchaseAssistant.Application.DTOs.Catalog;

namespace PurchaseAssistant.Application.Validators;

public class ItemCategoryCreateValidator : AbstractValidator<ItemCategoryCreateRequest>
{
    public ItemCategoryCreateValidator()
    {
        RuleFor(x => x.Name).NotEmpty().MaximumLength(255);
    }
}

public class ItemCategoryUpdateValidator : AbstractValidator<ItemCategoryUpdateRequest>
{
    public ItemCategoryUpdateValidator()
    {
        RuleFor(x => x.Name).NotEmpty().MaximumLength(255);
    }
}

public class CategoryTypeCreateValidator : AbstractValidator<CategoryTypeCreateRequest>
{
    public CategoryTypeCreateValidator()
    {
        RuleFor(x => x.Name).NotEmpty().MaximumLength(255);
    }
}

public class CatalogItemCreateValidator : AbstractValidator<CatalogItemCreateRequest>
{
    public CatalogItemCreateValidator()
    {
        RuleFor(x => x.Name).NotEmpty().MaximumLength(512);
        RuleFor(x => x.CategoryId).NotEmpty();
        RuleFor(x => x.ItemCode).MaximumLength(64);
    }
}

public class CatalogBatchCreateValidator : AbstractValidator<CatalogBatchCreateRequest>
{
    public CatalogBatchCreateValidator()
    {
        RuleFor(x => x.Items).NotEmpty().Must(x => x.Count <= 80);
    }
}

public class ItemCodePatchValidator : AbstractValidator<ItemCodePatchRequest>
{
    public ItemCodePatchValidator()
    {
        RuleFor(x => x.ItemCode).NotEmpty().MaximumLength(64).Matches("^[A-Z0-9\\-\\_]+$");
    }
}

public class BarcodePatchValidator : AbstractValidator<BarcodePatchRequest>
{
    public BarcodePatchValidator()
    {
        RuleFor(x => x.Barcode).NotEmpty().MaximumLength(64);
    }
}
