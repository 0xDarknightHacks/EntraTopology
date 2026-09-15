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
