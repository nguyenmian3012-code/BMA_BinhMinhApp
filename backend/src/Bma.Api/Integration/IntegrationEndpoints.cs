namespace Bma.Integration;

public static class IntegrationEndpoints
{
    public static IEndpointRouteBuilder MapBmaIntegration(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/api/v1/integrations/events", async (
            CanonicalEvent message,
            HttpContext http,
            IntegrationIngestionService ingestion,
            CancellationToken ct) =>
        {
            if (!ingestion.IsInboundKeyValid(http.Request.Headers["X-BMA-Gateway-Key"].FirstOrDefault()))
                return Results.Unauthorized();
            var idempotency = http.Request.Headers["Idempotency-Key"].FirstOrDefault();
            if (!string.IsNullOrWhiteSpace(idempotency) && idempotency != message.EventId)
                return Results.UnprocessableEntity(new { error = "IDEMPOTENCY_KEY_MISMATCH" });

            var result = await ingestion.IngestAsync(message, ct);
            return result.Status switch
            {
                IngestionStatus.Accepted => Results.Accepted(value: new
                    { status = "ACCEPTED", raw_event_id = result.RawEventId }),
                IngestionStatus.Duplicate => Results.Ok(new
                    { status = "DUPLICATE", raw_event_id = result.RawEventId }),
                _ => Results.UnprocessableEntity(new { error = result.Error })
            };
        }).AllowAnonymous().RequireRateLimiting("integration").WithTags("Integration");

        return endpoints;
    }
}
