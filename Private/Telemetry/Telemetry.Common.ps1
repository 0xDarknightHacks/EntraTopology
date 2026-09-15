function New-EntraTopologyTelemetry {
    [CmdletBinding()] param()
    [pscustomobject][ordered]@{
        RunId = [guid]::NewGuid().Guid
        StartedAtUtc = [datetime]::UtcNow.ToString('o')
        CompletedAtUtc = $null
        DurationMs = 0L
        GraphLogicalRequests = 0L
        GraphHttpRequests = 0L
        Retries = 0L
        Throttles = 0L
        BatchingEfficiency = 0.0
        Stages = [ordered]@{}
    }
}

function Get-EntraTopologyTelemetryElapsedMilliseconds {
    param(
        [Parameter(Mandatory)][string]$StartedAtUtc,
        [Parameter(Mandatory)][datetime]$CompletedUtc
    )
    $started = [datetimeoffset]::Parse($StartedAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)
    $completed = [datetimeoffset]::new($CompletedUtc)
    [long][math]::Max(0, [math]::Round(($completed - $started).TotalMilliseconds))
}

function Add-EntraTopologyTelemetryRequest {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][object]$Telemetry,
        [int]$Logical=1,
        [int]$Http=1,
        [int]$Retries=0,
        [int]$Throttles=0
    )
    $Telemetry.GraphLogicalRequests += $Logical
    $Telemetry.GraphHttpRequests += $Http
    $Telemetry.Retries += $Retries
    $Telemetry.Throttles += $Throttles
}

function Start-EntraTopologyTelemetryStage {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][object]$Telemetry,
        [Parameter(Mandatory)][string]$Name
    )
    $Telemetry.Stages[$Name]=[pscustomobject][ordered]@{
        Name=$Name
        StartedAtUtc=[datetime]::UtcNow.ToString('o')
        CompletedAtUtc=$null
        DurationMs=0L
        Status='Running'
        Message=$null
    }
    $Telemetry.Stages[$Name]
}

function Stop-EntraTopologyTelemetryStage {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][object]$Telemetry,
        [Parameter(Mandatory)][string]$Name,
        [ValidateSet('Success','Partial','Failed','Skipped')][string]$Status='Success',
        [AllowNull()][string]$Message
    )
    if(-not $Telemetry.Stages.Contains($Name)){ Start-EntraTopologyTelemetryStage -Telemetry $Telemetry -Name $Name | Out-Null }
    $stage=$Telemetry.Stages[$Name]
    $completed=[datetime]::UtcNow
    $stage.CompletedAtUtc=$completed.ToString('o')
    $stage.DurationMs=Get-EntraTopologyTelemetryElapsedMilliseconds -StartedAtUtc $stage.StartedAtUtc -CompletedUtc $completed
    $stage.Status=$Status
    $stage.Message=$Message
    $stage
}

function Complete-EntraTopologyTelemetry {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Telemetry)
    $completed=[datetime]::UtcNow
    $Telemetry.CompletedAtUtc=$completed.ToString('o')
    $Telemetry.DurationMs=Get-EntraTopologyTelemetryElapsedMilliseconds -StartedAtUtc $Telemetry.StartedAtUtc -CompletedUtc $completed
    $Telemetry.BatchingEfficiency=if([long]$Telemetry.GraphHttpRequests -gt 0){[math]::Round(([double]$Telemetry.GraphLogicalRequests/[double]$Telemetry.GraphHttpRequests),2)}else{0.0}
    $Telemetry
}
