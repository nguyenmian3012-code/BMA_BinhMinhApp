using System.Text.Json;
using Bma.Data;
using Bma.Domain;
using Bma.Modules;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Bma.Integration;

public sealed class CanonicalEventProjector(
    BmaDbContext db,
    IOptions<PlantOptions> options,
    AttendancePolicy attendance)
{
    private readonly PlantOptions plant = options.Value;

    public async Task ProjectAsync(RawIntegrationEvent raw, CancellationToken ct)
    {
        using var document = JsonDocument.Parse(raw.PayloadJson);
        var payload = document.RootElement;
        switch (raw.EventType)
        {
            case CanonicalEventTypes.MotorStateChanged:
                await ProjectMotorAsync(raw, payload, ct);
                break;
            case CanonicalEventTypes.QualityResultPublished:
                ProjectQuality(raw, payload);
                break;
            case CanonicalEventTypes.EmployeeScan:
                await ProjectAttendanceScanAsync(raw, payload, ct);
                break;
            case CanonicalEventTypes.EmployeeEntry:
            case CanonicalEventTypes.EmployeeExit:
                await ProjectAttendanceAsync(raw, payload, ct);
                break;
            case CanonicalEventTypes.ProductionMassRecorded:
                ProjectMass(raw, payload);
                break;
            case CanonicalEventTypes.AnnouncementPublished:
                ProjectAnnouncement(payload);
                break;
            default:
                throw new InvalidOperationException($"Unsupported canonical event type: {raw.EventType}");
        }
    }

    private async Task ProjectMotorAsync(RawIntegrationEvent raw, JsonElement payload, CancellationToken ct)
    {
        var position = RequiredString(payload, "position").ToUpperInvariant();
        if (position is not ("INPUT" or "OUTPUT"))
            throw new InvalidOperationException("Motor position must be INPUT or OUTPUT.");
        var changedAt = raw.OccurredAt;
        var state = RequiredString(payload, "state").ToUpperInvariant();
        var heartbeat = RequiredDateTime(payload, "heartbeat_at");
        var row = await db.MotorStateProjections.SingleOrDefaultAsync(x => x.Position == position, ct);
        if (row is not null && row.ChangedAt > changedAt)
        {
            AddAudit("LATE_MOTOR_EVENT_IGNORED", raw, new { position, row.ChangedAt, changedAt });
            return;
        }
        if (row is null)
        {
            row = new MotorStateProjection
            {
                Position = position,
                MotorId = RequiredString(payload, "motor_id"),
                SourceEventId = raw.EventId
            };
            db.MotorStateProjections.Add(row);
        }
        row.MotorId = RequiredString(payload, "motor_id");
        row.IsOn = state switch
        {
            "ON" => true,
            "OFF" => false,
            _ => throw new InvalidOperationException("Motor state must be ON or OFF.")
        };
        row.HeartbeatAt = heartbeat;
        row.ChangedAt = changedAt;
        row.SourceEventId = raw.EventId;

        var states = await db.MotorStateProjections.ToListAsync(ct);
        // A newly added projection is not visible to the database query until SaveChanges.
        // Include the current tracked row so the first event from the second motor can
        // immediately produce STARTING/RUNNING/DRAINING/STOPPED instead of UNKNOWN.
        var input = position == "INPUT" ? row : states.SingleOrDefault(x => x.Position == "INPUT");
        var output = position == "OUTPUT" ? row : states.SingleOrDefault(x => x.Position == "OUTPUT");
        var projected = PlantStateCalculator.Calculate(input, output, changedAt,
            plant.HeartbeatStaleSeconds);
        var open = await db.PlantStatePeriods.SingleOrDefaultAsync(x => x.EndedAt == null, ct);
        if (open?.State == projected) return;
        if (open is not null) open.EndedAt = changedAt < open.StartedAt ? open.StartedAt : changedAt;
        db.PlantStatePeriods.Add(new PlantStatePeriod
        {
            State = projected,
            StartedAt = changedAt,
            SourceEventId = raw.EventId
        });
    }

    private void ProjectQuality(RawIntegrationEvent raw, JsonElement payload)
    {
        db.QualityReadings.Add(new QualityReading
        {
            SourceEventId = raw.EventId,
            ResultId = RequiredString(payload, "result_id"),
            LotCode = RequiredString(payload, "lot_code"),
            MeasuredAt = RequiredDateTime(payload, "measured_at"),
            Ph = RequiredDecimal(payload, "ph"),
            Whiteness = RequiredDecimal(payload, "whiteness"),
            Moisture = RequiredDecimal(payload, "moisture"),
            Fineness = OptionalDecimal(payload, "fineness"),
            FinenessUnit = OptionalString(payload, "fineness_unit"),
            Viscosity = OptionalDecimal(payload, "viscosity"),
            ViscosityUnit = OptionalString(payload, "viscosity_unit"),
            ExtraValue = OptionalDecimal(payload, "extra_value"),
            ProductCode = OptionalString(payload, "product_code"),
            OperatorCode = OptionalString(payload, "operator_code"),
            QualityCode = OptionalString(payload, "quality_code"),
            CustomerCode = OptionalString(payload, "customer_code")
        });
    }

    private async Task ProjectAttendanceAsync(RawIntegrationEvent raw, JsonElement payload,
        CancellationToken ct)
    {
        var employee = RequiredString(payload, "employee_id");
        var kind = raw.EventType == CanonicalEventTypes.EmployeeEntry
            ? AttendanceKind.Entry : AttendanceKind.Exit;
        var workDate = attendance.Classify(raw.OccurredAt).WorkDate;
        AddAttendanceEvent(raw, payload, employee, kind);

        var session = await db.AttendanceSessions.SingleOrDefaultAsync(
            x => x.EmployeeId == employee && x.WorkDate == workDate, ct);
        if (kind == AttendanceKind.Entry)
        {
            if (session is null)
                db.AttendanceSessions.Add(new AttendanceSession
                {
                    EmployeeId = employee,
                    EntryAt = raw.OccurredAt,
                    EntryEventId = raw.EventId,
                    WorkDate = workDate,
                    ShiftCode = attendance.Options.ShiftCode,
                    Status = AttendanceSessionStatus.Provisional
                });
            else
            {
                session.Status = AttendanceSessionStatus.NeedsReview;
                session.ReviewReason = "DUPLICATE_ENTRY_WITHOUT_EXIT";
                AddAudit("ATTENDANCE_NEEDS_REVIEW", raw,
                    new { employee, session.Id, session.ReviewReason });
            }
            return;
        }

        if (session is null)
        {
            db.AttendanceSessions.Add(new AttendanceSession
            {
                EmployeeId = employee,
                ExitAt = raw.OccurredAt,
                ExitEventId = raw.EventId,
                WorkDate = workDate,
                ShiftCode = attendance.Options.ShiftCode,
                CreditedMinutes = attendance.MissingPunchMinutes,
                Status = AttendanceSessionStatus.NeedsReview,
                ReviewReason = "EXIT_WITHOUT_ENTRY"
            });
            AddAudit("ATTENDANCE_NEEDS_REVIEW", raw, new { employee, reason = "EXIT_WITHOUT_ENTRY" });
            return;
        }

        session.ExitAt = raw.OccurredAt;
        session.ExitEventId = raw.EventId;
        if (session.EntryAt is not null && raw.OccurredAt >= session.EntryAt)
        {
            session.Status = AttendanceSessionStatus.Confirmed;
            session.ReviewReason = null;
            session.CreditedMinutes = attendance.CalculateCreditedMinutes(
                workDate, session.EntryAt.Value, raw.OccurredAt);
        }
        else
        {
            session.Status = AttendanceSessionStatus.NeedsReview;
            session.ReviewReason = "EXIT_BEFORE_ENTRY";
            session.CreditedMinutes = attendance.MissingPunchMinutes;
            AddAudit("ATTENDANCE_NEEDS_REVIEW", raw,
                new { employee, session.Id, session.ReviewReason });
        }
    }

    private async Task ProjectAttendanceScanAsync(RawIntegrationEvent raw, JsonElement payload,
        CancellationToken ct)
    {
        var employee = RequiredString(payload, "employee_id");
        var decision = attendance.Classify(raw.OccurredAt);
        if (decision.Window is AttendanceScanWindow.Break or
            AttendanceScanWindow.OutsideShift or AttendanceScanWindow.NonWorkingDay)
        {
            AddAudit("ATTENDANCE_SCAN_IGNORED", raw,
                new { employee, decision.WorkDate, window = decision.Window.ToString() });
            return;
        }

        var session = await db.AttendanceSessions.SingleOrDefaultAsync(
            x => x.EmployeeId == employee && x.WorkDate == decision.WorkDate, ct);
        if (decision.Window == AttendanceScanWindow.Entry)
        {
            if (session is not null)
            {
                AddAudit("ATTENDANCE_SCAN_DUPLICATE", raw,
                    new { employee, decision.WorkDate, resolved_kind = "ENTRY", session.Id });
                return;
            }

            AddAttendanceEvent(raw, payload, employee, AttendanceKind.Entry);
            db.AttendanceSessions.Add(new AttendanceSession
            {
                EmployeeId = employee,
                EntryAt = raw.OccurredAt,
                EntryEventId = raw.EventId,
                WorkDate = decision.WorkDate,
                ShiftCode = attendance.Options.ShiftCode,
                Status = AttendanceSessionStatus.Provisional
            });
            return;
        }

        if (session is null)
        {
            AddAttendanceEvent(raw, payload, employee, AttendanceKind.Exit);
            db.AttendanceSessions.Add(new AttendanceSession
            {
                EmployeeId = employee,
                ExitAt = raw.OccurredAt,
                ExitEventId = raw.EventId,
                WorkDate = decision.WorkDate,
                ShiftCode = attendance.Options.ShiftCode,
                CreditedMinutes = attendance.MissingPunchMinutes,
                Status = AttendanceSessionStatus.NeedsReview,
                ReviewReason = "MISSING_ENTRY"
            });
            AddAudit("ATTENDANCE_NEEDS_REVIEW", raw,
                new { employee, decision.WorkDate, reason = "MISSING_ENTRY" });
            return;
        }

        if (session.EntryAt is null || session.ExitAt is not null ||
            session.Status != AttendanceSessionStatus.Provisional)
        {
            AddAudit("ATTENDANCE_SCAN_DUPLICATE", raw,
                new { employee, decision.WorkDate, resolved_kind = "EXIT", session.Id });
            return;
        }

        AddAttendanceEvent(raw, payload, employee, AttendanceKind.Exit);
        session.ExitAt = raw.OccurredAt;
        session.ExitEventId = raw.EventId;
        session.Status = AttendanceSessionStatus.Confirmed;
        session.ReviewReason = null;
        session.CreditedMinutes = attendance.CalculateCreditedMinutes(
            decision.WorkDate, session.EntryAt.Value, raw.OccurredAt);
    }

    private void AddAttendanceEvent(RawIntegrationEvent raw, JsonElement payload,
        string employee, AttendanceKind kind) => db.AttendanceEvents.Add(new AttendanceEvent
        {
            SourceEventId = raw.EventId,
            EmployeeId = employee,
            Kind = kind,
            OccurredAt = raw.OccurredAt,
            SourceSystem = raw.SourceSystem,
            SourceDeviceId = raw.SourceDeviceId,
            Sequence = raw.Sequence,
            EvidenceRef = RequiredString(payload, "evidence_ref")
        });

    private void ProjectMass(RawIntegrationEvent raw, JsonElement payload)
    {
        db.ProductionMassReadings.Add(new ProductionMassReading
        {
            SourceEventId = raw.EventId,
            PeriodId = RequiredString(payload, "period_id"),
            Kind = RequiredString(payload, "kind") switch
            {
                "CASSAVA_INPUT" => ProductionMassKind.CassavaInput,
                "STARCH_OUTPUT" => ProductionMassKind.StarchOutput,
                _ => throw new InvalidOperationException("Invalid production mass kind.")
            },
            MassKg = RequiredDecimal(payload, "mass_kg"),
            Basis = RequiredString(payload, "basis") switch
            {
                "WET" => MassBasis.Wet,
                "DRY" => MassBasis.Dry,
                "AS_WEIGHED" => MassBasis.AsWeighed,
                _ => throw new InvalidOperationException("Invalid mass basis.")
            },
            Approved = payload.GetProperty("approved").GetBoolean(),
            FormulaVersion = RequiredString(payload, "formula_version"),
            RecordedAt = raw.OccurredAt
        });
    }

    private void ProjectAnnouncement(JsonElement payload)
    {
        var audience = RequiredString(payload, "audience");
        db.Announcements.Add(new Announcement
        {
            Id = Guid.Parse(RequiredString(payload, "announcement_id")),
            Title = RequiredString(payload, "title"),
            Body = RequiredString(payload, "body"),
            Audience = Enum.Parse<AnnouncementAudience>(audience, true),
            AudienceValue = OptionalString(payload, "audience_value"),
            Priority = OptionalString(payload, "priority") ?? "NORMAL",
            CreatedBy = Guid.Parse(RequiredString(payload, "created_by")),
            PublishedAt = payload.TryGetProperty("published_at", out var at)
                ? at.GetDateTimeOffset() : DateTimeOffset.UtcNow,
            ExpiresAt = payload.TryGetProperty("expires_at", out var expires) &&
                        expires.ValueKind != JsonValueKind.Null
                ? expires.GetDateTimeOffset() : null
        });
    }

    private void AddAudit(string action, RawIntegrationEvent raw, object after) =>
        db.AuditEntries.Add(new AuditEntry
        {
            Action = action,
            SubjectType = "INTEGRATION_EVENT",
            SubjectId = raw.EventId,
            CorrelationId = raw.CorrelationId,
            AfterJson = JsonSerializer.Serialize(after)
        });

    private static string RequiredString(JsonElement value, string name) =>
        value.TryGetProperty(name, out var field) && field.ValueKind == JsonValueKind.String &&
        !string.IsNullOrWhiteSpace(field.GetString())
            ? field.GetString()!
            : throw new InvalidOperationException($"Missing required string payload field: {name}");
    private static string? OptionalString(JsonElement value, string name) =>
        value.TryGetProperty(name, out var field) && field.ValueKind == JsonValueKind.String
            ? field.GetString() : null;
    private static decimal RequiredDecimal(JsonElement value, string name) =>
        value.TryGetProperty(name, out var field) && field.TryGetDecimal(out var result)
            ? result : throw new InvalidOperationException($"Missing required numeric payload field: {name}");
    private static decimal? OptionalDecimal(JsonElement value, string name) =>
        value.TryGetProperty(name, out var field) && field.ValueKind != JsonValueKind.Null &&
        field.TryGetDecimal(out var result) ? result : null;
    private static DateTimeOffset RequiredDateTime(JsonElement value, string name) =>
        value.TryGetProperty(name, out var field) && field.ValueKind == JsonValueKind.String &&
        field.TryGetDateTimeOffset(out var result)
            ? result.ToUniversalTime()
            : throw new InvalidOperationException($"Missing required datetime payload field: {name}");
}
