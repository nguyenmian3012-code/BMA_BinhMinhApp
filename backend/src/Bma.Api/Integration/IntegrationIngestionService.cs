using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Bma.Data;
using Bma.Domain;
using Bma.Modules;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Bma.Integration;

public sealed class IntegrationIngestionService(
    BmaDbContext db,
    IOptions<GatewayOptions> options,
    AuditWriter audit)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
    };
    private readonly GatewayOptions gateway = options.Value;

    public bool IsInboundKeyValid(string? provided) =>
        !string.IsNullOrWhiteSpace(gateway.InboundKey) &&
        !string.IsNullOrWhiteSpace(provided) &&
        FixedTimeEquals(gateway.InboundKey, provided);

    public async Task<IngestionResult> IngestAsync(CanonicalEvent message, CancellationToken ct)
    {
        var contractError = Validate(message);
        if (contractError is not null)
            return new(IngestionStatus.InvalidContract, Error: contractError);

        var computedHash = ComputePayloadHash(message.Payload);
        if (!FixedTimeEquals(computedHash, message.PayloadHash.ToLowerInvariant()))
            return new(IngestionStatus.InvalidHash, Error: "PAYLOAD_HASH_MISMATCH");

        var source = message.SourceSystem.Trim().ToUpperInvariant();
        var eventId = message.EventId.Trim();
        var existing = await db.RawIntegrationEvents.AsNoTracking()
            .Where(x => x.SourceSystem == source && x.EventId == eventId)
            .Select(x => (Guid?)x.Id).SingleOrDefaultAsync(ct);
        if (existing is not null) return new(IngestionStatus.Duplicate, existing);

        await using var transaction = await db.Database.BeginTransactionAsync(ct);
        var raw = new RawIntegrationEvent
        {
            EventId = eventId,
            EventType = message.EventType,
            SourceSystem = source,
            SourceDeviceId = NullIfWhiteSpace(message.SourceDeviceId),
            Sequence = message.Sequence,
            OccurredAt = message.OccurredAt.ToUniversalTime(),
            SchemaVersion = message.SchemaVersion,
            CorrelationId = NullIfWhiteSpace(message.CorrelationId),
            PayloadJson = message.Payload.GetRawText(),
            PayloadHash = computedHash,
            Signature = NullIfWhiteSpace(message.Signature)
        };
        db.RawIntegrationEvents.Add(raw);
        db.OutboxMessages.Add(new OutboxMessage
        {
            Topic = "bma.project.canonical-event",
            MessageKey = raw.Id.ToString(),
            PayloadJson = JsonSerializer.Serialize(message, JsonOptions),
            OccurredAt = raw.OccurredAt
        });

        if (message.Sequence is not null && message.SourceDeviceId is not null)
        {
            var lastSequence = await db.RawIntegrationEvents.AsNoTracking()
                .Where(x => x.SourceDeviceId == message.SourceDeviceId && x.Sequence != null)
                .MaxAsync(x => x.Sequence, ct);
            if (lastSequence is not null && message.Sequence > lastSequence + 1)
                audit.Add("INTEGRATION_SEQUENCE_GAP", "DEVICE", message.SourceDeviceId,
                    correlationId: message.CorrelationId,
                    after: new { previous = lastSequence, current = message.Sequence });
            if (lastSequence is not null && message.Sequence <= lastSequence)
                audit.Add("INTEGRATION_LATE_OR_REORDERED", "DEVICE", message.SourceDeviceId,
                    correlationId: message.CorrelationId,
                    after: new { previous = lastSequence, current = message.Sequence });
        }

        try
        {
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
            return new(IngestionStatus.Accepted, raw.Id);
        }
        catch (DbUpdateException)
        {
            await transaction.RollbackAsync(ct);
            db.ChangeTracker.Clear();
            existing = await db.RawIntegrationEvents.AsNoTracking()
                .Where(x => x.SourceSystem == source && x.EventId == eventId)
                .Select(x => (Guid?)x.Id).SingleOrDefaultAsync(ct);
            if (existing is not null) return new(IngestionStatus.Duplicate, existing);
            throw;
        }
    }

    public static string ComputePayloadHash(JsonElement payload) => Convert.ToHexString(
        SHA256.HashData(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(payload))))
        .ToLowerInvariant();

    private static string? Validate(CanonicalEvent message)
    {
        if (message.SchemaVersion != "1.0") return "UNSUPPORTED_SCHEMA_VERSION";
        if (string.IsNullOrWhiteSpace(message.EventId) || message.EventId.Length > 100)
            return "INVALID_EVENT_ID";
        if (!CanonicalEventTypes.Supported.Contains(message.EventType))
            return "UNSUPPORTED_EVENT_TYPE";
        if (string.IsNullOrWhiteSpace(message.SourceSystem) || message.SourceSystem.Length > 64)
            return "INVALID_SOURCE_SYSTEM";
        if (message.Payload.ValueKind != JsonValueKind.Object) return "PAYLOAD_MUST_BE_OBJECT";
        if (message.PayloadHash.Length != 64) return "INVALID_PAYLOAD_HASH";
        if (message.OccurredAt > DateTimeOffset.UtcNow.AddMinutes(5)) return "EVENT_FROM_FUTURE";
        return null;
    }

    private static bool FixedTimeEquals(string expected, string actual)
    {
        var left = SHA256.HashData(Encoding.UTF8.GetBytes(expected));
        var right = SHA256.HashData(Encoding.UTF8.GetBytes(actual));
        return CryptographicOperations.FixedTimeEquals(left, right);
    }

    private static string? NullIfWhiteSpace(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
