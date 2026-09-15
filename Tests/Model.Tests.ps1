Import-Module (Join-Path $PSScriptRoot '..' 'EntraTopology.psd1') -Force
Describe 'Topology identity semantics' {
    InModuleScope EntraTopology {
        It 'keeps edge identity stable when mutable state changes' {
            $a=New-EntraTopologyEdge -TenantId t -From a -To b -Relationship owns -State @{x=1}
            $b=New-EntraTopologyEdge -TenantId t -From a -To b -Relationship owns -State @{x=2}
            $a.Key | Should -Be $b.Key
        }
    }
}

Describe 'Relationship evidence provenance' {
    InModuleScope EntraTopology {
        It 'attaches exact collector evidence to normalized edges' {
            $endpoint='/groups/g1/members?$select=id,displayName'
            $snapshot=[pscustomobject]@{
                TenantId='tenant';SnapshotId='s1';CollectedAtUtc='2026-01-01T00:00:00Z';Collectors=@(
                    [pscustomobject]@{
                        Name='Groups';Status='Complete';RequiredPermissions=@('Group.Read.All');Warnings=@();Metrics=@{};
                        Capabilities=@([pscustomobject]@{Name='GroupMembers';Status='Complete';RequiredPermissions=@('Group.Read.All');Endpoints=@($endpoint);Warnings=@()});
                        Evidence=@([pscustomobject]@{Capability='GroupMembers';Endpoint=$endpoint;Status='Success';RequiredPermission='Group.Read.All';Count=1;Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='req1';PageCount=1;RetryCount=0;ObservedAtUtc='2026-01-01T00:00:00Z'});
                        Objects=@(
                            [pscustomobject]@{Kind='group';Object=[pscustomobject]@{id='g1';displayName='Group'}},
                            [pscustomobject]@{Kind='user';Object=[pscustomobject]@{id='u1';displayName='User'}}
                        );
                        Relations=@([pscustomobject]@{FromId='u1';ToId='g1';Relationship='memberOf';Qualifier='';State=@{};EvidenceRefs=@([pscustomobject]@{Capability='GroupMembers';Endpoint=$endpoint})})
                    }
                )
            }
            $graph=New-EntraTopologyGraph -Snapshot $snapshot
            $graph.Edges.Count | Should -Be 1
            $graph.Edges[0].EvidenceKeys.Count | Should -Be 1
            $matched=@($graph.Evidence | Where-Object Key -eq $graph.Edges[0].EvidenceKeys[0])
            $matched.Count | Should -Be 1
            $matched[0].Endpoint | Should -Be $endpoint
        }
    }
}
