namespace Bma.Authentication;

public sealed class JwtOptions
{
    public const string Section = "Jwt";
    public string Issuer { get; set; } = "BMA";
    public string Audience { get; set; } = "BMA.Mobile";
    public string SigningKey { get; set; } = "";
    public int AccessMinutes { get; set; } = 15;
    public int RefreshDays { get; set; } = 180;
}

public static class BmaAuthSchemes
{
    public const string Selector = "BmaAuth";
    public const string Cookie = "BmaCookie";
}
