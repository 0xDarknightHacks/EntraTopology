BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' 'EntraTopology.psd1') -Force }

Describe 'Entra admin center links' {
    InModuleScope EntraTopology {
        It 'generates tenant-scoped links for supported object types' {
            (Get-EntraTopologyPortalUri -TenantId 'tenant' -Kind user -ObjectId 'user-id') | Should -Match 'entra\.microsoft\.com/tenant/.+userId/user-id'
            (Get-EntraTopologyPortalUri -TenantId 'tenant' -Kind group -ObjectId 'group-id') | Should -Match 'groupId/group-id'
            (Get-EntraTopologyPortalUri -TenantId 'tenant' -Kind application -ObjectId 'object-id' -AppId 'app-id') | Should -Match 'RegisteredApps.+appId/app-id'
            (Get-EntraTopologyPortalUri -TenantId 'tenant' -Kind servicePrincipal -ObjectId 'sp-id' -AppId 'app-id') | Should -Match 'ManagedAppMenuBlade.+objectId/sp-id/appId/app-id'
        }
    }
}
