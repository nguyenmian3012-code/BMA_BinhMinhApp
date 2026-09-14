using Bma.Domain;
using Microsoft.EntityFrameworkCore;

namespace Bma.Data;

public sealed class BmaDbContext(DbContextOptions<BmaDbContext> options) : DbContext(options)
{
    public DbSet<AppUser> AppUsers => Set<AppUser>();
    public DbSet<RefreshSession> RefreshSessions => Set<RefreshSession>();
    public DbSet<RawIntegrationEvent> RawIntegrationEvents => Set<RawIntegrationEvent>();
    public DbSet<OutboxMessage> OutboxMessages => Set<OutboxMessage>();
    public DbSet<AuditEntry> AuditEntries => Set<AuditEntry>();
    public DbSet<IntegrationCursor> IntegrationCursors => Set<IntegrationCursor>();
    public DbSet<MotorStateProjection> MotorStateProjections => Set<MotorStateProjection>();
    public DbSet<PlantStatePeriod> PlantStatePeriods => Set<PlantStatePeriod>();
    public DbSet<RunSchedule> RunSchedules => Set<RunSchedule>();
    public DbSet<QualityReading> QualityReadings => Set<QualityReading>();
    public DbSet<ProductionMassReading> ProductionMassReadings => Set<ProductionMassReading>();
    public DbSet<AttendanceEvent> AttendanceEvents => Set<AttendanceEvent>();
    public DbSet<AttendanceSession> AttendanceSessions => Set<AttendanceSession>();
    public DbSet<EmployeeProfile> EmployeeProfiles => Set<EmployeeProfile>();
    public DbSet<Announcement> Announcements => Set<Announcement>();
    public DbSet<AnnouncementRead> AnnouncementReads => Set<AnnouncementRead>();
    public DbSet<PushDevice> PushDevices => Set<PushDevice>();

    protected override void OnModelCreating(ModelBuilder model)
    {
        model.Entity<AppUser>(e =>
        {
            e.ToTable("app_users");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.NormalizedUserName).IsUnique();
            e.HasIndex(x => x.EmployeeCode).IsUnique();
            e.Property(x => x.Status).HasConversion<string>().HasMaxLength(20);
            e.Property(x => x.UserName).HasMaxLength(64);
            e.Property(x => x.NormalizedUserName).HasMaxLength(64);
            e.Property(x => x.DisplayName).HasMaxLength(120);
            e.Property(x => x.EmployeeCode).HasMaxLength(64);
            e.Property(x => x.Roles).HasMaxLength(256);
        });

        model.Entity<RefreshSession>(e =>
        {
            e.ToTable("refresh_sessions");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.TokenHash).IsUnique();
            e.HasIndex(x => new { x.UserId, x.TokenFamily });
            e.HasOne(x => x.User).WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        model.Entity<RawIntegrationEvent>(e =>
        {
            e.ToTable("raw_integration_events");
            e.HasKey(x => x.Id);
            e.HasIndex(x => new { x.SourceSystem, x.EventId }).IsUnique();
            e.HasIndex(x => new { x.SourceDeviceId, x.Sequence });
            e.Property(x => x.PayloadJson).HasColumnType("jsonb");
            e.Property(x => x.ProcessingState).HasConversion<string>().HasMaxLength(20);
        });

        model.Entity<OutboxMessage>(e =>
        {
            e.ToTable("outbox_messages");
            e.HasKey(x => x.Id);
            e.HasIndex(x => new { x.ProcessedAt, x.NextAttemptAt });
            e.HasIndex(x => new { x.Topic, x.MessageKey }).IsUnique();
            e.Property(x => x.PayloadJson).HasColumnType("jsonb");
        });

        model.Entity<AuditEntry>(e =>
        {
            e.ToTable("audit_entries");
            e.HasKey(x => x.Id);
            e.HasIndex(x => new { x.SubjectType, x.SubjectId, x.OccurredAt });
            e.Property(x => x.BeforeJson).HasColumnType("jsonb");
            e.Property(x => x.AfterJson).HasColumnType("jsonb");
        });

        model.Entity<IntegrationCursor>(e =>
        {
            e.ToTable("integration_cursors");
            e.HasKey(x => x.SourceSystem);
        });

        model.Entity<MotorStateProjection>(e =>
        {
            e.ToTable("motor_state_projections");
            e.HasKey(x => x.Position);
            e.HasIndex(x => x.SourceEventId).IsUnique();
        });

        model.Entity<PlantStatePeriod>(e =>
        {
            e.ToTable("plant_state_periods");
            e.HasKey(x => x.Id);
            e.HasIndex(x => new { x.StartedAt, x.EndedAt });
            e.Property(x => x.State).HasConversion<string>().HasMaxLength(20);
        });

        model.Entity<RunSchedule>(e =>
        {
            e.ToTable("run_schedules");
            e.HasKey(x => x.Id);
            e.HasIndex(x => new { x.Status, x.PlannedStartAt });
        });

        model.Entity<QualityReading>(e =>
        {
            e.ToTable("quality_readings");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.SourceEventId).IsUnique();
            e.HasIndex(x => x.ResultId).IsUnique();
            e.HasIndex(x => x.MeasuredAt);
            e.Property(x => x.Ph).HasPrecision(6, 3);
            e.Property(x => x.Whiteness).HasPrecision(7, 3);
            e.Property(x => x.Moisture).HasPrecision(7, 3);
            e.Property(x => x.Fineness).HasPrecision(12, 4);
            e.Property(x => x.Viscosity).HasPrecision(12, 4);
            e.Property(x => x.ExtraValue).HasPrecision(12, 4);
        });

        model.Entity<ProductionMassReading>(e =>
        {
            e.ToTable("production_mass_readings");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.SourceEventId).IsUnique();
            e.HasIndex(x => new { x.PeriodId, x.Basis, x.Kind });
            e.Property(x => x.Kind).HasConversion<string>().HasMaxLength(30);
            e.Property(x => x.Basis).HasConversion<string>().HasMaxLength(20);
            e.Property(x => x.MassKg).HasPrecision(18, 3);
        });

        model.Entity<AttendanceEvent>(e =>
        {
            e.ToTable("attendance_events");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.SourceEventId).IsUnique();
            e.HasIndex(x => new { x.EmployeeId, x.OccurredAt });
            e.Property(x => x.Kind).HasConversion<string>().HasMaxLength(10);
        });

        model.Entity<AttendanceSession>(e =>
        {
            e.ToTable("attendance_sessions");
            e.HasKey(x => x.Id);
            e.HasIndex(x => new { x.EmployeeId, x.EntryAt, x.ExitAt });
            e.Property(x => x.Status).HasConversion<string>().HasMaxLength(20);
        });

        model.Entity<EmployeeProfile>(e =>
        {
            e.ToTable("employee_profiles");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.EmployeeCode).IsUnique();
            e.HasIndex(x => x.UserId).IsUnique();
        });

        model.Entity<Announcement>(e =>
        {
            e.ToTable("announcements");
            e.HasKey(x => x.Id);
            e.HasIndex(x => new { x.PublishedAt, x.ExpiresAt });
            e.Property(x => x.Audience).HasConversion<string>().HasMaxLength(20);
        });

        model.Entity<AnnouncementRead>(e =>
        {
            e.ToTable("announcement_reads");
            e.HasKey(x => new { x.AnnouncementId, x.UserId });
        });

        model.Entity<PushDevice>(e =>
        {
            e.ToTable("push_devices");
            e.HasKey(x => x.Id);
            e.HasIndex(x => new { x.UserId, x.TokenHash }).IsUnique();
        });
    }
}
