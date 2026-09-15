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
