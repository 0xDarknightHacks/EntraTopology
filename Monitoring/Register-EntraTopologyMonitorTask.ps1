#requires -Version 7.2
#requires -RunAsAdministrator
<#
.SYNOPSIS
Registers the EntraTopology monitor as a Windows Scheduled Task running as SYSTEM.

.DESCRIPTION
The monitor script defaults to the copy in this repository and the runtime
configuration defaults to C:\ProgramData\EntraTopologyMonitor\monitor-config.json.
The Graph authentication module must be installed machine-wide because the task
runs as NT AUTHORITY\SYSTEM.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$MonitorScriptPath = (Join-Path $PSScriptRoot 'Invoke-EntraTopologyMonitor.ps1'),
    [string]$ConfigPath = (Join-Path $env:ProgramData 'EntraTopologyMonitor\monitor-config.json'),
    [ValidateRange(1, 1440)]
    [int]$EveryMinutes = 120,
    [string]$TaskName = 'EntraTopology Monitor'
)

$ErrorActionPreference = 'Stop'

$monitor = (Resolve-Path -LiteralPath $MonitorScriptPath -ErrorAction Stop).Path
$config = (Resolve-Path -LiteralPath $ConfigPath -ErrorAction Stop).Path
$pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source

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
    throw 'Microsoft.Graph.Authentication 2.33.0 or later is not installed in a machine-wide PowerShell module directory. Install it from an elevated PowerShell 7 session with: Install-Module Microsoft.Graph.Authentication -MinimumVersion 2.33.0 -Scope AllUsers'
}

$arguments = @(
    '-NoLogo'
    '-NoProfile'
    '-NonInteractive'
    '-ExecutionPolicy', 'Bypass'
    '-File', ('"{0}"' -f $monitor)
    '-ConfigPath', ('"{0}"' -f $config)
) -join ' '

$action = New-ScheduledTaskAction `
    -Execute $pwsh `
    -Argument $arguments `
    -WorkingDirectory (Split-Path -Parent $monitor)

$trigger = New-ScheduledTaskTrigger `
    -Once `
    -At (Get-Date).AddMinutes(2) `
    -RepetitionInterval (New-TimeSpan -Minutes $EveryMinutes)

$principal = New-ScheduledTaskPrincipal `
    -UserId 'SYSTEM' `
    -LogonType ServiceAccount `
    -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1)

if ($PSCmdlet.ShouldProcess($TaskName, "Register scheduled task every $EveryMinutes minute(s)")) {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description 'Periodic EntraTopology collection, semantic graph comparison, and severity-based notification.' `
        -Force | Out-Null

    Get-ScheduledTask -TaskName $TaskName
}
