BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' 'EntraTopology.psd1') -Force }

Describe 'Canonical element contract 1.1.0' {
    InModuleScope EntraTopology {
        It 'uses EvidenceKeys rather than the pre-freeze EvidenceIds name' {
            $node=New-EntraTopologyNode -TenantId 't' -ObjectId 'u' -Kind 'user' -DisplayName 'User' -EvidenceKeys @('evidence:x')
            $edge=New-EntraTopologyEdge -TenantId 't' -From 'a' -To 'b' -Relationship 'owns' -EvidenceKeys @('evidence:x')
            $node.SchemaVersion | Should -Be '1.1.0'
            $edge.SchemaVersion | Should -Be '1.1.0'
            $node.PSObject.Properties.Name | Should -Contain 'EvidenceKeys'
            $node.PSObject.Properties.Name | Should -Not -Contain 'EvidenceIds'
            $edge.PSObject.Properties.Name | Should -Contain 'EvidenceKeys'
        }

        It 'keeps evidence identity stable when observation metadata changes' {
            $a=New-EntraTopologyEvidence -TenantId 't' -Collector 'Groups' -Endpoint '/groups/g1/members' -SourceObjectId 'GroupMembers' -Fields @{ObservedAtUtc='2026-01-01T00:00:00Z';RequestId='a'}
            $b=New-EntraTopologyEvidence -TenantId 't' -Collector 'Groups' -Endpoint '/groups/g1/members' -SourceObjectId 'GroupMembers' -Fields @{ObservedAtUtc='2026-01-02T00:00:00Z';RequestId='b'}
            $a.Key | Should -Be $b.Key
        }
    }
}

Describe 'Top-level graph contract 1.2.0' {
    It 'requires recommendations in the graph schema' {
        $schema=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..' 'Schemas' 'topology-graph.schema.json') -Raw | ConvertFrom-Json
        $schema.properties.SchemaVersion.const | Should -Be '1.2.0'
        @($schema.required) | Should -Contain 'Recommendations'
    }
}
