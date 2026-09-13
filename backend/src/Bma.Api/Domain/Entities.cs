namespace Bma.Domain;

public enum AccountStatus { Pending, Approved, Rejected, Disabled }
public enum IntegrationProcessingState { Pending, Projected, Failed }
public enum PlantState { Unknown, Starting, Running, Draining, Stopped }
public enum AttendanceKind { Entry, Exit }
public enum AttendanceSessionStatus { Provisional, Confirmed, NeedsReview, Approved }
public enum AnnouncementAudience { Company, Department, Role, Person }
public enum ProductionMassKind { CassavaInput, StarchOutput }
public enum MassBasis { Wet, Dry, AsWeighed }

public sealed class AppUser
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public required string UserName { get; set; }
    public required string NormalizedUserName { get; set; }
    public required string DisplayName { get; set; }
    public string? EmployeeCode { get; set; }
    public required string PasswordHash { get; set; }
    public AccountStatus Status { get; set; } = AccountStatus.Pending;
    public string Roles { get; set; } = "Employee";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? ApprovedAt { get; set; }
    public Guid? ApprovedBy { get; set; }
}

public sealed class RefreshSession
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public required string TokenHash { get; set; }
    public required string TokenFamily { get; set; }
    public string? DeviceName { get; set; }
    public string? IpAddress { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? RevokedAt { get; set; }
    public string? RevocationReason { get; set; }
    public string? ReplacedByHash { get; set; }
    public AppUser? User { get; set; }
}

public sealed class RawIntegrationEvent
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public required string EventId { get; set; }
    public required string EventType { get; set; }
    public required string SourceSystem { get; set; }
    public string? SourceDeviceId { get; set; }
    public long? Sequence { get; set; }
    public DateTimeOffset OccurredAt { get; set; }
    public DateTimeOffset ReceivedAt { get; set; } = DateTimeOffset.UtcNow;
    public required string SchemaVersion { get; set; }
    public string? CorrelationId { get; set; }
    public required string PayloadJson { get; set; }
    public required string PayloadHash { get; set; }
    public string? Signature { get; set; }
    public IntegrationProcessingState ProcessingState { get; set; } = IntegrationProcessingState.Pending;
    public string? ProcessingError { get; set; }
}

public sealed class OutboxMessage
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public required string Topic { get; set; }
    public required string MessageKey { get; set; }
    public required string PayloadJson { get; set; }
    public DateTimeOffset OccurredAt { get; set; }
    public DateTimeOffset NextAttemptAt { get; set; } = DateTimeOffset.UtcNow;
    public int AttemptCount { get; set; }
    public DateTimeOffset? ProcessedAt { get; set; }
    public string? LastError { get; set; }
}

public sealed class AuditEntry
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public DateTimeOffset OccurredAt { get; set; } = DateTimeOffset.UtcNow;
    public Guid? ActorUserId { get; set; }
    public required string Action { get; set; }
    public required string SubjectType { get; set; }
    public required string SubjectId { get; set; }
    public string? CorrelationId { get; set; }
    public string? BeforeJson { get; set; }
    public string? AfterJson { get; set; }
    public string? IpAddress { get; set; }
}

public sealed class IntegrationCursor
{
    public required string SourceSystem { get; set; }
    public required string Cursor { get; set; }
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class MotorStateProjection
{
    public required string Position { get; set; }
    public required string MotorId { get; set; }
    public bool IsOn { get; set; }
    public DateTimeOffset HeartbeatAt { get; set; }
    public DateTimeOffset ChangedAt { get; set; }
    public required string SourceEventId { get; set; }
}

public sealed class PlantStatePeriod
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public PlantState State { get; set; }
    public DateTimeOffset StartedAt { get; set; }
    public DateTimeOffset? EndedAt { get; set; }
    public required string SourceEventId { get; set; }
}

public sealed class RunSchedule
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public DateTimeOffset PlannedStartAt { get; set; }
    public string Status { get; set; } = "PLANNED";
    public string? Note { get; set; }
    public Guid CreatedBy { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class QualityReading
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public required string SourceEventId { get; set; }
    public required string ResultId { get; set; }
    public required string LotCode { get; set; }
    public DateTimeOffset MeasuredAt { get; set; }
    public decimal Ph { get; set; }
    public decimal Whiteness { get; set; }
    public decimal Moisture { get; set; }
    public decimal? Fineness { get; set; }
    public string? FinenessUnit { get; set; }
    public decimal? Viscosity { get; set; }
    public string? ViscosityUnit { get; set; }
    public decimal? ExtraValue { get; set; }
    public string? ProductCode { get; set; }
    public string? OperatorCode { get; set; }
    public string? QualityCode { get; set; }
    public string? CustomerCode { get; set; }
}

public sealed class ProductionMassReading
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public required string SourceEventId { get; set; }
    public required string PeriodId { get; set; }
    public ProductionMassKind Kind { get; set; }
    public decimal MassKg { get; set; }
    public MassBasis Basis { get; set; }
    public bool Approved { get; set; }
    public required string FormulaVersion { get; set; }
    public DateTimeOffset RecordedAt { get; set; }
}

public sealed class AttendanceEvent
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public required string SourceEventId { get; set; }
    public required string EmployeeId { get; set; }
    public AttendanceKind Kind { get; set; }
    public DateTimeOffset OccurredAt { get; set; }
    public required string SourceSystem { get; set; }
    public string? SourceDeviceId { get; set; }
    public long? Sequence { get; set; }
    public required string EvidenceRef { get; set; }
}

public sealed class AttendanceSession
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public required string EmployeeId { get; set; }
    public DateTimeOffset? EntryAt { get; set; }
    public DateTimeOffset? ExitAt { get; set; }
    public string? EntryEventId { get; set; }
    public string? ExitEventId { get; set; }
    public DateOnly? WorkDate { get; set; }
    public string? ShiftCode { get; set; }
    public int CreditedMinutes { get; set; }
    public AttendanceSessionStatus Status { get; set; }
    public string? ReviewReason { get; set; }
    public Guid? ApprovedBy { get; set; }
    public DateTimeOffset? ApprovedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class EmployeeProfile
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid? UserId { get; set; }
    public required string EmployeeCode { get; set; }
    public required string FullName { get; set; }
    public string? Department { get; set; }
    public string? Position { get; set; }
    public string? ManagerEmployeeCode { get; set; }
    public string Responsibilities { get; set; } = "";
    public string Obligations { get; set; } = "";
    public string Benefits { get; set; } = "";
    public string Accountabilities { get; set; } = "";
    public DateOnly EffectiveFrom { get; set; }
    public int Version { get; set; } = 1;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class Announcement
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public required string Title { get; set; }
    public required string Body { get; set; }
    public AnnouncementAudience Audience { get; set; }
    public string? AudienceValue { get; set; }
    public string Priority { get; set; } = "NORMAL";
    public DateTimeOffset PublishedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? ExpiresAt { get; set; }
    public Guid CreatedBy { get; set; }
}

public sealed class AnnouncementRead
{
    public Guid AnnouncementId { get; set; }
    public Guid UserId { get; set; }
    public DateTimeOffset ReadAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class PushDevice
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public required string Platform { get; set; }
    public required string TokenHash { get; set; }
    public required string EncryptedToken { get; set; }
    public DateTimeOffset RegisteredAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? RevokedAt { get; set; }
}
