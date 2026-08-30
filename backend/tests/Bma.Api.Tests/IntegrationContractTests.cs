using System.Text.Json;
using Bma.Authentication;
using Bma.Integration;

namespace Bma.Api.Tests;

public sealed class IntegrationContractTests
{
    [Fact]
    public void Payload_hash_is_lowercase_sha256_and_sensitive_to_content()
    {
        using var first = JsonDocument.Parse("{\"state\":\"ON\",\"position\":\"INPUT\"}");
        using var second = JsonDocument.Parse("{\"state\":\"OFF\",\"position\":\"INPUT\"}");
        var left = IntegrationIngestionService.ComputePayloadHash(first.RootElement);
        var right = IntegrationIngestionService.ComputePayloadHash(second.RootElement);
        Assert.Matches("^[a-f0-9]{64}$", left);
        Assert.NotEqual(left, right);
    }

    [Fact]
    public void Refresh_tokens_are_never_stored_as_plain_text()
    {
        const string token = "plain-refresh-token";
        var hash = AuthService.Hash(token);
        Assert.NotEqual(token, hash);
        Assert.Equal(64, hash.Length);
    }
}
