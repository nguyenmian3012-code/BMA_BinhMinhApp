using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Bma.Data;

public sealed class BmaDbContextFactory : IDesignTimeDbContextFactory<BmaDbContext>
{
    public BmaDbContext CreateDbContext(string[] args)
    {
        var connection = Environment.GetEnvironmentVariable("ConnectionStrings__Bma")
            ?? "Host=localhost;Database=bma_dev;Username=bma_app";
        var options = new DbContextOptionsBuilder<BmaDbContext>()
            .UseNpgsql(connection)
            .UseSnakeCaseNamingConvention()
            .Options;
        return new BmaDbContext(options);
    }
}
