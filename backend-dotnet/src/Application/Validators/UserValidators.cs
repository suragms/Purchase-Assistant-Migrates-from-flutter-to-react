using FluentValidation;
using PurchaseAssistant.Application.DTOs.Users;

namespace PurchaseAssistant.Application.Validators;

public class UserCreateInValidator : AbstractValidator<UserCreateIn>
{
    public UserCreateInValidator()
    {
        RuleFor(x => x.FullName).NotEmpty().MaximumLength(255);
        RuleFor(x => x.Email).EmailAddress().When(x => x.Email is not null).Length(5, 320);
        RuleFor(x => x.Phone).NotEmpty().Length(6, 32);
        RuleFor(x => x.Role).NotEmpty().Matches("^(admin|manager|staff)$");
        RuleFor(x => x.Notes).MaximumLength(2000);
    }
}

public class UserPatchInValidator : AbstractValidator<UserPatchIn>
{
    public UserPatchInValidator()
    {
        RuleFor(x => x.FullName).MaximumLength(255);
        RuleFor(x => x.Email).EmailAddress().When(x => x.Email is not null);
        RuleFor(x => x.Phone).Length(6, 32).When(x => x.Phone is not null);
        RuleFor(x => x.Role).Matches("^(admin|manager|staff|owner)$").When(x => x.Role is not null);
        RuleFor(x => x.Notes).MaximumLength(2000);
    }
}

public class UserBulkInValidator : AbstractValidator<UserBulkIn>
{
    public UserBulkInValidator()
    {
        RuleFor(x => x.UserIds).NotEmpty().Must(x => x.Count <= 100);
        RuleFor(x => x.Action).NotEmpty().Matches("^(activate|deactivate|block|unblock|delete|set_role)$");
        RuleFor(x => x.Role).Matches("^(admin|manager|staff)$").When(x => x.Role is not null);
    }
}

public class ActivityLogInValidator : AbstractValidator<ActivityLogIn>
{
    public ActivityLogInValidator()
    {
        RuleFor(x => x.ActionType).NotEmpty().MaximumLength(64);
    }
}
