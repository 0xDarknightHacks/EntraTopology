BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' 'EntraTopology.psd1') -Force }

Describe 'Application topology enrichment' {
    InModuleScope EntraTopology {
        BeforeEach {
            Mock Invoke-EntraTopologyGraphBatch { @() }
        }

        It 'classifies and excludes Microsoft first-party enterprise apps while retaining referenced API resources' {
            Mock Test-EntraTopologyPermission { $true }
            Mock Invoke-EntraTopologyGraphRequest {
                param($Uri,$RequiredPermission,$Telemetry)
                if($Uri -like '/v1.0/applications*'){
                    return [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@([pscustomobject]@{id='app1';appId='client-app';displayName='Client';passwordCredentials=@([pscustomobject]@{keyId='secret1';displayName='Primary';startDateTime='2026-01-01T00:00:00Z';endDateTime='2026-10-01T00:00:00Z'});keyCredentials=@();requiredResourceAccess=@([pscustomobject]@{resourceAppId='00000003-0000-0000-c000-000000000000';resourceAccess=@([pscustomobject]@{id='role1';type='Role'})})});Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='apps';RetryCount=0;PageCount=1}
                }
                if($Uri -like '/v1.0/servicePrincipals*'){
                    return [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@(
                        [pscustomobject]@{id='sp-local';appId='client-app';displayName='Client SP';accountEnabled=$true;servicePrincipalType='Application';appOwnerOrganizationId='tenant';appRoles=@();oauth2PermissionScopes=@();keyCredentials=@()},
                        [pscustomobject]@{id='sp-graph';appId='00000003-0000-0000-c000-000000000000';displayName='Microsoft Graph';accountEnabled=$true;servicePrincipalType='Application';appOwnerOrganizationId='f8cdef31-a31e-4b4a-93e4-5f571e91255a';appRoles=@([pscustomobject]@{id='role1';value='User.Read.All';displayName='Read all users'});oauth2PermissionScopes=@();keyCredentials=@()},
                        [pscustomobject]@{id='sp-explorer';appId='de8bc8b5-d9f9-48b1-a8ad-b748da725064';displayName='Graph Explorer';accountEnabled=$true;servicePrincipalType='Application';appOwnerOrganizationId='72f988bf-86f1-41af-91ab-2d7cd011db47';appRoles=@();oauth2PermissionScopes=@();keyCredentials=@()},
                        [pscustomobject]@{id='sp-cli';appId='14d82eec-204b-4c2f-b7e8-296a70dab67e';displayName='Microsoft Graph Command Line Tools';accountEnabled=$true;servicePrincipalType='Application';appOwnerOrganizationId=$null;appRoles=@();oauth2PermissionScopes=@();keyCredentials=@()}
                    );Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='sps';RetryCount=0;PageCount=1}
                }
                [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@();Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='other';RetryCount=0;PageCount=1}
            }
            $result=Get-EntraTopologyApplications -TenantId 'tenant' -ExcludeMicrosoftFirstPartyApps
            $result.Metrics.ExcludedMicrosoftFirstPartyServicePrincipalCount | Should -Be 3
            @($result.Objects|Where-Object{[string]$_.Kind -eq 'applicationCredential'}).Count | Should -Be 1
            $graphRef=@($result.Objects|Where-Object{[string]$_.Kind -eq 'servicePrincipal' -and [string]$_.Object.id -eq 'sp-graph'})[0]
            $graphRef.Object.topologyReferenceOnly | Should -BeTrue
            @($result.Objects|Where-Object{[string]$_.Kind -eq 'servicePrincipal' -and [string]$_.Object.id -in @('sp-explorer','sp-cli')}).Count | Should -Be 0
            @($result.Relations|Where-Object Relationship -eq 'requiresApiPermission').Count | Should -Be 1
            @($result.Relations|Where-Object Relationship -eq 'hasCredential').Count | Should -Be 1
        }

        It 'probes delegated permission grants in app-only mode even when local scope introspection is incomplete' {
            Mock Get-EntraTopologyGraphContext { [pscustomobject]@{AuthType='AppOnly';Scopes=@('Application.Read.All')} }
            Mock Test-EntraTopologyPermission { param($AnyOf) return ($AnyOf -contains 'Application.Read.All') }
            Mock Invoke-EntraTopologyGraphRequest {
                param($Uri,$RequiredPermission,$Telemetry)
                if($Uri -like '/v1.0/applications*'){return [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@();Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='a';RetryCount=0;PageCount=1}}
                if($Uri -like '/v1.0/servicePrincipals*'){return [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@([pscustomobject]@{id='client';appId='c';displayName='Client';servicePrincipalType='Application';appOwnerOrganizationId='tenant';appRoles=@();oauth2PermissionScopes=@();keyCredentials=@()},[pscustomobject]@{id='resource';appId='r';displayName='API';servicePrincipalType='Application';appOwnerOrganizationId='external';appRoles=@();oauth2PermissionScopes=@();keyCredentials=@()});Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='s';RetryCount=0;PageCount=1}}
                if($Uri -like '/v1.0/oauth2PermissionGrants*'){return [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@([pscustomobject]@{id='grant1';clientId='client';resourceId='resource';consentType='AllPrincipals';principalId=$null;scope='User.Read Group.Read.All'});Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='g';RetryCount=0;PageCount=1}}
                return [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@();Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='other';RetryCount=0;PageCount=1}
            }
            $result=Get-EntraTopologyApplications -TenantId 'tenant'
            $delegatedCapability=@($result.Capabilities|Where-Object Name -eq 'DelegatedPermissionGrants')[0]
            $delegatedCapability.Status | Should -Be 'Complete'
            $delegatedCapability.RequiredPermissions | Should -Contain 'Directory.Read.All'
            @($result.Relations|Where-Object Relationship -eq 'hasDelegatedPermission').Count | Should -Be 1
            Should -Invoke Invoke-EntraTopologyGraphRequest -ParameterFilter { $Uri -like '/v1.0/oauth2PermissionGrants*' } -Times 1 -Exactly
        }
    }
}

Describe 'Credential and permission security context' {
    It 'emits expired and expiring credential signals on credential nodes' {
        $snapshot=[pscustomobject]@{TenantId='tenant';SnapshotId='cred';CollectedAtUtc='2026-09-14T00:00:00Z';Collectors=@(
            [pscustomobject]@{Name='Applications';Status='Complete';RequiredPermissions=@('Application.Read.All');Warnings=@();Metrics=@{};Evidence=@();Capabilities=@(
                [pscustomobject]@{Name='ApplicationInventory';Status='Complete';RequiredPermissions=@();Endpoints=@();Warnings=@()},
                [pscustomobject]@{Name='ApplicationCredentialMetadata';Status='Complete';RequiredPermissions=@();Endpoints=@();Warnings=@()},
                [pscustomobject]@{Name='ServicePrincipalCredentialMetadata';Status='Complete';RequiredPermissions=@();Endpoints=@();Warnings=@()}
            );Objects=@(
                [pscustomobject]@{Kind='applicationCredential';Object=[pscustomobject]@{id='c1';displayName='Expired secret';parentKind='application';credentialType='passwordCredential';endDateTime='2020-01-01T00:00:00Z'}},
                [pscustomobject]@{Kind='applicationCredential';Object=[pscustomobject]@{id='c2';displayName='Future secret';parentKind='application';credentialType='passwordCredential';endDateTime=([datetime]::UtcNow.AddDays(20).ToString('o'))}}
            );Relations=@()}
        )}
        $graph=New-EntraTopologyGraph -Snapshot $snapshot -IncludeSignals
        @($graph.Signals|Where-Object Type -eq 'credentialExpired').Count | Should -Be 1
        @($graph.Signals|Where-Object Type -eq 'credentialExpiring').Count | Should -Be 1
    }
}
