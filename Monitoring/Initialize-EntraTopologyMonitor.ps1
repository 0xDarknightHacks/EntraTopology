#requires -Version 7.2
#requires -RunAsAdministrator
<#
.SYNOPSIS
Initializes the machine-local runtime state for EntraTopology monitoring.

.DESCRIPTION
Creates and ACL-hardens C:\ProgramData\EntraTopologyMonitor, validates that the
certificate private key and a machine-wide Microsoft.Graph.Authentication module
are available to SYSTEM, and writes monitor-config.json. Tenant state remains in
ProgramData and is never copied into the source repository.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$TenantId,
    [Parameter(Mandatory)][string]$ClientId,
    [Parameter(Mandatory)][string]$CertificateThumbprint,
    [string]$StateDirectory = (Join-Path $env:ProgramData 'EntraTopologyMonitor'),
    [ValidateSet('Info','Low','Medium','High','Critical')]
    [string]$NotifyAtOrAbove = 'High',
    [bool]$ExcludeMicrosoftFirstPartyApps = $true,
    [switch]$EnableNotification,
    [string]$SenderUserId = '',
    [string[]]$Recipients = @(),
    [string]$TenantDisplayName = '',
    [ValidateRange(1,25)][int]$NotificationMaxItems = 12,
    [bool]$SaveToSentItems = $true,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$state = [System.IO.Path]::GetFullPath($StateDirectory)
$configPath = Join-Path $state 'monitor-config.json'

if ($EnableNotification) {
    if ([string]::IsNullOrWhiteSpace($SenderUserId)) {
        throw 'EnableNotification requires SenderUserId.'
    }
    if (@($Recipients | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -eq 0) {
        throw 'EnableNotification requires at least one recipient.'
    }
}

$thumbprint = ($CertificateThumbprint -replace '\s','').ToUpperInvariant()
$certificatePath = "Cert:\LocalMachine\My\$thumbprint"
if (-not (Test-Path -LiteralPath $certificatePath)) {
    throw "Certificate not found in LocalMachine\My: $thumbprint"
}

$certificate = Get-Item -LiteralPath $certificatePath
if (-not $certificate.HasPrivateKey) {
    throw "Certificate $thumbprint does not have an accessible private key."
}

$machineRoots = @(
    (Join-Path $env:ProgramFiles 'PowerShell\Modules'),
    (Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules')
)
$machineGraphAuth = @(
    Get-Module -Name Microsoft.Graph.Authentication -ListAvailable |
        Where-Object {
            $module = $_
            $module.Version -ge [version]'2.33.0' -and
            @($machineRoots | Where-Object {
                $root = $_
                $root -and ([System.IO.Path]::GetFullPath($module.ModuleBase)).StartsWith(
                    [System.IO.Path]::GetFullPath($root),
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            }).Count -gt 0
        }
)
if ($machineGraphAuth.Count -eq 0) {
    throw 'Microsoft.Graph.Authentication 2.33.0 or later must be installed machine-wide for the SYSTEM task. Run: Install-Module Microsoft.Graph.Authentication -MinimumVersion 2.33.0 -Scope AllUsers'
}

if ((Test-Path -LiteralPath $configPath) -and -not $Force) {
    throw "Configuration already exists: $configPath. Use -Force to replace it."
}

if ($PSCmdlet.ShouldProcess($state, 'Initialize protected EntraTopology monitoring runtime state')) {
    New-Item -ItemType Directory -Force -Path $state | Out-Null

    $acl = Get-Acl -LiteralPath $state
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) {
        [void]$acl.RemoveAccessRuleAll($rule)
    }

    $inheritance = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $propagation = [System.Security.AccessControl.PropagationFlags]::None
    $allow = [System.Security.AccessControl.AccessControlType]::Allow
    foreach ($sidText in @('S-1-5-18','S-1-5-32-544')) {
        $sid = [System.Security.Principal.SecurityIdentifier]::new($sidText)
        $accessRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $sid,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            $inheritance,
            $propagation,
            $allow
        )
        [void]$acl.AddAccessRule($accessRule)
    }
    Set-Acl -LiteralPath $state -AclObject $acl

    $config = [ordered]@{
        TenantId = $TenantId
        ClientId = $ClientId
        CertificateThumbprint = $thumbprint
        StateDirectory = $state
        ExcludeMicrosoftFirstPartyApps = $ExcludeMicrosoftFirstPartyApps
        NotifyAtOrAbove = $NotifyAtOrAbove
        Notification = [ordered]@{
            Enabled = [bool]$EnableNotification
            SenderUserId = if ($EnableNotification) { $SenderUserId } else { '' }
            Recipients = if ($EnableNotification) { @($Recipients) } else { @() }
            TenantDisplayName = $TenantDisplayName
            MaxItems = $NotificationMaxItems
            SaveToSentItems = $SaveToSentItems
        }
    }

    $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding utf8

    [pscustomobject][ordered]@{
        StateDirectory = $state
        ConfigPath = $configPath
        CertificateThumbprint = $thumbprint
        GraphAuthenticationVersion = [string](($machineGraphAuth | Sort-Object Version -Descending | Select-Object -First 1).Version)
        NotificationEnabled = [bool]$EnableNotification
    }
}
