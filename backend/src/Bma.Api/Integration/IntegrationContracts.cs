using System.Text.Json;
using System.Text.Json.Serialization;

namespace Bma.Integration;

public static class CanonicalEventTypes
{
    public const string MotorStateChanged = "MOTOR_STATE_CHANGED";
    public const string QualityResultPublished = "QUALITY_RESULT_PUBLISHED";
    public const string EmployeeEntry = "EMPLOYEE_ENTRY";
    public const string EmployeeExit = "EMPLOYEE_EXIT";
    public const string ProductionMassRecorded = "PRODUCTION_MASS_RECORDED";
    public const string AnnouncementPublished = "ANNOUNCEMENT_PUBLISHED";

    public static readonly HashSet<string> Supported =
    [
        MotorStateChanged,
        QualityResultPublished,
        EmployeeEntry,
        EmployeeExit,
        ProductionMassRecorded,
        AnnouncementPublished
    ];
}

public sealed record CanonicalEvent(
    string EventId,
    string EventType,
    string SourceSystem,
    string? SourceDeviceId,
    long? Sequence,
    DateTimeOffset OccurredAt,
    string SchemaVersion,
    string? CorrelationId,
    JsonElement Payload,
    string PayloadHash,
    string? Signature);

public sealed class GatewayOptions
{
    public const string Section = "Gateway";
    public string InboundKey { get; set; } = "";
    public bool ReconciliationEnabled { get; set; }
    public string BaseUrl { get; set; } = "https://gateway.abmtlab.com";
    public string HistoryPath { get; set; } = "/api/bma/v1/integration-events";
    public string HistoryKey { get; set; } = "";
    public int IntervalSeconds { get; set; } = 60;
    public int BatchSize { get; set; } = 100;
}

public sealed record GatewayHistoryPage(
    [property: JsonPropertyName("items")] IReadOnlyList<CanonicalEvent> Items,
    [property: JsonPropertyName("next_cursor")] string? NextCursor,
    [property: JsonPropertyName("has_more")] bool HasMore);

public enum IngestionStatus { Accepted, Duplicate, InvalidContract, InvalidHash }
public sealed record IngestionResult(IngestionStatus Status, Guid? RawEventId = null, string? Error = null);
