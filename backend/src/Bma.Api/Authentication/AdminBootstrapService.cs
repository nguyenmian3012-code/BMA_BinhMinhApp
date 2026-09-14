using Bma.Data;
using Bma.Domain;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace Bma.Authentication;

public sealed class AdminBootstrapService(
    IServiceScopeFactory scopeFactory,
    IConfiguration configuration,
    ILogger<AdminBootstrapService> logger) : IHostedService
{
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        var username = configuration["BMA_BOOTSTRAP_ADMIN_USERNAME"];
        var password = configuration["BMA_BOOTSTRAP_ADMIN_PASSWORD"];
        if (string.IsNullOrWhiteSpace(username) || string.IsNullOrWhiteSpace(password)) return;
        if (password.Length < 14)
            throw new InvalidOperationException("Bootstrap admin password must contain at least 14 characters.");

        await using var scope = scopeFactory.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<BmaDbContext>();
        var normalized = username.Trim().ToUpperInvariant();
        if (await db.AppUsers.AnyAsync(x => x.NormalizedUserName == normalized, cancellationToken)) return;

        var user = new AppUser
        {
            UserName = username.Trim(),
            NormalizedUserName = normalized,
            DisplayName = "BMA Administrator",
            PasswordHash = "",
            Status = AccountStatus.Approved,
            Roles = "Admin,HR",
            ApprovedAt = DateTimeOffset.UtcNow
        };
        user.PasswordHash = new PasswordHasher<AppUser>().HashPassword(user, password);
        db.AppUsers.Add(user);
        db.AuditEntries.Add(new AuditEntry
        {
            Action = "BOOTSTRAP_ADMIN_CREATED",
            SubjectType = "USER",
            SubjectId = user.Id.ToString(),
            ActorUserId = user.Id
        });
        await db.SaveChangesAsync(cancellationToken);
        logger.LogWarning("Bootstrap administrator created. Remove bootstrap environment variables now.");
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
