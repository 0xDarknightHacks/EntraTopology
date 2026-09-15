function Compare-EntraTopologyGraph {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$ReferenceGraph,[Parameter(Mandatory)][object]$DifferenceGraph)
    if($ReferenceGraph.TenantId-ne$DifferenceGraph.TenantId){throw 'Graphs belong to different tenants.'}
    $changes=@();$changes+=Compare-EntraTopologySet $ReferenceGraph.Nodes $DifferenceGraph.Nodes 'Node';$changes+=Compare-EntraTopologySet $ReferenceGraph.Edges $DifferenceGraph.Edges 'Edge';$changes+=Compare-EntraTopologySet $ReferenceGraph.Signals $DifferenceGraph.Signals 'Signal'
    [pscustomobject][ordered]@{TenantId=$ReferenceGraph.TenantId;ComparedAtUtc=[datetime]::UtcNow.ToString('o');Summary=@{Added=@($changes|Where-Object Change -eq 'Added').Count;Removed=@($changes|Where-Object Change -eq 'Removed').Count;Changed=@($changes|Where-Object Change -eq 'Changed').Count};Changes=@($changes)}
}
