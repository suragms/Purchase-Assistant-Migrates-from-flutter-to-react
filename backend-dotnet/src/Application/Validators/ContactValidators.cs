using FluentValidation;
using PurchaseAssistant.Application.DTOs.Contacts;

namespace PurchaseAssistant.Application.Validators;

public class SupplierCreateValidator : AbstractValidator<SupplierCreate>
{
    public SupplierCreateValidator()
    {
        RuleFor(x => x.Name).NotEmpty().MaximumLength(255);
        RuleFor(x => x.FreightType).Matches("^(included|separate)$").When(x => x.FreightType is not null);
    }
}

public class BrokerCreateValidator : AbstractValidator<BrokerCreate>
{
    public BrokerCreateValidator()
    {
        RuleFor(x => x.Name).NotEmpty().MaximumLength(255);
        RuleFor(x => x.CommissionType).Matches("^(percent|flat)$").When(x => x.CommissionType is not null);
    }
}
