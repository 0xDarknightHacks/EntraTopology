Import-Module (Join-Path $PSScriptRoot '..' 'EntraTopology.psd1') -Force

$global:NewTestBatchResult = {
    param([object]$Request,[object[]]$Items=@(),[string]$Status='Success',[int]$StatusCode=200)
    [pscustomobject]@{
        Request=$Request;SourceEndpoint=[string]$Request.Uri;LastEndpoint=[string]$Request.Uri;Status=$Status;StatusCode=$StatusCode;
        Items=@($Items);Error=$null;ErrorCode=$null;ErrorMessage=$null;RequestId='req-test';AttemptCount=1;RetryCount=0;PageCount=1
    }
}

AfterAll { Remove-Variable -Name NewTestBatchResult -Scope Global -ErrorAction SilentlyContinue }

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

Describe 'Group relationship completeness hardening' {
    InModuleScope EntraTopology {
        It 'recovers service-principal group membership and ownership through supported v1.0 reverse relationships' {
            Mock Test-EntraTopologyPermission { $true }
            Mock Test-EntraTopologyMayProbePermission { $true }
            Mock Get-EntraTopologyGraphContext { [pscustomobject]@{AuthType='AppOnly';Scopes=@()} }
            Mock Invoke-EntraTopologyGraphRequest {
                param($Uri,$RequiredPermission,$Telemetry)
                if($Uri -like '/v1.0/groups*'){
                    return [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@([pscustomobject]@{id='g1';displayName='Group One';groupTypes=@();mailEnabled=$false;securityEnabled=$true;visibility='Private';onPremisesSyncEnabled=$false});CollectionTime='';Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='groups';RetryCount=0;PageCount=1}
                }
                [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@([pscustomobject]@{id='sp1'});CollectionTime='';Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='sps';RetryCount=0;PageCount=1}
            }
            Mock Invoke-EntraTopologyGraphBatch {
                param($Requests,$BatchSize,$Telemetry)
                foreach($request in @($Requests)){
                    $items=@()
                    if($request.Uri -like '/servicePrincipals/sp1/memberOf*'){$items=@([pscustomobject]@{id='g1';displayName='Group One'})}
                    elseif($request.Uri -like '/servicePrincipals/sp1/ownedObjects*'){$items=@([pscustomobject]@{id='g1';displayName='Group One'})}
                    & $global:NewTestBatchResult -Request $request -Items $items
                }
            }

            $result=Get-EntraTopologyGroups -TenantId 'tenant'
            (@($result.Capabilities|Where-Object Name -eq 'GroupMembers')[0]).Status | Should -Be 'Complete'
            (@($result.Capabilities|Where-Object Name -eq 'GroupOwners')[0]).Status | Should -Be 'Complete'
            @($result.Relations|Where-Object{$_.FromId -eq 'sp1' -and $_.ToId -eq 'g1' -and $_.Relationship -eq 'memberOf'}).Count | Should -Be 1
            @($result.Relations|Where-Object{$_.FromId -eq 'sp1' -and $_.ToId -eq 'g1' -and $_.Relationship -eq 'owns'}).Count | Should -Be 1
            $result.Metrics.ServicePrincipalSupplementRelationCount | Should -Be 2
        }



        It 'deduplicates a service-principal relation if Graph later returns it from both directions' {
            Mock Test-EntraTopologyPermission { $true }
            Mock Test-EntraTopologyMayProbePermission { $true }
            Mock Get-EntraTopologyGraphContext { [pscustomobject]@{AuthType='AppOnly';Scopes=@()} }
            Mock Invoke-EntraTopologyGraphRequest {
                param($Uri,$RequiredPermission,$Telemetry)
                if($Uri -like '/v1.0/groups*'){
                    return [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@([pscustomobject]@{id='g1';displayName='Group One';groupTypes=@();mailEnabled=$false;securityEnabled=$true;visibility='Private';onPremisesSyncEnabled=$false});CollectionTime='';Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='groups';RetryCount=0;PageCount=1}
                }
                [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@([pscustomobject]@{id='sp1'});CollectionTime='';Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='sps';RetryCount=0;PageCount=1}
            }
            Mock Invoke-EntraTopologyGraphBatch {
                param($Requests,$BatchSize,$Telemetry)
                foreach($request in @($Requests)){
                    $items=@()
                    if($request.Uri -like '/groups/g1/members*'){$items=@([pscustomobject]@{id='sp1';displayName='Service Principal One'})}
                    elseif($request.Uri -like '/servicePrincipals/sp1/memberOf*'){$items=@([pscustomobject]@{id='g1';displayName='Group One'})}
                    & $global:NewTestBatchResult -Request $request -Items $items
                }
            }

            $result=Get-EntraTopologyGroups -TenantId 'tenant'
            @($result.Relations|Where-Object{$_.FromId -eq 'sp1' -and $_.ToId -eq 'g1' -and $_.Relationship -eq 'memberOf'}).Count | Should -Be 1
            $result.Metrics.ServicePrincipalSupplementRelationCount | Should -Be 0
        }

        It 'fails closed when the service-principal inventory probe is denied by Graph' {
            Mock Test-EntraTopologyPermission { $true }
            Mock Test-EntraTopologyMayProbePermission { $true }
            Mock Get-EntraTopologyGraphContext { [pscustomobject]@{AuthType='AppOnly';Scopes=@()} }
            Mock Invoke-EntraTopologyGraphRequest {
                param($Uri,$RequiredPermission,$Telemetry)
                if($Uri -like '/v1.0/groups*'){
                    return [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@([pscustomobject]@{id='g1';displayName='Group One';groupTypes=@();mailEnabled=$false;securityEnabled=$true;visibility='Private';onPremisesSyncEnabled=$false});CollectionTime='';Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='groups';RetryCount=0;PageCount=1}
                }
                [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='InsufficientPermission';StatusCode=403;Items=@();CollectionTime='';Limitations=@('Insufficient privileges');ErrorCode='Authorization_RequestDenied';ErrorMessage='Insufficient privileges';RequestId='sps-denied';RetryCount=0;PageCount=0}
            }
            Mock Invoke-EntraTopologyGraphBatch {
                param($Requests,$BatchSize,$Telemetry)
                foreach($request in @($Requests)){& $global:NewTestBatchResult -Request $request}
            }

            $result=Get-EntraTopologyGroups -TenantId 'tenant'
            (@($result.Capabilities|Where-Object Name -eq 'GroupMembers')[0]).Status | Should -Be 'Partial'
            (@($result.Capabilities|Where-Object Name -eq 'GroupOwners')[0]).Status | Should -Be 'Partial'
            ($result.Warnings -join ' ') | Should -Match 'HTTP 403'
            ($result.Warnings -join ' ') | Should -Match 'Insufficient privileges'
        }

        It 'fails closed when service-principal reverse correlation cannot be performed' {
            Mock Test-EntraTopologyPermission { $true }
            Mock Test-EntraTopologyMayProbePermission { $false }
            Mock Invoke-EntraTopologyGraphRequest {
                param($Uri,$RequiredPermission,$Telemetry)
                [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@([pscustomobject]@{id='g1';displayName='Group One';groupTypes=@();mailEnabled=$false;securityEnabled=$true;visibility='Private';onPremisesSyncEnabled=$false});CollectionTime='';Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='groups';RetryCount=0;PageCount=1}
            }
            Mock Invoke-EntraTopologyGraphBatch {
                param($Requests,$BatchSize,$Telemetry)
                foreach($request in @($Requests)){& $global:NewTestBatchResult -Request $request}
            }

            $result=Get-EntraTopologyGroups -TenantId 'tenant'
            (@($result.Capabilities|Where-Object Name -eq 'GroupMembers')[0]).Status | Should -Be 'Partial'
            (@($result.Capabilities|Where-Object Name -eq 'GroupOwners')[0]).Status | Should -Be 'Partial'
            ($result.Warnings -join ' ') | Should -Match 'service-principal membership and ownership omissions'
        }

        It 'marks delegated hidden-membership visibility partial without Member.Read.Hidden' {
            Mock Test-EntraTopologyPermission {
                param($AnyOf)
                return -not ($AnyOf -contains 'Member.Read.Hidden')
            }
            Mock Test-EntraTopologyMayProbePermission { $true }
            Mock Get-EntraTopologyGraphContext { [pscustomobject]@{AuthType='Delegated';Scopes=@('Group.Read.All','Application.Read.All')} }
            Mock Invoke-EntraTopologyGraphRequest {
                param($Uri,$RequiredPermission,$Telemetry)
                if($Uri -like '/v1.0/groups*'){
                    return [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@([pscustomobject]@{id='g1';displayName='Hidden Group';groupTypes=@('Unified');mailEnabled=$true;securityEnabled=$true;visibility='HiddenMembership';onPremisesSyncEnabled=$false});CollectionTime='';Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='groups';RetryCount=0;PageCount=1}
                }
                [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@();CollectionTime='';Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='sps';RetryCount=0;PageCount=1}
            }
            Mock Invoke-EntraTopologyGraphBatch {
                param($Requests,$BatchSize,$Telemetry)
                foreach($request in @($Requests)){& $global:NewTestBatchResult -Request $request}
            }

            $result=Get-EntraTopologyGroups -TenantId 'tenant'
            (@($result.Capabilities|Where-Object Name -eq 'GroupMembers')[0]).Status | Should -Be 'Partial'
            $result.Metrics.HiddenMembershipGroupCount | Should -Be 1
            ($result.Warnings -join ' ') | Should -Match 'Member.Read.Hidden'
        }

        It 'marks group ownership partial for synchronized or mail-enabled non-Microsoft-365 group types' {
            Mock Test-EntraTopologyPermission { $true }
            Mock Test-EntraTopologyMayProbePermission { $true }
            Mock Get-EntraTopologyGraphContext { [pscustomobject]@{AuthType='AppOnly';Scopes=@()} }
            Mock Invoke-EntraTopologyGraphRequest {
                param($Uri,$RequiredPermission,$Telemetry)
                if($Uri -like '/v1.0/groups*'){
                    return [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@(
                        [pscustomobject]@{id='g1';displayName='Synced';groupTypes=@();mailEnabled=$false;securityEnabled=$true;visibility='Private';onPremisesSyncEnabled=$true},
                        [pscustomobject]@{id='g2';displayName='Distribution';groupTypes=@();mailEnabled=$true;securityEnabled=$false;visibility=$null;onPremisesSyncEnabled=$false}
                    );CollectionTime='';Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='groups';RetryCount=0;PageCount=1}
                }
                [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@();CollectionTime='';Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='sps';RetryCount=0;PageCount=1}
            }
            Mock Invoke-EntraTopologyGraphBatch {
                param($Requests,$BatchSize,$Telemetry)
                foreach($request in @($Requests)){& $global:NewTestBatchResult -Request $request}
            }

            $result=Get-EntraTopologyGroups -TenantId 'tenant'
            (@($result.Capabilities|Where-Object Name -eq 'GroupOwners')[0]).Status | Should -Be 'Partial'
            $result.Metrics.OwnerUnsupportedGroupCount | Should -Be 2
            ($result.Warnings -join ' ') | Should -Match 'does not guarantee owner availability'
        }
    }
}

