param(
    [string]$BaseUrl = "https://gateway.redtigerhead.com/bmapp-staging",
    [string]$EnvFile = ".env.staging",
    [string]$PostgresBin = "C:\Program Files\PostgreSQL\17\bin",
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

function New-QualityEvent {
    param(
        [Parameter(Mandatory = $true)][string]$EventId,
        [Parameter(Mandatory = $true)][string]$ResultId
    )

    $occurredAt = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
    $payload = [ordered]@{
        result_id = $ResultId
        lot_code = "SYNTHETIC-NOT-FOR-PRODUCTION"
        measured_at = $occurredAt
        ph = 5.8
        whiteness = 93.4
        moisture = 12.4
        fineness = $null
        fineness_unit = $null
        viscosity = 18.6
        viscosity_unit = $null
        extra_value = $null
        product_code = "SYNTHETIC"
        operator_code = "CI"
        quality_code = "TEST"
        customer_code = "INTERNAL"
    }
    $payloadJson = ConvertTo-Json -InputObject $payload -Depth 10 -Compress
    $message = [ordered]@{
        event_id = $EventId
        event_type = "QUALITY_RESULT_PUBLISHED"
        source_system = "BMKCS"
        source_device_id = "BMKCSLAB-SYNTHETIC"
        sequence = $null
        occurred_at = $occurredAt
        schema_version = "1.0"
        correlation_id = $EventId
        payload = $payload
        payload_hash = Get-Sha256Hex -Text $payloadJson
        signature = $null
    }
    return ConvertTo-Json -InputObject $message -Depth 10 -Compress
}

function New-EmployeeScanEvent {
    param(
        [Parameter(Mandatory = $true)][string]$EventId,
        [Parameter(Mandatory = $true)][string]$EmployeeId,
        [Parameter(Mandatory = $true)][long]$Sequence,
        [Parameter(Mandatory = $true)][DateTimeOffset]$OccurredAt
    )

    $payload = [ordered]@{
        employee_id = $EmployeeId
        evidence_ref = "bma-staging://synthetic/$EventId"
        verification_method = "SYNTHETIC"
        confidence = 1
    }
    $payloadJson = ConvertTo-Json -InputObject $payload -Depth 10 -Compress
    $message = [ordered]@{
        event_id = $EventId
        event_type = "EMPLOYEE_SCAN"
        source_system = "FACE_TERMINAL"
        source_device_id = "BMA-STAGING-FACE"
        sequence = $Sequence
        occurred_at = $OccurredAt.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
        schema_version = "1.0"
        correlation_id = "attendance-$EmployeeId"
        payload = $payload
        payload_hash = Get-Sha256Hex -Text $payloadJson
        signature = $null
    }
    return ConvertTo-Json -InputObject $message -Depth 10 -Compress
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
        [Parameter(Mandatory = $true)][string]$DatabaseHost,
        [Parameter(Mandatory = $true)][string]$DatabasePort,
        [Parameter(Mandatory = $true)][string]$DatabaseName,
        [Parameter(Mandatory = $true)][string]$DatabaseUser,
        [Parameter(Mandatory = $true)][string]$DatabasePassword,
        [Parameter(Mandatory = $true)][string]$PsqlPath
    )

    $previousPassword = $env:PGPASSWORD
    try {
        $env:PGPASSWORD = $DatabasePassword
        $output = @($Sql | & $PsqlPath -X -v ON_ERROR_STOP=1 `
            --host $DatabaseHost --port $DatabasePort --username $DatabaseUser `
            --dbname $DatabaseName --quiet --tuples-only --no-align 2>&1)
        $postgresExitCode = $LASTEXITCODE
        if ($postgresExitCode -ne 0) {
            throw "PostgreSQL verification failed (exit $postgresExitCode): $($output -join [Environment]::NewLine)"
        }
    }
    finally {
        $env:PGPASSWORD = $previousPassword
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
$databaseHost = Get-DotEnvValue -Path $resolvedEnvFile -Name "BMA_DB_HOST"
if (!$databaseHost) { $databaseHost = "127.0.0.1" }
$databasePort = Get-DotEnvValue -Path $resolvedEnvFile -Name "BMA_DB_PORT"
if (!$databasePort) { $databasePort = "5432" }
$databaseName = Get-DotEnvValue -Path $resolvedEnvFile -Name "BMA_DB_NAME"
if (!$databaseName) { $databaseName = "binhminh_data_staging" }
$databaseUser = Get-DotEnvValue -Path $resolvedEnvFile -Name "BMA_DB_USER"
if (!$databaseUser) { $databaseUser = "bma_staging_runtime" }
$databasePassword = Get-DotEnvValue -Path $resolvedEnvFile -Name "BMA_DB_PASSWORD"
if (!$databasePassword) {
    $databasePassword = Get-DotEnvValue -Path $resolvedEnvFile -Name "POSTGRES_PASSWORD"
}
if (!$databasePassword -or $databasePassword -like "*CHANGE_ME*") {
    throw "BMA_DB_PASSWORD is missing or still uses a placeholder."
}
if ($databaseName -eq "binhminh_data") {
    throw "Safety stop: synthetic tests cannot use production database binhminh_data."
}
$psqlPath = Join-Path $PostgresBin "psql.exe"
if (!(Test-Path $psqlPath -PathType Leaf)) {
    $psqlCommand = Get-Command psql.exe -ErrorAction SilentlyContinue
    if (!$psqlCommand) { throw "psql.exe not found: $psqlPath" }
    $psqlPath = $psqlCommand.Source
}
$databaseArguments = @{
    DatabaseHost = $databaseHost
    DatabasePort = $databasePort
    DatabaseName = $databaseName
    DatabaseUser = $databaseUser
    DatabasePassword = $databasePassword
    PsqlPath = $psqlPath
}

$runId = [DateTime]::UtcNow.ToString("yyyyMMddHHmmss") + "-" + [Guid]::NewGuid().ToString("N").Substring(0, 8)
$deviceId = "BMA-STAGING-M1P-INPUT-$runId"
$motorId = "BM-STAGING-INPUT-$runId"
$eventOneId = "bma-staging-$runId-seq-1"
$eventGapId = "bma-staging-$runId-seq-3"
$qualityEventId = "bmkcs-staging-$runId"
$qualityResultId = "SYNTHETIC-$runId"
$employeeId = "BMA-SYNTHETIC-$runId"
$scanEntryId = "employee-scan-entry-$runId"
$scanExitId = "employee-scan-exit-$runId"
$endpoint = $BaseUrl.TrimEnd("/") + "/api/v1/integrations/events"

Push-Location $repoRoot
try {
    Write-Host "Checkpoint: canonical ingest -> idempotency -> outbox -> projection -> audit"
    Write-Host "Test device: $deviceId"

    # Verify the local database command path before writing synthetic events. A
    # command-transport failure must not leave another partial checkpoint run.
    $databaseProbe = [int](Invoke-PostgresScalar @databaseArguments -Sql "SELECT 1;")
    if ($databaseProbe -ne 1) {
        throw "PostgreSQL scalar preflight returned '$databaseProbe' instead of 1."
    }
    Write-Host "PostgreSQL scalar preflight: PASS"

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

    $qualityJson = New-QualityEvent -EventId $qualityEventId -ResultId $qualityResultId
    $qualityAccepted = Send-CanonicalEvent -Url $endpoint -GatewayKey $gatewayKey `
        -EventId $qualityEventId -Body $qualityJson
    if ($qualityAccepted.HttpStatus -ne 202 -or $qualityAccepted.Status -ne "ACCEPTED") {
        throw "Synthetic BMKCS result was not accepted: HTTP $($qualityAccepted.HttpStatus), status $($qualityAccepted.Status)"
    }

    $vietnamOffset = [TimeSpan]::FromHours(7)
    $workDate = [DateTimeOffset]::UtcNow.ToOffset($vietnamOffset).Date.AddDays(-1)
    while ($workDate.DayOfWeek -eq [DayOfWeek]::Sunday) { $workDate = $workDate.AddDays(-1) }
    $entryAt = [DateTimeOffset]::new($workDate.AddHours(7), $vietnamOffset)
    $exitAt = [DateTimeOffset]::new($workDate.AddHours(17), $vietnamOffset)
    $entryJson = New-EmployeeScanEvent -EventId $scanEntryId -EmployeeId $employeeId `
        -Sequence 101 -OccurredAt $entryAt
    $entryAccepted = Send-CanonicalEvent -Url $endpoint -GatewayKey $gatewayKey `
        -EventId $scanEntryId -Body $entryJson
    $entryDuplicate = Send-CanonicalEvent -Url $endpoint -GatewayKey $gatewayKey `
        -EventId $scanEntryId -Body $entryJson
    $exitJson = New-EmployeeScanEvent -EventId $scanExitId -EmployeeId $employeeId `
        -Sequence 102 -OccurredAt $exitAt
    $exitAccepted = Send-CanonicalEvent -Url $endpoint -GatewayKey $gatewayKey `
        -EventId $scanExitId -Body $exitJson
    if ($entryAccepted.Status -ne "ACCEPTED" -or $entryDuplicate.Status -ne "DUPLICATE" -or
        $exitAccepted.Status -ne "ACCEPTED") {
        throw "Synthetic EMPLOYEE_SCAN events were not accepted."
    }

    $quotedOne = $eventOneId.Replace("'", "''")
    $quotedGap = $eventGapId.Replace("'", "''")
    $quotedQuality = $qualityEventId.Replace("'", "''")
    $quotedResult = $qualityResultId.Replace("'", "''")
    $quotedDevice = $deviceId.Replace("'", "''")
    $quotedEntry = $scanEntryId.Replace("'", "''")
    $quotedExit = $scanExitId.Replace("'", "''")
    $quotedEmployee = $employeeId.Replace("'", "''")
    $deadline = [DateTime]::UtcNow.AddSeconds($ProjectionTimeoutSeconds)
    do {
        $rawProjected = [int](Invoke-PostgresScalar @databaseArguments -Sql "SELECT count(*) FROM raw_integration_events WHERE event_id IN ('$quotedOne','$quotedGap','$quotedQuality','$quotedEntry','$quotedExit') AND processing_state = 'Projected' AND processing_error IS NULL;")
        $outboxProcessed = [int](Invoke-PostgresScalar @databaseArguments -Sql "SELECT count(*) FROM outbox_messages o JOIN raw_integration_events r ON o.message_key = r.id::text WHERE r.event_id IN ('$quotedOne','$quotedGap','$quotedQuality','$quotedEntry','$quotedExit') AND o.processed_at IS NOT NULL AND o.last_error IS NULL;")
        $projectionUpdated = [int](Invoke-PostgresScalar @databaseArguments -Sql "SELECT count(*) FROM motor_state_projections WHERE position = 'INPUT' AND source_event_id = '$quotedGap' AND is_on = false;")
        $gapAudited = [int](Invoke-PostgresScalar @databaseArguments -Sql "SELECT count(*) FROM audit_entries WHERE action = 'INTEGRATION_SEQUENCE_GAP' AND subject_id = '$quotedDevice';")
        $qualityProjected = [int](Invoke-PostgresScalar @databaseArguments -Sql "SELECT count(*) FROM quality_readings WHERE result_id = '$quotedResult' AND source_event_id = '$quotedQuality';")
        $attendanceProjected = [int](Invoke-PostgresScalar @databaseArguments -Sql "SELECT count(*) FROM attendance_events WHERE employee_id = '$quotedEmployee' AND source_event_id IN ('$quotedEntry','$quotedExit');")
        $attendanceConfirmed = [int](Invoke-PostgresScalar @databaseArguments -Sql "SELECT count(*) FROM attendance_sessions WHERE employee_id = '$quotedEmployee' AND entry_event_id = '$quotedEntry' AND exit_event_id = '$quotedExit' AND status = 'Confirmed' AND credited_minutes = 480;")
        if ($rawProjected -eq 5 -and $outboxProcessed -eq 5 -and `
            $projectionUpdated -eq 1 -and $gapAudited -ge 1 -and `
            $qualityProjected -eq 1 -and $attendanceProjected -eq 2 -and `
            $attendanceConfirmed -eq 1) { break }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)

    if ($rawProjected -ne 5) { throw "Expected 5 projected raw events; found $rawProjected." }
    if ($outboxProcessed -ne 5) { throw "Expected 5 processed outbox messages; found $outboxProcessed." }
    if ($projectionUpdated -ne 1) { throw "Motor projection did not advance to the sequence-3 OFF event." }
    if ($gapAudited -lt 1) { throw "Sequence gap was not recorded in audit_entries." }
    if ($qualityProjected -ne 1) { throw "Synthetic BMKCS result was not projected." }
    if ($attendanceProjected -ne 2 -or $attendanceConfirmed -ne 1) {
        throw "Synthetic EMPLOYEE_SCAN did not produce one confirmed 480-minute session."
    }

    [PSCustomObject]@{
        FirstDelivery = "202 ACCEPTED"
        DuplicateDelivery = "200 DUPLICATE"
        RawEventsProjected = $rawProjected
        OutboxMessagesProcessed = $outboxProcessed
        InputProjection = "OFF @ sequence 3"
        SequenceGapAuditEntries = $gapAudited
        BmkcsSyntheticResult = $qualityResultId
        QualityProjection = "PASS"
        EmployeeScan = "$employeeId -> ENTRY + EXIT"
        EmployeeScanDuplicate = "PASS"
        AttendanceSession = "CONFIRMED / 480 minutes"
        Result = "PASS"
    } | Format-List
}
finally {
    $gatewayKey = $null
    $databasePassword = $null
    $databaseArguments.DatabasePassword = $null
    Pop-Location
}
