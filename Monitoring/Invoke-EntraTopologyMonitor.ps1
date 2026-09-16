#requires -Version 7.2
<#
.SYNOPSIS
Runs EntraTopology periodically, compares the current canonical graph with the
last successful baseline, and optionally sends high-severity notifications.

.NOTES
The first successful run establishes the baseline and does not alert.
The baseline is promoted only after a healthy collection and, when required,
a successful notification.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$notificationCommonPath = Join-Path $PSScriptRoot 'Private\Notification.Common.ps1'
if (-not (Test-Path -LiteralPath $notificationCommonPath)) {
    throw "Monitoring notification helper not found: $notificationCommonPath"
}
. $notificationCommonPath

$SeverityRank = @{
    Info     = 0
    Low      = 1
    Medium   = 2
    High     = 3
    Critical = 4
}

function Write-MonitorLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f ([datetime]::UtcNow.ToString('o')), $Level, $Message
    Write-Host $line

    if ($script:LogPath) {
        Add-Content -LiteralPath $script:LogPath -Value $line -Encoding utf8
    }
}

function Get-ChangeItem {
    param([Parameter(Mandatory)][object]$Change)

    if ($null -ne $Change.After) {
        return $Change.After
    }

    return $Change.Before
}

function Get-MonitorSeverity {
    param([Parameter(Mandatory)][object]$Change)

    $item = Get-ChangeItem -Change $Change
    $changeType = [string]$Change.Change
    $kind = [string]$Change.Kind

    if ($kind -eq 'Signal') {
        # A removed signal generally means risk/context was resolved.
        if ($changeType -eq 'Removed') {
            return 'Info'
        }

        $signalType = [string]$item.Type

        if ($signalType -in @(
            'highPrivilegeRoleAssignment',
            'highImpactApplicationPermission',
            'highImpactDelegatedPermission',
            'privilegedOwnerRelationship'
        )) {
            return 'Critical'
        }

        if ($signalType -in @(
            'ownerlessObject',
            'credentialExpired',
            'riskyIdentity',
            'riskyOwnerRelationship',
            'highImpactRequestedPermission',
            'disabledOwnerRelationship'
        )) {
            return 'High'
        }

        $nativeSeverity = [string]$item.Severity
        if ($SeverityRank.ContainsKey($nativeSeverity)) {
            return $nativeSeverity
        }

        return 'Medium'
    }

    if ($kind -eq 'Edge') {
        $relationship = [string]$item.Relationship

        if ($changeType -eq 'Added') {
            switch ($relationship) {
                'assignedDirectoryRole'   { return 'Critical' }
                'hasAppRoleAssignment'    { return 'High' }
                'hasDelegatedPermission'  { return 'High' }
                'hasCredential'           { return 'High' }
                'owns'                    { return 'Medium' }
                'registeredOwnerOf'       { return 'Medium' }
                'memberOf'                { return 'Medium' }
                'requiresApiPermission'   { return 'Medium' }
                default                   { return 'Low' }
            }
        }

        if ($changeType -eq 'Removed') {
            switch ($relationship) {
                'assignedDirectoryRole'   { return 'Medium' }
                'hasAppRoleAssignment'    { return 'Medium' }
                'hasDelegatedPermission'  { return 'Medium' }
                'hasCredential'           { return 'Medium' }
                'owns'                    { return 'Medium' }
                'registeredOwnerOf'       { return 'Medium' }
                default                   { return 'Low' }
            }
        }

        return 'Low'
    }

    if ($kind -eq 'Node') {
        $nodeKind = [string]$item.Kind
        if ($nodeKind -eq 'applicationCredential' -and $changeType -in @('Added','Changed')) {
            return 'High'
        }

        return 'Low'
    }

    return 'Info'
}

function Save-Json {
    param(
        [Parameter(Mandatory)][object]$InputObject,
        [Parameter(Mandatory)][string]$Path,
        [int]$Depth = 100
    )

    $InputObject |
        ConvertTo-Json -Depth $Depth |
        Set-Content -LiteralPath $Path -Encoding utf8
}

function Get-LoadedIdentityAssemblySummary {
    [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object {
            $_.GetName().Name -in @(
                'Azure.Identity',
                'Microsoft.Identity.Client',
                'Microsoft.IdentityModel.Abstractions',
                'Microsoft.Graph.Authentication',
                'Microsoft.Graph.Authentication.Core'
            )
        } |
        Sort-Object { $_.GetName().Name } |
        ForEach-Object {
            $name = $_.GetName()
            [pscustomobject][ordered]@{
                Name     = [string]$name.Name
                Version  = [string]$name.Version
                Location = [string]$_.Location
            }
        }
}

function Assert-MonitorGraphAuthenticationModule {
    $module = Get-Module -Name Microsoft.Graph.Authentication
    if ($null -eq $module) {
        throw 'Microsoft.Graph.Authentication failed to load.'
    }

    if ($module.Version -lt [version]'2.33.0') {
        throw "Microsoft.Graph.Authentication $($module.Version) is loaded. Install or load version 2.33.0 or later for certificate-based monitor authentication."
    }

    $moduleRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $module.Path))
    $conflicts = @(
        Get-LoadedIdentityAssemblySummary |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_.Location) -and
                -not ([System.IO.Path]::GetFullPath($_.Location).StartsWith($moduleRoot, [System.StringComparison]::OrdinalIgnoreCase))
            }
    )

    if ($conflicts.Count -gt 0) {
        $details = ($conflicts | ForEach-Object { "$($_.Name) $($_.Version) from $($_.Location)" }) -join '; '
        throw "Conflicting Microsoft identity assemblies are already loaded before monitor authentication: $details. Start the monitor in a fresh pwsh process and avoid preloading Az/Microsoft.Graph modules with different dependency versions."
    }
}

function ConvertTo-MonitorConnectionError {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

    $message = [string]$ErrorRecord.Exception.Message
    if ($message -match 'ClientCertificateCredential authentication failed' -and $message -match 'Method not found') {
        $assemblies = (Get-LoadedIdentityAssemblySummary | ForEach-Object {
            "$($_.Name) $($_.Version) from $($_.Location)"
        }) -join '; '

        return "Microsoft Graph certificate authentication failed because incompatible Microsoft identity assemblies are loaded in this PowerShell process. Loaded assemblies: $assemblies. Run the monitor from a fresh PowerShell 7 process, remove preloaded Az/Microsoft.Graph modules from the host profile, and keep Microsoft.Graph.Authentication updated."
    }

    return $message
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Configuration file not found: $ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -Depth 30

$defaultStateDirectory = Join-Path $env:ProgramData 'EntraTopologyMonitor'
$stateDirectory = if (
    $null -ne $config.PSObject.Properties['StateDirectory'] -and
    -not [string]::IsNullOrWhiteSpace([string]$config.StateDirectory)
) {
    [System.IO.Path]::GetFullPath([string]$config.StateDirectory)
} else {
    [System.IO.Path]::GetFullPath($defaultStateDirectory)
}

New-Item -ItemType Directory -Force -Path $stateDirectory | Out-Null

$script:LogPath = Join-Path $stateDirectory 'monitor.log'
$baselinePath = Join-Path $stateDirectory 'baseline-topology.json'
$lastDeltaPath = Join-Path $stateDirectory 'last-delta.json'
$lastAlertPath = Join-Path $stateDirectory 'last-alert.json'
$statePath = Join-Path $stateDirectory 'monitor-state.json'
$runDirectory = Join-Path $stateDirectory ('run-' + [datetime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))

$defaultModuleManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'EntraTopology.psd1'
$moduleManifestPath = if (
    $null -ne $config.PSObject.Properties['ModuleManifestPath'] -and
    -not [string]::IsNullOrWhiteSpace([string]$config.ModuleManifestPath)
) {
    [System.IO.Path]::GetFullPath([string]$config.ModuleManifestPath)
} else {
    [System.IO.Path]::GetFullPath($defaultModuleManifestPath)
}

$notifyAtOrAbove = if (
    $null -eq $config.PSObject.Properties['NotifyAtOrAbove'] -or
    [string]::IsNullOrWhiteSpace([string]$config.NotifyAtOrAbove)
) {
    'High'
} else {
    [string]$config.NotifyAtOrAbove
}

$notificationEnabled = $false
if ($null -ne $config.PSObject.Properties['Notification'] -and $null -ne $config.Notification) {
    if ($null -ne $config.Notification.PSObject.Properties['Enabled']) {
        $notificationEnabled = [bool]$config.Notification.Enabled
    }
}

$excludeMicrosoftFirstParty = $true
if ($null -ne $config.PSObject.Properties['ExcludeMicrosoftFirstPartyApps']) {
    $excludeMicrosoftFirstParty = [bool]$config.ExcludeMicrosoftFirstPartyApps
}

$connected = $false
$success = $false

try {
    foreach ($required in @('TenantId','ClientId','CertificateThumbprint')) {
        if ($null -eq $config.PSObject.Properties[$required] -or [string]::IsNullOrWhiteSpace([string]$config.$required)) {
            throw "Missing required configuration value: $required"
        }
    }

    Write-MonitorLog "Starting EntraTopology monitor run for tenant $($config.TenantId)."

    if (-not (Test-Path -LiteralPath $moduleManifestPath)) {
        throw "EntraTopology module manifest not found: $moduleManifestPath"
    }

    $certificateThumbprint = ([string]$config.CertificateThumbprint -replace '\s','').ToUpperInvariant()
    $certificatePath = "Cert:\LocalMachine\My\$certificateThumbprint"
    if (-not (Test-Path -LiteralPath $certificatePath)) {
        throw "Monitoring certificate not found in LocalMachine\My: $certificateThumbprint"
    }
    $monitorCertificate = Get-Item -LiteralPath $certificatePath
    if (-not $monitorCertificate.HasPrivateKey) {
        throw "Monitoring certificate $certificateThumbprint does not have an accessible private key."
    }

    if ($notificationEnabled) {
        if (
            $null -eq $config.Notification.PSObject.Properties['SenderUserId'] -or
            $null -eq $config.Notification.PSObject.Properties['Recipients']
        ) {
            throw 'Notification.Enabled is true but SenderUserId or Recipients is not configured.'
        }

        $sender = [string]$config.Notification.SenderUserId
        $recipients = @($config.Notification.Recipients | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ([string]::IsNullOrWhiteSpace($sender) -or $recipients.Count -eq 0) {
            throw 'Notification.Enabled is true but SenderUserId or Recipients is not configured.'
        }
    }

    if (-not $SeverityRank.ContainsKey($notifyAtOrAbove)) {
        throw "Unsupported NotifyAtOrAbove value '$notifyAtOrAbove'."
    }

    try {
        Import-Module Microsoft.Graph.Authentication -MinimumVersion 2.33.0 -ErrorAction Stop
    }
    catch {
        throw "Microsoft.Graph.Authentication 2.33.0 or later could not be loaded. Scheduled monitoring runs as SYSTEM, so install the module machine-wide with: Install-Module Microsoft.Graph.Authentication -MinimumVersion 2.33.0 -Scope AllUsers. Details: $($_.Exception.Message)"
    }

    Assert-MonitorGraphAuthenticationModule
    Import-Module $moduleManifestPath -Force -ErrorAction Stop

    try {
        Connect-EntraTopologyGraph `
            -ClientId ([string]$config.ClientId) `
            -CertificateTenantId ([string]$config.TenantId) `
            -CertificateThumbprint $certificateThumbprint `
            -NoWelcome | Out-Null
    }
    catch {
        throw (ConvertTo-MonitorConnectionError -ErrorRecord $_)
    }

    $connected = $true

    $ctx = Get-MgContext
    if ([string]$ctx.AuthType -ne 'AppOnly') {
        throw "Expected app-only authentication but Graph context reports '$($ctx.AuthType)'."
    }

    $result = Invoke-EntraTopology `
        -OutputDirectory $runDirectory `
        -SkipConnect `
        -NoDisconnect `
        -NoBanner `
        -NoProgress `
        -NoReport `
        -PassThru `
        -ExcludeMicrosoftFirstPartyApps:$excludeMicrosoftFirstParty

    if ([long]$result.GraphCallsAfterSnapshot -ne 0) {
        throw "Release boundary violated: GraphCallsAfterSnapshot=$($result.GraphCallsAfterSnapshot)."
    }

    $graph = $result.Graph
    if ($null -eq $graph) {
        throw 'Invoke-EntraTopology did not return the canonical graph.'
    }

    # Partial coverage is accepted because some Microsoft Graph limitations are
    # deterministic and fail-closed. Failed/Unavailable collectors are not.
    $unhealthyCoverage = @(
        $graph.Coverage |
            Where-Object { [string]$_.Status -in @('Failed','Unavailable') }
    )

    if ($unhealthyCoverage.Count -gt 0) {
        $names = ($unhealthyCoverage | ForEach-Object { "$($_.Collector)=$($_.Status)" }) -join ', '
        throw "Collection coverage is unhealthy; baseline will not be promoted: $names"
    }

    if (-not (Test-Path -LiteralPath $baselinePath)) {
        Copy-Item -LiteralPath $result.GraphPath -Destination $baselinePath -Force

        Save-Json -InputObject ([ordered]@{
            InitializedAtUtc                = [datetime]::UtcNow.ToString('o')
            LastSuccessfulRunUtc            = [datetime]::UtcNow.ToString('o')
            TenantId                        = [string]$graph.TenantId
            LastGraphId                     = [string]$graph.GraphId
            BaselineGraphSchemaVersion      = [string]$graph.SchemaVersion
            ExcludeMicrosoftFirstPartyApps  = $excludeMicrosoftFirstParty
            LastAlertCount                  = 0
        }) -Path $statePath -Depth 10

        Write-MonitorLog 'Baseline initialized. No alert was sent on the first run.'
        $success = $true
        return
    }

    $baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json -Depth 100

    $baselineSchemaVersion = [string]$baseline.SchemaVersion
    $currentSchemaVersion = [string]$graph.SchemaVersion
    if (
        [string]::IsNullOrWhiteSpace($baselineSchemaVersion) -or
        [string]::IsNullOrWhiteSpace($currentSchemaVersion) -or
        $baselineSchemaVersion -ne $currentSchemaVersion
    ) {
        throw "Monitoring baseline schema mismatch: baseline='$baselineSchemaVersion', current='$currentSchemaVersion'. The baseline was not promoted. Reinitialize the baseline deliberately after validating the schema change."
    }

    if (-not (Test-Path -LiteralPath $statePath)) {
        throw "Monitoring baseline exists but monitor-state.json is missing. The collection policy that produced the baseline cannot be verified, so the baseline was not promoted. Restore monitor-state.json or reinitialize the baseline deliberately."
    }

    $previousState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -Depth 30
    if ($null -ne $previousState.PSObject.Properties['ExcludeMicrosoftFirstPartyApps']) {
        $previousExclude = [bool]$previousState.ExcludeMicrosoftFirstPartyApps
        if ($previousExclude -ne $excludeMicrosoftFirstParty) {
            throw "Monitoring collection policy changed: ExcludeMicrosoftFirstPartyApps was '$previousExclude' and is now '$excludeMicrosoftFirstParty'. The baseline was not promoted. Reinitialize the baseline deliberately after validating the policy change."
        }
    } else {
        throw 'Monitoring baseline collection policy cannot be proven because monitor-state.json does not record ExcludeMicrosoftFirstPartyApps. The baseline was not compared or promoted. Reinitialize the baseline deliberately after validating the originating collection policy.'
    }

    $delta = Compare-EntraTopologyGraph -ReferenceGraph $baseline -DifferenceGraph $graph
    Save-Json -InputObject $delta -Path $lastDeltaPath

    $notificationLookup = New-EntraTopologyMonitorLookup -Graph $graph -Baseline $baseline
    $alerts = [System.Collections.Generic.List[object]]::new()

    foreach ($change in @($delta.Changes)) {
        $severity = Get-MonitorSeverity -Change $change

        if ($SeverityRank[$severity] -ge $SeverityRank[$notifyAtOrAbove]) {
            $alerts.Add((New-EntraTopologyMonitorAlert `
                -Change $change `
                -Severity $severity `
                -Lookup $notificationLookup))
        }
    }

    if ($alerts.Count -gt 0) {
        Save-Json -InputObject @($alerts) -Path $lastAlertPath -Depth 20

        if ($notificationEnabled) {
            $notificationMessage = New-EntraTopologyMonitorNotification `
                -Notification $config.Notification `
                -Alerts @($alerts) `
                -Delta $delta `
                -TenantId ([string]$graph.TenantId) `
                -Graph $graph `
                -Baseline $baseline `
                -PreviousState $previousState

            Send-EntraTopologyMonitorNotification `
                -Notification $config.Notification `
                -Message $notificationMessage

            Write-MonitorLog "Sent $($notificationMessage.HighestSeverity) notification for $($notificationMessage.SignificantChangeCount) significant change(s) ($($alerts.Count) alert record(s)) at or above $notifyAtOrAbove."
        } else {
            Write-MonitorLog "$($alerts.Count) alert-worthy change(s) detected; email notification is disabled." 'WARN'
        }
    } else {
        if (Test-Path -LiteralPath $lastAlertPath) {
            Remove-Item -LiteralPath $lastAlertPath -Force
        }
        Write-MonitorLog "No changes at or above $notifyAtOrAbove."
    }

    # Promote only after the current run has completed successfully.
    $tempBaselinePath = "$baselinePath.new"
    Copy-Item -LiteralPath $result.GraphPath -Destination $tempBaselinePath -Force
    Move-Item -LiteralPath $tempBaselinePath -Destination $baselinePath -Force

    Save-Json -InputObject ([ordered]@{
        LastSuccessfulRunUtc            = [datetime]::UtcNow.ToString('o')
        TenantId                        = [string]$graph.TenantId
        LastGraphId                     = [string]$graph.GraphId
        BaselineGraphSchemaVersion      = [string]$graph.SchemaVersion
        ExcludeMicrosoftFirstPartyApps  = $excludeMicrosoftFirstParty
        LastComparison                  = $delta.Summary
        LastAlertCount                  = $alerts.Count
        NotifyAtOrAbove                 = $notifyAtOrAbove
    }) -Path $statePath -Depth 20

    Write-MonitorLog "Baseline promoted successfully. Delta: +$($delta.Summary.Added) / -$($delta.Summary.Removed) / ~$($delta.Summary.Changed)."
    $success = $true
}
catch {
    Write-MonitorLog $_.Exception.Message 'ERROR'
    throw
}
finally {
    if ($connected) {
        try {
            Disconnect-MgGraph | Out-Null
        }
        catch {
            Write-MonitorLog "Graph disconnect warning: $($_.Exception.Message)" 'WARN'
        }
    }

    # Successful runs keep only baseline, last delta/alert, state, and log.
    # Failed run directories are retained for troubleshooting.
    if ($success -and (Test-Path -LiteralPath $runDirectory)) {
        Remove-Item -LiteralPath $runDirectory -Recurse -Force
    }
}
