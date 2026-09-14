using System.Security.Cryptography;
using System.Text.Json;

namespace Bma.Modules;

public sealed class EtagJsonResult(object value, TimeSpan maxAge) : IResult
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
    };

    public async Task ExecuteAsync(HttpContext httpContext)
    {
        var bytes = JsonSerializer.SerializeToUtf8Bytes(value, JsonOptions);
        var etag = $"\"{Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant()}\"";
        httpContext.Response.Headers["ETag"] = etag;
        httpContext.Response.Headers["Cache-Control"] = $"private,max-age={(int)maxAge.TotalSeconds},must-revalidate";
        if (httpContext.Request.Headers["If-None-Match"].Any(x =>
                x?.Split(',', StringSplitOptions.TrimEntries).Contains(etag) == true))
        {
            httpContext.Response.StatusCode = StatusCodes.Status304NotModified;
            return;
        }
        httpContext.Response.ContentType = "application/json; charset=utf-8";
        httpContext.Response.ContentLength = bytes.Length;
        await httpContext.Response.Body.WriteAsync(bytes, httpContext.RequestAborted);
    }
}

public static class EtagResults
{
    public static IResult Json(object value, int maxAgeSeconds = 15) =>
        new EtagJsonResult(value, TimeSpan.FromSeconds(maxAgeSeconds));
}
