param(
    [Parameter(Mandatory = $true)][string]$MobileRoot,
    [string]$BrandRoot
)

$ErrorActionPreference = "Stop"

$resolvedMobileRoot = (Resolve-Path -LiteralPath $MobileRoot).Path
if ([string]::IsNullOrWhiteSpace($BrandRoot)) {
    $scriptsParent = Join-Path $PSScriptRoot ".."
    $repositoryRoot = (Resolve-Path (Join-Path $scriptsParent "..")).Path
    $BrandRoot = Join-Path $repositoryRoot "assets/brand/binh-minh/app-icon"
}
$resolvedBrandRoot = (Resolve-Path -LiteralPath $BrandRoot).Path
$appliedPlatforms = @()

$androidRoot = Join-Path $resolvedMobileRoot "android"
if (Test-Path -LiteralPath $androidRoot -PathType Container) {
    $androidSource = Join-Path $resolvedBrandRoot "platform/android/res"
    $androidTarget = Join-Path $androidRoot "app/src/main/res"
    if (!(Test-Path -LiteralPath $androidSource -PathType Container)) {
        throw "Android branding source was not found: $androidSource"
    }
    New-Item -ItemType Directory -Force -Path $androidTarget | Out-Null
    Get-ChildItem -LiteralPath $androidSource | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $androidTarget -Recurse -Force
    }
    $appliedPlatforms += "Android"
}

$iosRoot = Join-Path $resolvedMobileRoot "ios"
if (Test-Path -LiteralPath $iosRoot -PathType Container) {
    $iosSource = Join-Path $resolvedBrandRoot "platform/ios/AppIcon.appiconset"
    $iosParent = Join-Path $iosRoot "Runner/Assets.xcassets"
    $iosTarget = Join-Path $iosParent "AppIcon.appiconset"
    if (!(Test-Path -LiteralPath $iosSource -PathType Container)) {
        throw "iOS branding source was not found: $iosSource"
    }
    New-Item -ItemType Directory -Force -Path $iosParent | Out-Null
    if (Test-Path -LiteralPath $iosTarget) {
        Remove-Item -LiteralPath $iosTarget -Recurse -Force
    }
    Copy-Item -LiteralPath $iosSource -Destination $iosParent -Recurse -Force
    $appliedPlatforms += "iOS"
}

if ($appliedPlatforms.Count -eq 0) {
    throw "No Android or iOS platform shell exists under '$resolvedMobileRoot'."
}

[PSCustomObject]@{
    Brand = "Bình Minh BM7"
    MobileRoot = $resolvedMobileRoot
    Platforms = $appliedPlatforms -join ", "
    Result = "PASS"
} | Format-List
