using System.Net.Http.Json;
using Bma.Data;
using Bma.Domain;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Bma.Integration;

public sealed class GatewayReconciliationWorker(
    IServiceScopeFactory scopeFactory,
    IHttpClientFactory clients,
    IOptions<GatewayOptions> options,
    ILogger<GatewayReconciliationWorker> logger) : BackgroundService
{
    private readonly GatewayOptions gateway = options.Value;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!gateway.ReconciliationEnabled)
        {
            logger.LogInformation("Gateway reconciliation is disabled until history/cursor is available.");
            return;
        }
        if (string.IsNullOrWhiteSpace(gateway.HistoryKey))
            throw new InvalidOperationException("Gateway history key is required when reconciliation is enabled.");

        while (!stoppingToken.IsCancellationRequested)
        {
            try { await ReconcileOnceAsync(stoppingToken); }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception ex) { logger.LogError(ex, "Gateway reconciliation failed."); }
            await Task.Delay(TimeSpan.FromSeconds(Math.Clamp(gateway.IntervalSeconds, 15, 3600)), stoppingToken);
        }
    }

    private async Task ReconcileOnceAsync(CancellationToken ct)
    {
        await using var scope = scopeFactory.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<BmaDbContext>();
        var ingestion = scope.ServiceProvider.GetRequiredService<IntegrationIngestionService>();
        var cursorRow = await db.IntegrationCursors.SingleOrDefaultAsync(x => x.SourceSystem == "GATEWAY", ct);
        var cursor = cursorRow?.Cursor;
        var client = clients.CreateClient("GatewayHistory");
        client.DefaultRequestHeaders.Remove("X-BMA-History-Key");
        client.DefaultRequestHeaders.Add("X-BMA-History-Key", gateway.HistoryKey);
        var separator = gateway.HistoryPath.Contains('?') ? '&' : '?';
        var url = $"{gateway.HistoryPath}{separator}limit={Math.Clamp(gateway.BatchSize, 1, 500)}" +
                  (cursor is null ? "" : $"&cursor={Uri.EscapeDataString(cursor)}");
        using var response = await client.GetAsync(url, ct);
        response.EnsureSuccessStatusCode();
        var page = await response.Content.ReadFromJsonAsync<GatewayHistoryPage>(cancellationToken: ct)
            ?? throw new InvalidOperationException("Gateway history returned an empty response.");

        foreach (var item in page.Items)
        {
            var result = await ingestion.IngestAsync(item, ct);
            if (result.Status is IngestionStatus.InvalidContract or IngestionStatus.InvalidHash)
            {
                db.AuditEntries.Add(new AuditEntry
                {
                    Action = "RECONCILIATION_EVENT_REJECTED",
                    SubjectType = "INTEGRATION_EVENT",
                    SubjectId = item.EventId,
                    CorrelationId = item.CorrelationId,
                    AfterJson = System.Text.Json.JsonSerializer.Serialize(new { result.Error })
                });
            }
        }

        if (!string.IsNullOrWhiteSpace(page.NextCursor))
        {
            if (cursorRow is null)
                db.IntegrationCursors.Add(new IntegrationCursor
                    { SourceSystem = "GATEWAY", Cursor = page.NextCursor });
            else
            {
                cursorRow.Cursor = page.NextCursor;
                cursorRow.UpdatedAt = DateTimeOffset.UtcNow;
            }
            await db.SaveChangesAsync(ct);
        }
        logger.LogInformation("Reconciled {Count} events; has_more={HasMore}.", page.Items.Count, page.HasMore);
    }
}
