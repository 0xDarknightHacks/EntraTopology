function New-EntraTopologySnapshot {
    [CmdletBinding()]
    param(
        [string]$Path,
        [ValidateRange(1,20)][int]$BatchSize=20,
        [switch]$ExcludeMicrosoftFirstPartyApps,
        [AllowNull()][object]$Telemetry
    )
    $ctx=Assert-EntraTopologyGraphConnected; $tenant=[string]$ctx.TenantId
    if(-not$tenant){throw 'The connected Graph context does not expose a tenant ID.'}
    if($null -eq $Telemetry){$Telemetry=New-EntraTopologyTelemetry}
    $collectors=@(Invoke-EntraTopologyCollection -TenantId $tenant -Telemetry $Telemetry -BatchSize $BatchSize -ExcludeMicrosoftFirstPartyApps:$ExcludeMicrosoftFirstPartyApps)
    $boundaryCount=Get-EntraTopologyGraphTransportCallCount
    $snapshot=[pscustomobject][ordered]@{
        SchemaVersion='1.0';SnapshotId=(Get-EntraTopologyStableId "$tenant|$([datetime]::UtcNow.ToString('o'))");TenantId=$tenant;CollectedAtUtc=[datetime]::UtcNow.ToString('o')
        Collectors=$collectors;Telemetry=$Telemetry;GraphHttpRequestsAtSnapshotBoundary=$boundaryCount;GraphCallsAfterSnapshot=0
    }
    if($Path){Save-EntraTopologyJson -InputObject $snapshot -Path $Path|Out-Null}
    $snapshot
}
