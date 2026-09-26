using System.Text.Json;
using Bma.Data;
using Bma.Domain;

namespace Bma.Modules;

public sealed class AuditWriter(BmaDbContext db, IHttpContextAccessor http)
{
    public void Add(
        string action,
        string subjectType,
        string subjectId,
        Guid? actorUserId = null,
        object? before = null,
        object? after = null,
        string? correlationId = null)
    {
        db.AuditEntries.Add(new AuditEntry
        {
            ActorUserId = actorUserId,
            Action = action,
            SubjectType = subjectType,
            SubjectId = subjectId,
            CorrelationId = correlationId,
            BeforeJson = before is null ? null : JsonSerializer.Serialize(before),
            AfterJson = after is null ? null : JsonSerializer.Serialize(after),
            IpAddress = http.HttpContext?.Connection.RemoteIpAddress?.ToString()
        });
    }
}
