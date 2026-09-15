BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' 'EntraTopology.psd1') -Force }

Describe 'Stored app-only authentication' {
    InModuleScope EntraTopology {
        BeforeEach {
            function Get-Secret { param($Name,$Vault) }
        }

        It 'loads tenant/client IDs from config and the client secret from SecretManagement' {
            $configPath=Join-Path $TestDrive 'config.json'
            @{TenantId='tenant-id';ClientId='client-id'} | ConvertTo-Json | Set-Content -LiteralPath $configPath
            $secure=ConvertTo-SecureString 'secret-value' -AsPlainText -Force
            Mock Get-Secret { $secure }

            $stored=Get-EntraTopologyStoredAppCredential -ConfigPath $configPath -VaultName 'TestVault' -SecretName 'TestSecret'
            $stored.TenantId | Should -Be 'tenant-id'
            $stored.ClientId | Should -Be 'client-id'
            $stored.ClientSecretCredential.UserName | Should -Be 'client-id'
            Should -Invoke Get-Secret -Times 1 -Exactly -ParameterFilter {$Name -eq 'TestSecret' -and $Vault -eq 'TestVault'}
        }

        It 'rejects plaintext secret material in the configuration file' {
            $configPath=Join-Path $TestDrive 'bad-config.json'
            @{TenantId='tenant-id';ClientId='client-id';ClientSecret='do-not-store-here'} | ConvertTo-Json | Set-Content -LiteralPath $configPath
            { Get-EntraTopologyStoredAppCredential -ConfigPath $configPath } | Should -Throw '*Do not store client secrets*'
        }


        It 'requests Directory.Read.All for delegated delegated-consent collection' {
            Mock Connect-MgGraph {}
            Mock Assert-EntraTopologyGraphConnected { [pscustomobject]@{TenantId='tenant-id';ClientId='client-id';AuthType='Delegated';Scopes=@('Application.Read.All','Directory.Read.All')} }

            Connect-EntraTopologyGraph -TenantId 'tenant-id' -Scopes @('Application.Read.All') -IncludeDelegatedPermissionGrants | Out-Null
            Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter { $Scopes -contains 'Directory.Read.All' -and $Scopes -notcontains 'DelegatedPermissionGrant.Read.All' }
        }

        It 'passes a PSCredential to Connect-MgGraph for stored-secret app-only authentication' {
            $configPath=Join-Path $TestDrive 'config.json'
            @{TenantId='tenant-id';ClientId='client-id'} | ConvertTo-Json | Set-Content -LiteralPath $configPath
            $secure=ConvertTo-SecureString 'secret-value' -AsPlainText -Force
            Mock Get-Secret { $secure }
            Mock Connect-MgGraph {}
            Mock Assert-EntraTopologyGraphConnected { [pscustomobject]@{TenantId='tenant-id';ClientId='client-id';AuthType='AppOnly';Scopes=@('User.Read.All')} }

            $result=Connect-EntraTopologyGraph -UseStoredAppCredentials -ConfigPath $configPath -VaultName 'TestVault' -SecretName 'TestSecret'
            $result.TenantId | Should -Be 'tenant-id'
            Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter {$TenantId -eq 'tenant-id' -and $null -ne $ClientSecretCredential}
        }
    }
}
