param(
    [Parameter(Mandatory = $true)][string]$ArtifactPath,
    [string]$PackageId = "com.binhminh.bma"
)

$ErrorActionPreference = "Stop"
$temporaryDirectory = $null

function Get-OnlyApk {
    param([Parameter(Mandatory = $true)][string]$SearchRoot)

    $candidates = @(Get-ChildItem -LiteralPath $SearchRoot -Filter *.apk -File -Recurse)
    if ($candidates.Count -ne 1) {
        throw "Expected exactly one APK under '$SearchRoot'; found $($candidates.Count)."
    }
    return $candidates[0]
}

try {
    $resolvedArtifact = (Resolve-Path -LiteralPath $ArtifactPath).Path
    $artifactItem = Get-Item -LiteralPath $resolvedArtifact

    if ($artifactItem.PSIsContainer) {
        $searchRoot = $artifactItem.FullName
        $apk = Get-OnlyApk -SearchRoot $searchRoot
    }
    elseif ($artifactItem.Extension -ieq ".zip") {
        $temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) (
            "bma-alpha-" + [Guid]::NewGuid().ToString("N")
        )
        New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
        Expand-Archive -LiteralPath $artifactItem.FullName -DestinationPath $temporaryDirectory
        $searchRoot = $temporaryDirectory
        $apk = Get-OnlyApk -SearchRoot $searchRoot
    }
    elseif ($artifactItem.Extension -ieq ".apk") {
        $searchRoot = $artifactItem.DirectoryName
        $apk = $artifactItem
    }
    else {
        throw "ArtifactPath must be an Android Alpha ZIP, APK or extracted directory."
    }

    $checksumFiles = @(
        Get-ChildItem -LiteralPath $searchRoot -Filter SHA256SUMS.txt -File -Recurse
    )
    if ($checksumFiles.Count -ne 1) {
        throw "Expected exactly one SHA256SUMS.txt beside the Alpha artifact."
    }

    $expectedHash = $null
    foreach ($line in Get-Content -LiteralPath $checksumFiles[0].FullName) {
        if ($line -notmatch '^\s*([0-9a-fA-F]{64})\s+\*?(.+?)\s*$') { continue }
        if ([System.IO.Path]::GetFileName($Matches[2]) -eq $apk.Name) {
            $expectedHash = $Matches[1].ToLowerInvariant()
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($expectedHash)) {
        throw "SHA256SUMS.txt does not contain an entry for '$($apk.Name)'."
    }

    $actualHash = (Get-FileHash -LiteralPath $apk.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "APK checksum mismatch. Expected $expectedHash; found $actualHash."
    }
    Write-Host "APK checksum: PASS ($actualHash)"

    $adbCommand = Get-Command adb -ErrorAction SilentlyContinue
    if ($null -eq $adbCommand) {
        throw "adb was not found. Install Android SDK Platform-Tools or add it to PATH."
    }

    $deviceOutput = @(& $adbCommand.Source devices 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "adb devices failed: $($deviceOutput -join [Environment]::NewLine)"
    }
    $readySerials = @(
        $deviceOutput |
            Where-Object { $_ -match '^\S+\s+device$' } |
            ForEach-Object { ($_ -split '\s+')[0] }
    )
    if ($readySerials.Count -ne 1) {
        $visible = @(
            $deviceOutput |
                Where-Object { $_ -match '^\S+\s+(device|unauthorized|offline)$' }
        )
        throw "Expected exactly one authorized Android device; found $($readySerials.Count). adb: $($visible -join '; ')"
    }
    $serial = $readySerials[0]
    Write-Host "Android device: $serial"

    $installOutput = @(& $adbCommand.Source -s $serial install -r $apk.FullName 2>&1)
    $installExitCode = $LASTEXITCODE
    if ($installExitCode -ne 0 -or !($installOutput -match '^Success$')) {
        throw @"
APK installation failed (exit $installExitCode):
$($installOutput -join [Environment]::NewLine)

If adb reports INSTALL_FAILED_UPDATE_INCOMPATIBLE, an older Alpha was signed
with a different temporary key. Uninstall it manually only after confirming
that losing its local Alpha session/cache is acceptable:
adb -s $serial uninstall $PackageId
"@
    }

    $packageOutput = @(& $adbCommand.Source -s $serial shell pm path $PackageId 2>&1)
    if ($LASTEXITCODE -ne 0 -or !($packageOutput -match '^package:')) {
        throw "Installed package '$PackageId' could not be verified: $($packageOutput -join [Environment]::NewLine)"
    }

    $launchOutput = @(
        & $adbCommand.Source -s $serial shell monkey -p $PackageId -c android.intent.category.LAUNCHER 1 2>&1
    )
    if ($LASTEXITCODE -ne 0 -or $launchOutput -match 'No activities found') {
        throw "BMA could not be launched: $($launchOutput -join [Environment]::NewLine)"
    }

    [PSCustomObject]@{
        DeviceSerial = $serial
        PackageId = $PackageId
        Apk = $apk.Name
        Sha256 = $actualHash
        Install = "PASS"
        Launch = "PASS"
        Result = "PASS"
    } | Format-List
}
finally {
    if ($null -ne $temporaryDirectory -and (Test-Path -LiteralPath $temporaryDirectory)) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
