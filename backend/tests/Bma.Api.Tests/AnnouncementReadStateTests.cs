using Bma.Modules;

namespace Bma.Api.Tests;

public sealed class AnnouncementReadStateTests
{
    [Fact]
    public void Missing_read_receipt_is_unread()
    {
        var announcementId = Guid.NewGuid();
        var reads = new Dictionary<Guid, DateTimeOffset>();

        Assert.Null(ApiEndpoints.AnnouncementReadAt(reads, announcementId));
    }

    [Fact]
    public void Existing_read_receipt_keeps_its_timestamp()
    {
        var announcementId = Guid.NewGuid();
        var readAt = new DateTimeOffset(2026, 9, 1, 9, 0, 0, TimeSpan.Zero);
        var reads = new Dictionary<Guid, DateTimeOffset>
        {
            [announcementId] = readAt
        };

        Assert.Equal(readAt, ApiEndpoints.AnnouncementReadAt(reads, announcementId));
    }
}
