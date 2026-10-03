using Bma.Domain;

namespace Bma.Api.Tests;

public sealed class EmployeeCodeRulesTests
{
    [Theory]
    [InlineData("BM001")]
    [InlineData("BM999")]
    public void Official_employee_codes_are_accepted(string value)
    {
        Assert.True(EmployeeCodeRules.IsValid(value));
    }

    [Theory]
    [InlineData("BM01")]
    [InlineData("BM0001")]
    [InlineData("BM-001")]
    [InlineData("bm001")]
    public void Non_standard_employee_codes_are_rejected(string value)
    {
        Assert.False(EmployeeCodeRules.IsValid(value));
    }
}
