using FluentValidation;
using Microsoft.AspNetCore.Mvc.Filters;

namespace PurchaseAssistant.Api.Filters;

public class ValidationFilter<T> : IAsyncActionFilter where T : class
{
    private readonly IValidator<T> _validator;

    public ValidationFilter(IValidator<T> validator) => _validator = validator;

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var model = context.ActionArguments.Values.OfType<T>().FirstOrDefault();
        if (model is not null)
        {
            var result = await _validator.ValidateAsync(model);
            if (!result.IsValid)
            {
                var errors = result.Errors.Select(e => e.ErrorMessage).ToList();
                context.Result = new Microsoft.AspNetCore.Mvc.BadRequestObjectResult(new { errors });
                return;
            }
        }
        await next();
    }
}
