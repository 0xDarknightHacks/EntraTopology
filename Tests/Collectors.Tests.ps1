Import-Module (Join-Path $PSScriptRoot '..' 'EntraTopology.psd1') -Force

Describe 'Collector capability and diagnostics behavior' {
    InModuleScope EntraTopology {
        It 'keeps signInActivity optional and declares AuditLog.Read.All explicitly' {
            Mock Test-EntraTopologyPermission {
                param($AnyOf)
                return ($AnyOf -contains 'User.Read.All' -or $AnyOf -contains 'Directory.Read.All')
            }
            Mock Invoke-EntraTopologyGraphRequest {
                param($Uri,$RequiredPermission,$Telemetry)
                [pscustomobject]@{
                    SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;
                    Items=@([pscustomobject]@{id='u1';displayName='User One';accountEnabled=$true});CollectionTime='';Limitations=@();
                    ErrorCode=$null;ErrorMessage=$null;RequestId=$null;RetryCount=0;PageCount=1
                }
            }
            $result=Get-EntraTopologyUsers -TenantId 'tenant'
            $result.Status | Should -Be 'Complete'
            (@($result.Capabilities | Where-Object Name -eq 'UserSignInActivity')[0]).Status | Should -Be 'NotRun'
            (@($result.Capabilities | Where-Object Name -eq 'UserSignInActivity')[0]).RequiredPermissions | Should -Contain 'AuditLog.Read.All'
            (@($result.Capabilities | Where-Object Name -eq 'RiskyUserContext')[0]).Status | Should -Be 'NotRun'
            Should -Invoke Invoke-EntraTopologyGraphRequest -Times 1 -Exactly
        }

        It 'merges optional risky-user context when IdentityRiskyUser.Read.All is available' {
            Mock Test-EntraTopologyPermission {
                param($AnyOf)
                return ($AnyOf -contains 'User.Read.All' -or $AnyOf -contains 'Directory.Read.All' -or $AnyOf -contains 'IdentityRiskyUser.Read.All')
            }
            Mock Invoke-EntraTopologyGraphRequest {
                param($Uri,$RequiredPermission,$Telemetry)
                if($Uri -like '*identityProtection/riskyUsers*'){
                    return [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@([pscustomobject]@{id='u1';riskLevel='high';riskState='atRisk';riskDetail='adminConfirmedUserCompromised';riskLastUpdatedDateTime='2026-01-01T00:00:00Z';isDeleted=$false});CollectionTime='';Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='risk';RetryCount=0;PageCount=1}
                }
                [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@([pscustomobject]@{id='u1';displayName='User One';userPrincipalName='user@example.test';accountEnabled=$true});CollectionTime='';Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='users';RetryCount=0;PageCount=1}
            }
            $result=Get-EntraTopologyUsers -TenantId 'tenant'
            (@($result.Capabilities | Where-Object Name -eq 'RiskyUserContext')[0]).Status | Should -Be 'Complete'
            $result.Objects[0].Object.riskState | Should -Be 'atRisk'
            $result.Objects[0].Object.riskLevel | Should -Be 'high'
            $result.Metrics.ActiveRiskyUserCount | Should -Be 1
        }

        It 'surfaces directory-role assignment 403 provenance and delegated role guidance' {
            Mock Test-EntraTopologyPermission { $true }
            Mock Invoke-EntraTopologyGraphRequest {
                param($Uri,$RequiredPermission,$Telemetry)
                if($Uri -like '*roleDefinitions*'){
                    return [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@([pscustomobject]@{id='r1';displayName='Role'});CollectionTime='';Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId=$null;RetryCount=0;PageCount=1}
                }
                [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='InsufficientPermission';StatusCode=403;Items=@();CollectionTime='';Limitations=@('Insufficient privileges');ErrorCode='Authorization_RequestDenied';ErrorMessage='Insufficient privileges';RequestId='req-roles';RetryCount=0;PageCount=0}
            }
            $result=Get-EntraTopologyRoles -TenantId 'tenant'
            $result.Status | Should -Be 'Partial'
            (@($result.Capabilities | Where-Object Name -eq 'DirectoryRoleAssignments')[0]).Status | Should -Be 'Partial'
            ($result.Warnings -join ' ') | Should -Match 'Directory Readers'
            ($result.Warnings -join ' ') | Should -Match 'req-roles'
        }


        It 'uses the directory-provider role assignment shape and preserves assignment evidence metadata' {
            Mock Test-EntraTopologyPermission { $true }
            $script:assignmentUri=$null
            Mock Invoke-EntraTopologyGraphRequest {
                param($Uri,$RequiredPermission,$Telemetry)
                if($Uri -like '*roleDefinitions*'){
                    return [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@([pscustomobject]@{id='r1';displayName='Role'});CollectionTime='';Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId=$null;RetryCount=0;PageCount=1}
                }
                $script:assignmentUri=$Uri
                [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@([pscustomobject]@{id='a1';principalId='u1';roleDefinitionId='r1';directoryScopeId='/'});CollectionTime='';Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId=$null;RetryCount=0;PageCount=1}
            }
            $result=Get-EntraTopologyRoles -TenantId 'tenant'
            $result.Status | Should -Be 'Complete'
            $script:assignmentUri | Should -Not -Match 'appScopeId'
            $result.Relations.Count | Should -Be 1
            $result.Relations[0].Qualifier | Should -Be '/'
            $result.Relations[0].State.ContainsKey('appScopeId') | Should -BeFalse
            $result.Relations[0].EvidenceRefs[0].Capability | Should -Be 'DirectoryRoleAssignments'
        }
    }
}
