function Invoke-EntraTopologyCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [object]$Telemetry,
        [ValidateRange(1,20)][int]$BatchSize=20,
        [switch]$ExcludeMicrosoftFirstPartyApps
    )

    $collectors=@(
        Get-EntraTopologyUsers -TenantId $TenantId -Telemetry $Telemetry
        Get-EntraTopologyGroups -TenantId $TenantId -Telemetry $Telemetry -BatchSize $BatchSize
        Get-EntraTopologyApplications -TenantId $TenantId -Telemetry $Telemetry -BatchSize $BatchSize -ExcludeMicrosoftFirstPartyApps:$ExcludeMicrosoftFirstPartyApps
        Get-EntraTopologyDevices -TenantId $TenantId -Telemetry $Telemetry -BatchSize $BatchSize
        Get-EntraTopologyRoles -TenantId $TenantId -Telemetry $Telemetry
    )

    # A final read-only resolution pass keeps collectors independent while resolving relation endpoints
    # (for example role-assignment principals) that were not present in the primary inventories.
    $resolver=Resolve-EntraTopologyDirectoryObjects -TenantId $TenantId -Collectors $collectors -Telemetry $Telemetry
    @($collectors)+@($resolver)
}
