using Bma.Data;
using Bma.Domain;
using Microsoft.EntityFrameworkCore;

namespace Bma.Integration;

public sealed class OutboxProjectionWorker(
    IServiceScopeFactory scopeFactory,
    ILogger<OutboxProjectionWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            var processed = false;
            try { processed = await ProcessOneAsync(stoppingToken); }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception ex) { logger.LogError(ex, "Outbox worker iteration failed."); }
            if (!processed) await Task.Delay(TimeSpan.FromSeconds(2), stoppingToken);
        }
    }

    private async Task<bool> ProcessOneAsync(CancellationToken ct)
    {
        Guid? failedMessageId = null;
        try
        {
            await using var scope = scopeFactory.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<BmaDbContext>();
            var projector = scope.ServiceProvider.GetRequiredService<CanonicalEventProjector>();
            await using var transaction = await db.Database.BeginTransactionAsync(ct);
            await db.Database.ExecuteSqlRawAsync("SELECT pg_advisory_xact_lock(4242001)", ct);
            var message = await db.OutboxMessages
                .Where(x => x.Topic == "bma.project.canonical-event" &&
                            x.ProcessedAt == null && x.NextAttemptAt <= DateTimeOffset.UtcNow)
                .OrderBy(x => x.OccurredAt).FirstOrDefaultAsync(ct);
            if (message is null)
            {
                await transaction.CommitAsync(ct);
                return false;
            }
            failedMessageId = message.Id;
            if (!Guid.TryParse(message.MessageKey, out var rawId))
                throw new InvalidOperationException("Outbox message key is not a raw event ID.");
            var raw = await db.RawIntegrationEvents.SingleAsync(x => x.Id == rawId, ct);
            await projector.ProjectAsync(raw, ct);
            raw.ProcessingState = IntegrationProcessingState.Projected;
            raw.ProcessingError = null;
            message.ProcessedAt = DateTimeOffset.UtcNow;
            message.LastError = null;
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
            return true;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            if (failedMessageId is not null) await MarkFailureAsync(failedMessageId.Value, ex, ct);
            throw;
        }
    }

    private async Task MarkFailureAsync(Guid id, Exception exception, CancellationToken ct)
    {
        await using var scope = scopeFactory.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<BmaDbContext>();
        var message = await db.OutboxMessages.SingleOrDefaultAsync(x => x.Id == id, ct);
        if (message is null) return;
        message.AttemptCount++;
        message.LastError = exception.Message[..Math.Min(exception.Message.Length, 1000)];
        message.NextAttemptAt = DateTimeOffset.UtcNow.AddSeconds(
            Math.Min(300, Math.Pow(2, Math.Min(message.AttemptCount, 8))));
        if (Guid.TryParse(message.MessageKey, out var rawId))
        {
            var raw = await db.RawIntegrationEvents.SingleOrDefaultAsync(x => x.Id == rawId, ct);
            if (raw is not null)
            {
                raw.ProcessingState = IntegrationProcessingState.Failed;
                raw.ProcessingError = message.LastError;
            }
        }
        await db.SaveChangesAsync(ct);
    }
}
