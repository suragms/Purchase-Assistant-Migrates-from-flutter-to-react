using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using PurchaseAssistant.Application;
using PurchaseAssistant.Infrastructure;
using PurchaseAssistant.Infrastructure.BackgroundServices;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

// Serilog
Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)
    .Enrich.FromLogContext()
    .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj}{NewLine}{Exception}")
    .CreateLogger();

builder.Host.UseSerilog();

// Controllers + OpenAPI
builder.Services.AddControllers();
builder.Services.AddOpenApi();

// JWT Authentication
var jwtSecret = builder.Configuration["Jwt:Secret"] ?? "change-me-min-32-chars-dev-only";
var jwtRefreshSecret = builder.Configuration["Jwt:RefreshSecret"] ?? "change-me-min-32-chars-refresh-dev";

builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(options =>
{
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = false,
        ValidateAudience = false,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecret)),
        ClockSkew = TimeSpan.Zero
    };
});

builder.Services.AddAuthorization();

// CORS
var corsOrigins = builder.Configuration.GetValue<string>("CorsOrigins")
    ?? "http://localhost:5173,http://127.0.0.1:5173,http://localhost:3000,http://127.0.0.1:3000";

builder.Services.AddCors(options =>
{
    options.AddPolicy("Default", policy =>
    {
        policy.WithOrigins(corsOrigins.Split(','))
            .AllowAnyHeader()
            .AllowAnyMethod()
            .AllowCredentials();
    });
});

// Application & Infrastructure
builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);

// Background hosted services (migrated from Python scheduled_notification_jobs)
builder.Services.AddHostedService<IdleDeliveryNotificationService>();
builder.Services.AddHostedService<EveningPhysicalCountReminderService>();

var app = builder.Build();

// Middleware pipeline
app.UseSerilogRequestLogging();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseCors("Default");
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

// Health check root (/)
app.MapGet("/", () => Results.Ok(new
{
    service = "purchase-assistant-dotnet",
    docs = "/swagger",
    openapi_json = "/swagger/v1/swagger.json",
    health = "/health",
    health_ready = "/health/ready",
    hint = "React and .NET migration shell is active; use /health/ready for database readiness."
}));

try
{
    Log.Information("Starting Purchase Assistant API");
    app.Run();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Application terminated unexpectedly");
}
finally
{
    Log.CloseAndFlush();
}
