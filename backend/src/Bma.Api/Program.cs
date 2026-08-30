using System.IO.Compression;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Bma.Authentication;
using Bma.Data;
using Bma.Integration;
using Bma.Modules;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.ResponseCompression;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);
builder.Logging.AddJsonConsole();
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower;
    options.SerializerOptions.DictionaryKeyPolicy = JsonNamingPolicy.SnakeCaseLower;
});
builder.Services.Configure<JwtOptions>(builder.Configuration.GetSection(JwtOptions.Section));
builder.Services.Configure<GatewayOptions>(builder.Configuration.GetSection(GatewayOptions.Section));
builder.Services.Configure<PlantOptions>(builder.Configuration.GetSection(PlantOptions.Section));

var connection = builder.Configuration.GetConnectionString("Bma");
if (string.IsNullOrWhiteSpace(connection))
    throw new InvalidOperationException("ConnectionStrings:Bma must be provided.");
builder.Services.AddDbContext<BmaDbContext>(options =>
    options.UseNpgsql(connection).UseSnakeCaseNamingConvention());

var signingKey = builder.Configuration["Jwt:SigningKey"];
if (string.IsNullOrWhiteSpace(signingKey) || Encoding.UTF8.GetByteCount(signingKey) < 32)
    throw new InvalidOperationException("Jwt:SigningKey must contain at least 32 UTF-8 bytes.");
var issuer = builder.Configuration["Jwt:Issuer"] ?? "BMA";
var audience = builder.Configuration["Jwt:Audience"] ?? "BMA.Mobile";
builder.Services.AddAuthentication(options =>
{
    options.DefaultScheme = BmaAuthSchemes.Selector;
    options.DefaultAuthenticateScheme = BmaAuthSchemes.Selector;
    options.DefaultChallengeScheme = BmaAuthSchemes.Selector;
})
.AddPolicyScheme(BmaAuthSchemes.Selector, "BMA bearer or admin cookie", options =>
{
    options.ForwardDefaultSelector = context =>
        context.Request.Headers["Authorization"].ToString().StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)
            ? JwtBearerDefaults.AuthenticationScheme
            : BmaAuthSchemes.Cookie;
})
.AddJwtBearer(options =>
{
    options.MapInboundClaims = false;
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidIssuer = issuer,
        ValidateAudience = true,
        ValidAudience = audience,
        ValidateIssuerSigningKey = true,
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(signingKey)),
        ValidateLifetime = true,
        ClockSkew = TimeSpan.FromSeconds(30),
        NameClaimType = System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.UniqueName,
        RoleClaimType = "role"
    };
})
.AddCookie(BmaAuthSchemes.Cookie, options =>
{
    options.LoginPath = "/bmapp/admin/login";
    options.AccessDeniedPath = "/bmapp/admin/denied";
    options.Cookie.Name = "__Host-BMA-Admin";
    options.Cookie.HttpOnly = true;
    options.Cookie.SameSite = SameSiteMode.Strict;
    options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
    options.SlidingExpiration = true;
    options.ExpireTimeSpan = TimeSpan.FromHours(12);
});
builder.Services.AddAuthorizationBuilder()
    .AddPolicy("Admin", policy => policy.RequireRole("Admin"))
    .AddPolicy("HrOrAdmin", policy => policy.RequireRole("HR", "Admin"));

builder.Services.AddProblemDetails();
builder.Services.AddHealthChecks();
builder.Services.AddRazorPages();
builder.Services.AddHttpContextAccessor();
builder.Services.AddResponseCompression(options =>
{
    options.EnableForHttps = true;
    options.Providers.Add<BrotliCompressionProvider>();
    options.Providers.Add<GzipCompressionProvider>();
    options.MimeTypes = ResponseCompressionDefaults.MimeTypes.Concat(["application/json"]);
});
builder.Services.Configure<BrotliCompressionProviderOptions>(x => x.Level = CompressionLevel.Fastest);
builder.Services.Configure<GzipCompressionProviderOptions>(x => x.Level = CompressionLevel.Fastest);
builder.Services.AddHttpClient("GatewayHistory", (services, client) =>
{
    var gateway = services.GetRequiredService<Microsoft.Extensions.Options.IOptions<GatewayOptions>>().Value;
    client.BaseAddress = new Uri(gateway.BaseUrl);
    client.Timeout = TimeSpan.FromSeconds(15);
});

builder.Services.AddScoped<AuditWriter>();
builder.Services.AddScoped<AuthService>();
builder.Services.AddScoped<IntegrationIngestionService>();
builder.Services.AddScoped<CanonicalEventProjector>();
builder.Services.AddScoped<DashboardService>();
builder.Services.AddScoped<RecoveryService>();
builder.Services.AddHostedService<AdminBootstrapService>();
builder.Services.AddHostedService<OutboxProjectionWorker>();
builder.Services.AddHostedService<GatewayReconciliationWorker>();

var app = builder.Build();
app.UseExceptionHandler();
app.UseResponseCompression();
app.UseStaticFiles();
app.Use(async (context, next) =>
{
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["X-Frame-Options"] = "DENY";
    context.Response.Headers["Referrer-Policy"] = "no-referrer";
    await next();
});
app.UseAuthentication();
app.UseAuthorization();

if (builder.Configuration.GetValue("Database:MigrateOnStartup", true))
{
    await using var scope = app.Services.CreateAsyncScope();
    await scope.ServiceProvider.GetRequiredService<BmaDbContext>().Database.MigrateAsync();
}

app.MapHealthChecks("/bmapp/health").AllowAnonymous();
app.MapBmaAuth();
app.MapBmaIntegration();
app.MapBmaReadApi();
app.MapRazorPages();
app.MapGet("/", () => Results.Redirect("/bmapp/admin")).AllowAnonymous();

await app.RunAsync();

public partial class Program
{
}
