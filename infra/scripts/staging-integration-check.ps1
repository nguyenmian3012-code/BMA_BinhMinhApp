param(
    [string]$BaseUrl = "https://gateway.abmtlab.com/bmapp-staging",
    [string]$EnvFile = ".env.staging",
    [string]$ProjectName = "bma-staging",
    [int]$ProjectionTimeoutSeconds = 30
)

$ErrorActionPreference = "Stop"

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    foreach ($rawLine in Get-Content -LiteralPath $Path) {
        $line = $rawLine.Trim()
        if (!$line -or $line.StartsWith("#")) { continue }
        $parts = $line -split "=", 2
        if ($parts.Count -ne 2 -or $parts[0].Trim() -ne $Name) { continue }
        $value = $parts[1].Trim()
        if ($value.Length -ge 2) {
            $quotedWithDouble = $value.StartsWith('"') -and $value.EndsWith('"')
            $quotedWithSingle = $value.StartsWith("'") -and $value.EndsWith("'")
            if ($quotedWithDouble -or $quotedWithSingle) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }
        return $value
    }
    return $null
}

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function New-MotorEvent {
    param(
        [Parameter(Mandatory = $true)][string]$EventId,
        [Parameter(Mandatory = $true)][string]$DeviceId,
        [Parameter(Mandatory = $true)][string]$MotorId,
        [Parameter(Mandatory = $true)][long]$Sequence,
        [Parameter(Mandatory = $true)][ValidateSet("ON", "OFF")][string]$State
    )

    $occurredAt = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
    $payload = [ordered]@{
        motor_id = $MotorId
        position = "INPUT"
        state = $State
        heartbeat_at = $occurredAt
        firmware_version = "staging-check"
    }
    $payloadJson = ConvertTo-Json -InputObject $payload -Depth 10 -Compress
    $message = [ordered]@{
        event_id = $EventId
        event_type = "MOTOR_STATE_CHANGED"
        source_system = "BMA_STAGING_CHECK"
        source_device_id = $DeviceId
        sequence = $Sequence
        occurred_at = $occurredAt
        schema_version = "1.0"
        correlation_id = $EventId
        payload = $payload
        payload_hash = Get-Sha256Hex -Text $payloadJson
        signature = $null
    }
    $messageJson = ConvertTo-Json -InputObject $message -Depth 10 -Compress
    return $messageJson
}

function Send-CanonicalEvent {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$GatewayKey,
        [Parameter(Mandatory = $true)][string]$EventId,
        [Parameter(Mandatory = $true)][string]$Body
    )

    $headers = @{
        "X-BMA-Gateway-Key" = $GatewayKey
        "Idempotency-Key" = $EventId
    }
    $response = Invoke-WebRequest -Uri $Url -Method Post -Headers $headers `
        -ContentType "application/json" -Body $Body -UseBasicParsing -TimeoutSec 20
    $content = $response.Content | ConvertFrom-Json
    return [PSCustomObject]@{
        HttpStatus = [int]$response.StatusCode
        Status = [string]$content.status
        RawEventId = [string]$content.raw_event_id
    }
}

function Invoke-PostgresScalar {
    param(
        [Parameter(Mandatory = $true)][string]$Sql,
        [Parameter(Mandatory = $true)][string]$ComposeEnvFile,
        [Parameter(Mandatory = $true)][string]$ComposeProject
    )

    # Pass SQL as sh positional parameter instead of an environment value. This keeps
    # quotes intact across PowerShell -> docker compose -> Alpine sh.
    $arguments = @(
        "compose",
        "--project-name", $ComposeProject,
        "--env-file", $ComposeEnvFile,
        "exec", "-T",
        "postgres", "sh", "-lc",
        'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -qAt -c "$1"',
        "bma-staging-check",
        $Sql
    )
    $output = @(& docker @arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "PostgreSQL verification failed: $($output -join [Environment]::NewLine)"
    }

    $nonEmptyLines = @(
        foreach ($item in $output) {
            if ($null -eq $item) { continue }
            $line = $item.ToString().Trim()
            if (![string]::IsNullOrWhiteSpace($line)) {
                $line
            }
        }
    )
    if ($nonEmptyLines.Count -eq 0) {
        throw "PostgreSQL verification returned no scalar value."
    }
    return $nonEmptyLines[-1]
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$resolvedEnvFile = if ([System.IO.Path]::IsPathRooted($EnvFile)) {
    $EnvFile
} else {
    Join-Path $repoRoot $EnvFile
}
if (!(Test-Path -LiteralPath $resolvedEnvFile -PathType Leaf)) {
    throw "Environment file not found: $resolvedEnvFile"
}

$gatewayKey = Get-DotEnvValue -Path $resolvedEnvFile -Name "BMA_GATEWAY_INBOUND_KEY"
if ([string]::IsNullOrWhiteSpace($gatewayKey) -or $gatewayKey -like "*CHANGE_ME*") {
    throw "BMA_GATEWAY_INBOUND_KEY is missing or still uses a placeholder."
}

$runId = [DateTime]::UtcNow.ToString("yyyyMMddHHmmss") + "-" + [Guid]::NewGuid().ToString("N").Substring(0, 8)
$deviceId = "BMA-STAGING-M1P-INPUT-$runId"
$motorId = "BM-STAGING-INPUT-$runId"
$eventOneId = "bma-staging-$runId-seq-1"
$eventGapId = "bma-staging-$runId-seq-3"
$endpoint = $BaseUrl.TrimEnd("/") + "/api/v1/integrations/events"

Push-Location $repoRoot
try {
    Write-Host "Checkpoint: canonical ingest -> idempotency -> outbox -> projection -> audit"
    Write-Host "Test device: $deviceId"

    $eventOneJson = New-MotorEvent -EventId $eventOneId -DeviceId $deviceId `
        -MotorId $motorId -Sequence 1 -State "ON"
    $accepted = Send-CanonicalEvent -Url $endpoint -GatewayKey $gatewayKey `
        -EventId $eventOneId -Body $eventOneJson
    if ($accepted.HttpStatus -ne 202 -or $accepted.Status -ne "ACCEPTED") {
        throw "First delivery was not accepted: HTTP $($accepted.HttpStatus), status $($accepted.Status)"
    }

    $duplicate = Send-CanonicalEvent -Url $endpoint -GatewayKey $gatewayKey `
        -EventId $eventOneId -Body $eventOneJson
    if ($duplicate.HttpStatus -ne 200 -or $duplicate.Status -ne "DUPLICATE") {
        throw "Duplicate delivery was not detected: HTTP $($duplicate.HttpStatus), status $($duplicate.Status)"
    }
    if ($duplicate.RawEventId -ne $accepted.RawEventId) {
        throw "Duplicate delivery returned a different raw_event_id."
    }

    Start-Sleep -Milliseconds 1100
    $eventGapJson = New-MotorEvent -EventId $eventGapId -DeviceId $deviceId `
        -MotorId $motorId -Sequence 3 -State "OFF"
    $gapAccepted = Send-CanonicalEvent -Url $endpoint -GatewayKey $gatewayKey `
        -EventId $eventGapId -Body $eventGapJson
    if ($gapAccepted.HttpStatus -ne 202 -or $gapAccepted.Status -ne "ACCEPTED") {
        throw "Sequence-gap event was not accepted: HTTP $($gapAccepted.HttpStatus), status $($gapAccepted.Status)"
    }

    $quotedOne = $eventOneId.Replace("'", "''")
    $quotedGap = $eventGapId.Replace("'", "''")
    $quotedDevice = $deviceId.Replace("'", "''")
    $deadline = [DateTime]::UtcNow.AddSeconds($ProjectionTimeoutSeconds)
    do {
        $rawProjected = [int](Invoke-PostgresScalar -ComposeEnvFile $resolvedEnvFile `
            -ComposeProject $ProjectName -Sql "SELECT count(*) FROM raw_integration_events WHERE event_id IN ('$quotedOne','$quotedGap') AND processing_state = 'Projected' AND processing_error IS NULL;")
        $outboxProcessed = [int](Invoke-PostgresScalar -ComposeEnvFile $resolvedEnvFile `
            -ComposeProject $ProjectName -Sql "SELECT count(*) FROM outbox_messages o JOIN raw_integration_events r ON o.message_key = r.id::text WHERE r.event_id IN ('$quotedOne','$quotedGap') AND o.processed_at IS NOT NULL AND o.last_error IS NULL;")
        $projectionUpdated = [int](Invoke-PostgresScalar -ComposeEnvFile $resolvedEnvFile `
            -ComposeProject $ProjectName -Sql "SELECT count(*) FROM motor_state_projections WHERE position = 'INPUT' AND source_event_id = '$quotedGap' AND is_on = false;")
        $gapAudited = [int](Invoke-PostgresScalar -ComposeEnvFile $resolvedEnvFile `
            -ComposeProject $ProjectName -Sql "SELECT count(*) FROM audit_entries WHERE action = 'INTEGRATION_SEQUENCE_GAP' AND subject_id = '$quotedDevice';")
        if ($rawProjected -eq 2 -and $outboxProcessed -eq 2 -and `
            $projectionUpdated -eq 1 -and $gapAudited -ge 1) { break }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)

    if ($rawProjected -ne 2) { throw "Expected 2 projected raw events; found $rawProjected." }
    if ($outboxProcessed -ne 2) { throw "Expected 2 processed outbox messages; found $outboxProcessed." }
    if ($projectionUpdated -ne 1) { throw "Motor projection did not advance to the sequence-3 OFF event." }
    if ($gapAudited -lt 1) { throw "Sequence gap was not recorded in audit_entries." }

    [PSCustomObject]@{
        FirstDelivery = "202 ACCEPTED"
        DuplicateDelivery = "200 DUPLICATE"
        RawEventsProjected = $rawProjected
        OutboxMessagesProcessed = $outboxProcessed
        InputProjection = "OFF @ sequence 3"
        SequenceGapAuditEntries = $gapAudited
        Result = "PASS"
    } | Format-List
}
finally {
    $gatewayKey = $null
    Pop-Location
}
