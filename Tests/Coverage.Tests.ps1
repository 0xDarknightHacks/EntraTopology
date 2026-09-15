BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'EntraTopology.psd1') -Force

    function New-TestApplicationSnapshot {
        param([string]$OwnershipStatus)
        [pscustomobject]@{
            TenantId='tenant';SnapshotId='s1';CollectedAtUtc='2026-01-01T00:00:00Z';Collectors=@(
                [pscustomobject]@{
                    Name='Applications';Status=$(if($OwnershipStatus -eq 'Complete'){'Complete'}else{'Partial'});RequiredPermissions=@('Application.Read.All');Warnings=@();Metrics=@{};Evidence=@();
                    Capabilities=@(
                        [pscustomobject]@{Name='ApplicationInventory';Status='Complete';RequiredPermissions=@('Application.Read.All');Endpoints=@();Warnings=@()},
                        [pscustomobject]@{Name='ApplicationOwnership';Status=$OwnershipStatus;RequiredPermissions=@('Application.Read.All');Endpoints=@();Warnings=@()}
                    );
                    Objects=@([pscustomobject]@{Kind='application';Object=[pscustomobject]@{id='a1';displayName='App One';passwordCredentials=@();keyCredentials=@()}});
                    Relations=@()
                }
            )
        }
    }
}

Describe 'Coverage-aware security signals' {
    It 'does not emit ownerless signals when ownership coverage is partial' {
        $graph=New-EntraTopologyGraph -Snapshot (New-TestApplicationSnapshot -OwnershipStatus 'Partial') -IncludeSignals
        @($graph.Signals | Where-Object Type -eq 'ownerlessObject').Count | Should -Be 0
    }

    It 'emits ownerless signals only when ownership coverage is complete' {
        $graph=New-EntraTopologyGraph -Snapshot (New-TestApplicationSnapshot -OwnershipStatus 'Complete') -IncludeSignals
        @($graph.Signals | Where-Object Type -eq 'ownerlessObject').Count | Should -Be 1
    }

    It 'preserves capability-level coverage in the graph' {
        $graph=New-EntraTopologyGraph -Snapshot (New-TestApplicationSnapshot -OwnershipStatus 'Partial')
        $apps=@($graph.Coverage | Where-Object Collector -eq 'Applications')[0]
        (@($apps.Capabilities | Where-Object Name -eq 'ApplicationOwnership')[0]).Status | Should -Be 'Partial'
    }
}

Describe 'Service-principal ownerless signal scope' {
    It 'suppresses ownerless signals for foreign application service principals and managed identities' {
        $snapshot=[pscustomobject]@{
            TenantId='tenant';SnapshotId='s2';CollectedAtUtc='2026-01-01T00:00:00Z';Collectors=@(
                [pscustomobject]@{
                    Name='Applications';Status='Complete';RequiredPermissions=@('Application.Read.All');Warnings=@();Metrics=@{};Evidence=@();
                    Capabilities=@(
                        [pscustomobject]@{Name='ApplicationInventory';Status='Complete';RequiredPermissions=@('Application.Read.All');Endpoints=@();Warnings=@()},
                        [pscustomobject]@{Name='ServicePrincipalOwnership';Status='Complete';RequiredPermissions=@('Application.Read.All');Endpoints=@();Warnings=@()}
                    );
                    Objects=@(
                        [pscustomobject]@{Kind='servicePrincipal';Object=[pscustomobject]@{id='sp-local';displayName='Local';servicePrincipalType='Application';appOwnerOrganizationId='tenant'}},
                        [pscustomobject]@{Kind='servicePrincipal';Object=[pscustomobject]@{id='sp-foreign';displayName='Foreign';servicePrincipalType='Application';appOwnerOrganizationId='other-tenant'}},
                        [pscustomobject]@{Kind='servicePrincipal';Object=[pscustomobject]@{id='sp-mi';displayName='Managed';servicePrincipalType='ManagedIdentity';appOwnerOrganizationId='tenant'}}
                    );Relations=@()
                }
            )
        }
        $graph=New-EntraTopologyGraph -Snapshot $snapshot -IncludeSignals
        $ownerless=@($graph.Signals | Where-Object Type -eq 'ownerlessObject')
        $ownerless.Count | Should -Be 1
        $ownerless[0].TargetKey | Should -Be 'tenant:tenant:object:sp-local'
    }
}

Describe 'Topology security-context enrichment' {
    It 'marks active risky users only when risky-user coverage is complete' {
        $snapshot=[pscustomobject]@{TenantId='tenant';SnapshotId='risk';CollectedAtUtc='2026-01-01T00:00:00Z';Collectors=@(
            [pscustomobject]@{Name='Users';Status='Complete';RequiredPermissions=@('User.Read.All');Warnings=@();Metrics=@{};Evidence=@();Capabilities=@(
                [pscustomobject]@{Name='UserInventory';Status='Complete';RequiredPermissions=@('User.Read.All');Endpoints=@();Warnings=@()},
                [pscustomobject]@{Name='RiskyUserContext';Status='Complete';RequiredPermissions=@('IdentityRiskyUser.Read.All');Endpoints=@();Warnings=@()}
            );Objects=@([pscustomobject]@{Kind='user';Object=[pscustomobject]@{id='u1';displayName='Risky User';accountEnabled=$true;riskLevel='high';riskState='atRisk';riskDetail='none'}});Relations=@()}
        )}
        $graph=New-EntraTopologyGraph -Snapshot $snapshot -IncludeSignals
        $risk=@($graph.Signals|Where-Object Type -eq 'riskyIdentity')
        $risk.Count | Should -Be 1
        $risk[0].Severity | Should -Be 'High'
    }

    It 'adds privileged identity and high-privilege role relationship context from active role assignments' {
        $snapshot=[pscustomobject]@{TenantId='tenant';SnapshotId='priv';CollectedAtUtc='2026-01-01T00:00:00Z';Collectors=@(
            [pscustomobject]@{Name='DirectoryRoles';Status='Complete';RequiredPermissions=@('RoleManagement.Read.Directory');Warnings=@();Metrics=@{};Evidence=@();Capabilities=@(
                [pscustomobject]@{Name='DirectoryRoleAssignments';Status='Complete';RequiredPermissions=@('RoleManagement.Read.Directory');Endpoints=@();Warnings=@()}
            );Objects=@(
                [pscustomobject]@{Kind='user';Object=[pscustomobject]@{id='u1';displayName='Admin';accountEnabled=$true}},
                [pscustomobject]@{Kind='directoryRole';Object=[pscustomobject]@{id='r1';displayName='Global Administrator'}}
            );Relations=@([pscustomobject]@{FromId='u1';ToId='r1';Relationship='assignedDirectoryRole';Qualifier='/';State=@{};EvidenceRefs=@()})}
        )}
        $graph=New-EntraTopologyGraph -Snapshot $snapshot -IncludeSignals
        @($graph.Signals|Where-Object Type -eq 'privilegedIdentity').Count | Should -Be 1
        @($graph.Signals|Where-Object Type -eq 'highPrivilegeRoleAssignment').Count | Should -Be 1
    }

    It 'marks curated high-impact application permissions on relationship edges without claiming over-privilege' {
        $snapshot=[pscustomobject]@{TenantId='tenant';SnapshotId='perm';CollectedAtUtc='2026-01-01T00:00:00Z';Collectors=@(
            [pscustomobject]@{Name='Applications';Status='Complete';RequiredPermissions=@('Application.Read.All');Warnings=@();Metrics=@{};Evidence=@();Capabilities=@(
                [pscustomobject]@{Name='ApplicationInventory';Status='Complete';RequiredPermissions=@('Application.Read.All');Endpoints=@();Warnings=@()},
                [pscustomobject]@{Name='ServicePrincipalAppRoleAssignments';Status='Complete';RequiredPermissions=@('Application.Read.All');Endpoints=@();Warnings=@()}
            );Objects=@(
                [pscustomobject]@{Kind='servicePrincipal';Object=[pscustomobject]@{id='client';displayName='Automation';appRoles=@()}},
                [pscustomobject]@{Kind='servicePrincipal';Object=[pscustomobject]@{id='graph';displayName='Microsoft Graph';appRoles=@([pscustomobject]@{id='role1';value='RoleManagement.ReadWrite.Directory';displayName='Read and write directory RBAC settings';description='';isEnabled=$true;allowedMemberTypes=@('Application')})}}
            );Relations=@([pscustomobject]@{FromId='client';ToId='graph';Relationship='hasAppRoleAssignment';Qualifier='role1';State=@{appRoleId='role1'};EvidenceRefs=@()})}
        )}
        $graph=New-EntraTopologyGraph -Snapshot $snapshot -IncludeSignals
        $signal=@($graph.Signals|Where-Object Type -eq 'highImpactApplicationPermission')
        $signal.Count | Should -Be 1
        $signal[0].TargetKey | Should -Be @($graph.Edges|Where-Object Relationship -eq 'hasAppRoleAssignment')[0].Key
        ($graph.Signals.Type -join ' ') | Should -Not -Match 'overPrivileged'
    }
}
