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


function New-EntraTopologyDiagnostics {
    [CmdletBinding()] param()
    ,[System.Collections.Generic.List[object]]::new()
}

function Add-EntraTopologyDiagnosticEvent {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][System.Collections.IList]$Diagnostics,
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string]$Event,
        [ValidateSet('Info','Warning','Error')][string]$Level='Info',
        [Parameter(Mandatory)][string]$Message,
        [AllowNull()][hashtable]$Data
    )
    $record=[pscustomobject][ordered]@{
        TimestampUtc=[datetime]::UtcNow.ToString('o')
        Stage=$Stage
        Event=$Event
        Level=$Level
        Message=$Message
        Data=$(if($Data){$Data}else{@{}})
    }
    [void]$Diagnostics.Add($record)
    $record
}

function Save-EntraTopologyDiagnostics {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][System.Collections.IEnumerable]$Diagnostics,
        [Parameter(Mandatory)][string]$Path
    )
    $parent=Split-Path -Parent $Path
    if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
    $lines=@($Diagnostics|ForEach-Object{$_|ConvertTo-Json -Depth 20 -Compress})
    Set-Content -LiteralPath $Path -Value $lines -Encoding utf8
    Get-Item -LiteralPath $Path
}


function Write-EntraTopologyBanner {
    [CmdletBinding()] param()
    $banner=@'
┌──────────────────────────────────────────────────────┐
│░█▀▀░█▀█░▀█▀░█▀▄░█▀█░░░▀█▀░█▀█░█▀█░█▀█░█░░░█▀█░█▀▀░█░█│
│░█▀▀░█░█░░█░░█▀▄░█▀█░░░░█░░█░█░█▀▀░█░█░█░░░█░█░█░█░░█░│
│░▀▀▀░▀░▀░░▀░░▀░▀░▀░▀░░░░▀░░▀▀▀░▀░░░▀▀▀░▀▀▀░▀▀▀░▀▀▀░░▀░│
└──────────────────────────────────────────────────────┘
'@
    try { Write-Host $banner -ForegroundColor Cyan } catch { Write-Host $banner }
    Write-Host '  Read-only Microsoft Entra inventory, topology, and security context' -ForegroundColor DarkGray
    Write-Host ''
}

function Write-EntraTopologyStage {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][int]$Step,
        [Parameter(Mandatory)][int]$Total,
        [Parameter(Mandatory)][string]$Message,
        [switch]$NoProgress
    )
    $text="[$Step/$Total] $Message"
    if(-not $NoProgress){Write-Progress -Activity 'EntraTopology' -Status $text -PercentComplete ([math]::Min(100,[math]::Round(($Step/$Total)*100)))}
    Write-Information $text -InformationAction Continue
}

function Write-EntraTopologyCompletion {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Result)
    Write-Host ''
    Write-Host '[+] EntraTopology run completed' -ForegroundColor Green
    Write-Host ("    Tenant        : {0}" -f $Result.TenantId) -ForegroundColor DarkGray
    Write-Host ("    Inventory     : {0} objects | {1} relationships" -f $Result.NodeCount,$Result.EdgeCount) -ForegroundColor DarkGray
    Write-Host ("    Security      : {0} signals | {1} recommendations" -f $Result.SignalCount,$Result.RecommendationCount) -ForegroundColor DarkGray
    Write-Host ("    Graph         : {0} logical | {1} HTTP | {2}x batching | {3} retries" -f $Result.GraphLogicalRequests,$Result.GraphHttpRequests,$Result.BatchingEfficiency,$Result.Retries) -ForegroundColor DarkGray
    Write-Host ("    Runtime       : {0:n2}s" -f ($Result.DurationMs/1000.0)) -ForegroundColor DarkGray
    Write-Host ("    Output        : {0}" -f $Result.OutputDirectory) -ForegroundColor DarkGray
    if($Result.ReportPath){Write-Host ("    Report        : {0}" -f $Result.ReportPath) -ForegroundColor DarkGray}
    Write-Host ''
}


function Get-EntraTopologyStableId {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$InputString)
    $sha=[System.Security.Cryptography.SHA256]::Create(); try{$bytes=[Text.Encoding]::UTF8.GetBytes($InputString);$hash=$sha.ComputeHash($bytes);([BitConverter]::ToString($hash)-replace'-','').ToLowerInvariant().Substring(0,24)}finally{$sha.Dispose()}
}
function New-EntraTopologyNode {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$TenantId,[Parameter(Mandatory)][string]$ObjectId,[Parameter(Mandatory)][string]$Kind,[string]$DisplayName,[hashtable]$Properties=@{},[string[]]$EvidenceKeys=@())
    [pscustomobject][ordered]@{SchemaVersion='1.1.0';Key="tenant:${TenantId}:object:${ObjectId}";Id=$ObjectId;TenantId=$TenantId;Kind=$Kind;DisplayName=$DisplayName;Properties=$Properties;EvidenceKeys=@($EvidenceKeys)}
}
function New-EntraTopologyEdge {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$TenantId,[Parameter(Mandatory)][string]$From,[Parameter(Mandatory)][string]$To,[Parameter(Mandatory)][string]$Relationship,[string]$Qualifier='',[hashtable]$State=@{},[string[]]$EvidenceKeys=@())
    # Identity intentionally excludes mutable state: state changes become temporal changes, not delete+add churn.
    $id=Get-EntraTopologyStableId "$TenantId|$From|$Relationship|$To|$Qualifier"
    [pscustomobject][ordered]@{SchemaVersion='1.1.0';Key="edge:$id";Id=$id;TenantId=$TenantId;From=$From;To=$To;Relationship=$Relationship;Qualifier=$Qualifier;State=$State;EvidenceKeys=@($EvidenceKeys)}
}
function New-EntraTopologyEvidence {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$TenantId,[Parameter(Mandatory)][string]$Collector,[Parameter(Mandatory)][string]$Endpoint,[Parameter(Mandatory)][string]$SourceObjectId,[hashtable]$Fields=@{},[ValidateSet('Complete','Partial','NotRun','Unavailable')][string]$Completeness='Complete')
    $id=Get-EntraTopologyStableId "$TenantId|$Collector|$Endpoint|$SourceObjectId"
    [pscustomobject][ordered]@{SchemaVersion='1.1.0';Key="evidence:$id";Id=$id;TenantId=$TenantId;Collector=$Collector;Endpoint=$Endpoint;SourceObjectId=$SourceObjectId;Completeness=$Completeness;Fields=$Fields;ObservedAtUtc=[datetime]::UtcNow.ToString('o')}
}
function New-EntraTopologySignal {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$TenantId,[Parameter(Mandatory)][string]$TargetKey,[Parameter(Mandatory)][string]$Type,[ValidateSet('Info','Low','Medium','High','Critical')][string]$Severity='Info',[Parameter(Mandatory)][string]$Reason,[hashtable]$State=@{})
    $id=Get-EntraTopologyStableId "$TenantId|$TargetKey|$Type"
    [pscustomobject][ordered]@{SchemaVersion='1.1.0';Key="signal:$id";Id=$id;TenantId=$TenantId;TargetKey=$TargetKey;Type=$Type;Severity=$Severity;Reason=$Reason;State=$State}
}


function Get-EntraTopologyPortalBaseUri {
    [CmdletBinding()] param([AllowNull()][string]$TenantId)
    if([string]::IsNullOrWhiteSpace($TenantId)){return 'https://entra.microsoft.com'}
    "https://entra.microsoft.com/$([uri]::EscapeDataString($TenantId))"
}

function Get-EntraTopologyPortalUri {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$Kind,
        [AllowNull()][string]$ObjectId,
        [AllowNull()][string]$AppId
    )
    $base=Get-EntraTopologyPortalBaseUri -TenantId $TenantId
    $id=if($ObjectId){[uri]::EscapeDataString($ObjectId)}else{''}
    switch($Kind){
        'user' { if($id){return "$base/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/overview/userId/$id"} }
        'group' { if($id){return "$base/#view/Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/Overview/groupId/$id"} }
        'application' {
            if($AppId){return "$base/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/$([uri]::EscapeDataString($AppId))"}
        }
        'servicePrincipal' {
            if($id -and $AppId){return "$base/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/Overview/objectId/$id/appId/$([uri]::EscapeDataString($AppId))"}
        }
        'directoryRole' { return "$base/#view/Microsoft_AAD_IAM/RolesManagementMenuBlade/~/AllRoles" }
        'device' { return "$base/#view/Microsoft_AAD_Devices/DevicesMenuBlade/~/Devices" }
    }
    $null
}


function Get-EntraTopologyObjectFingerprint {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$InputObject)
    Get-EntraTopologyStableId ($InputObject | ConvertTo-Json -Compress -Depth 20)
}
function Save-EntraTopologyJson {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$InputObject,[Parameter(Mandatory)][string]$Path)
    $parent=Split-Path -Parent $Path;if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null};$InputObject|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $Path -Encoding utf8;Get-Item -LiteralPath $Path
}
function Read-EntraTopologyJson {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path)){throw "File not found: $Path"};Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json -Depth 40
}


function Get-EntraTopologyAdjacency { param([Parameter(Mandatory)][object]$Graph,[switch]$Undirected)
    $a=@{};foreach($n in @($Graph.Nodes)){$a[$n.Key]=[System.Collections.Generic.List[object]]::new()};foreach($e in @($Graph.Edges)){if(-not$a.ContainsKey($e.From)){$a[$e.From]=[System.Collections.Generic.List[object]]::new()};$a[$e.From].Add([pscustomobject]@{Next=$e.To;Edge=$e});if($Undirected){if(-not$a.ContainsKey($e.To)){$a[$e.To]=[System.Collections.Generic.List[object]]::new()};$a[$e.To].Add([pscustomobject]@{Next=$e.From;Edge=$e})}};$a
}

