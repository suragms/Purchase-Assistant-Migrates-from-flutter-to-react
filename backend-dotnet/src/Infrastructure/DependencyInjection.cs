using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using PurchaseAssistant.Application.Common.Interfaces;
using PurchaseAssistant.Application.Interfaces;
using PurchaseAssistant.Application.Services;
using PurchaseAssistant.Infrastructure.Data;
using PurchaseAssistant.Infrastructure.Services;

namespace PurchaseAssistant.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        var useInMemory = configuration.GetValue<bool>("UseInMemoryDatabase");
        if (useInMemory)
        {
            services.AddDbContext<PurchaseAssistantDbContext>(options =>
                options.UseInMemoryDatabase("TestDb"));
        }
        else
        {
            services.AddDbContext<PurchaseAssistantDbContext>(options =>
                options.UseNpgsql(
                    configuration.GetConnectionString("DefaultConnection"),
                    npgsqlOptions => npgsqlOptions.CommandTimeout(45)));
        }

        services.AddScoped<IJwtService, JwtService>();
        services.AddScoped<IPasswordService, PasswordService>();
        services.AddScoped<IGoogleOAuthService, GoogleOAuthService>();
        services.AddScoped<IPermissionService, PermissionService>();
        services.AddScoped<IUsernameService, UsernameService>();
        services.AddSingleton<IOtpService, OtpService>();
        services.AddScoped<INotificationService, NotificationService>();
        services.AddScoped<ILegacyArchiveService, LegacyArchiveService>();

        // Stock
        services.AddScoped<IStockService, StockService>();
        services.AddScoped<PurchaseAssistant.Application.Services.ITradePurchaseService, TradePurchaseService>();

        return services;
    }
}
