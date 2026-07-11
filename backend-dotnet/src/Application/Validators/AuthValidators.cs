using FluentValidation;
using PurchaseAssistant.Application.DTOs.Auth;

namespace PurchaseAssistant.Application.Validators;

public class RegisterRequestValidator : AbstractValidator<RegisterRequest>
{
    public RegisterRequestValidator()
    {
        RuleFor(x => x.Email).NotEmpty().EmailAddress().Length(5, 320);
        RuleFor(x => x.Username).NotEmpty().Length(3, 64).Matches("^[a-z0-9_]+$");
        RuleFor(x => x.Password).NotEmpty().Length(8, 128);
        RuleFor(x => x.Name).MaximumLength(255);
    }
}

public class LoginRequestValidator : AbstractValidator<LoginRequest>
{
    public LoginRequestValidator()
    {
        RuleFor(x => x.Password).NotEmpty().MaximumLength(128);
        RuleFor(x => x.DeviceToken).MaximumLength(512);
    }
}

public class GoogleAuthRequestValidator : AbstractValidator<GoogleAuthRequest>
{
    public GoogleAuthRequestValidator()
    {
        RuleFor(x => x.IdToken).NotEmpty().Length(20, 12000);
    }
}

public class ForgotPasswordRequestValidator : AbstractValidator<ForgotPasswordRequest>
{
    public ForgotPasswordRequestValidator()
    {
        RuleFor(x => x.Email).NotEmpty().EmailAddress().Length(3, 320);
    }
}

public class ResetPasswordRequestValidator : AbstractValidator<ResetPasswordRequest>
{
    public ResetPasswordRequestValidator()
    {
        RuleFor(x => x.Token).NotEmpty().Length(10, 2000);
        RuleFor(x => x.NewPassword).NotEmpty().Length(8, 128);
    }
}
