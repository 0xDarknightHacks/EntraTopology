BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' 'EntraTopology.psd1') -Force }

Describe 'Semantic topology comparison' {
    It 'ignores evidence-key churn when topology semantics are unchanged' {
        $a=[pscustomobject]@{TenantId='t';Nodes=@();Signals=@();Edges=@([pscustomobject]@{Key='edge:x';From='a';To='b';Relationship='owns';Qualifier='';State=@{};EvidenceKeys=@('evidence:old')})}
        $b=[pscustomobject]@{TenantId='t';Nodes=@();Signals=@();Edges=@([pscustomobject]@{Key='edge:x';From='a';To='b';Relationship='owns';Qualifier='';State=@{};EvidenceKeys=@('evidence:new')})}
        $result=Compare-EntraTopologyGraph -ReferenceGraph $a -DifferenceGraph $b
        $result.Summary.Changed | Should -Be 0
    }

    It 'reports edge state changes without requiring edge identity churn' {
        $a=[pscustomobject]@{TenantId='t';Nodes=@();Signals=@();Edges=@([pscustomobject]@{Key='edge:x';From='a';To='b';Relationship='assignedDirectoryRole';Qualifier='/';State=@{assignmentType='active'};EvidenceKeys=@()})}
        $b=[pscustomobject]@{TenantId='t';Nodes=@();Signals=@();Edges=@([pscustomobject]@{Key='edge:x';From='a';To='b';Relationship='assignedDirectoryRole';Qualifier='/';State=@{assignmentType='eligible'};EvidenceKeys=@()})}
        $result=Compare-EntraTopologyGraph -ReferenceGraph $a -DifferenceGraph $b
        $result.Summary.Changed | Should -Be 1
    }
}
