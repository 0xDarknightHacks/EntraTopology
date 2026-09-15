BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' 'EntraTopology.psd1') -Force }

Describe 'Offline topology construction' {
    It 'builds a graph from a snapshot without any Microsoft Graph transport call' {
        InModuleScope EntraTopology {
            Mock Invoke-MgGraphRequest { throw 'Graph transport must not be called during offline graph construction.' }
            Mock Invoke-EntraTopologyGraphRequest { throw 'Graph request wrapper must not be called during offline graph construction.' }
            Mock Invoke-EntraTopologyGraphBatch { throw 'Graph batch wrapper must not be called during offline graph construction.' }

            $snapshot=[pscustomobject]@{
                TenantId='tenant';SnapshotId='s1';CollectedAtUtc='2026-01-01T00:00:00Z';Collectors=@(
                    [pscustomobject]@{
                        Name='Users';Status='Complete';RequiredPermissions=@('User.Read.All');Warnings=@();Metrics=@{};Evidence=@();
                        Capabilities=@([pscustomobject]@{Name='UserInventory';Status='Complete';RequiredPermissions=@('User.Read.All');Endpoints=@();Warnings=@()});
                        Objects=@([pscustomobject]@{Kind='user';Object=[pscustomobject]@{id='u1';displayName='User';accountEnabled=$true}});Relations=@()
                    }
                )
            }
            $graph=New-EntraTopologyGraph -Snapshot $snapshot -IncludeSignals
            $graph.Nodes.Count | Should -Be 1
            $graph.Metadata.GraphCallsAfterSnapshot | Should -Be 0
            Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
            Should -Invoke Invoke-EntraTopologyGraphRequest -Times 0 -Exactly
            Should -Invoke Invoke-EntraTopologyGraphBatch -Times 0 -Exactly
        }
    }
}
