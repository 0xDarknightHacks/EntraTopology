function Get-EntraTopologyIndex {
    param([object[]]$Item)
    $h=@{};foreach($x in @($Item)){if($x.Key){$h[[string]$x.Key]=$x}};$h
}

function Get-EntraTopologySemanticFingerprint {
    param([Parameter(Mandatory)][object]$Item,[Parameter(Mandatory)][string]$Kind)
    $semantic=switch($Kind){
        'Node' {
            [ordered]@{Id=$Item.Id;TenantId=$Item.TenantId;Kind=$Item.Kind;DisplayName=$Item.DisplayName;Properties=$Item.Properties}
        }
        'Edge' {
            [ordered]@{From=$Item.From;To=$Item.To;Relationship=$Item.Relationship;Qualifier=$Item.Qualifier;State=$Item.State}
        }
        'Signal' {
            [ordered]@{TargetKey=$Item.TargetKey;Type=$Item.Type;Severity=$Item.Severity;Reason=$Item.Reason;State=$Item.State}
        }
        default { $Item }
    }
    Get-EntraTopologyObjectFingerprint $semantic
}

function Compare-EntraTopologySet {
    param([object[]]$Reference,[object[]]$Difference,[string]$Kind)
    $a=Get-EntraTopologyIndex $Reference;$b=Get-EntraTopologyIndex $Difference;$out=[System.Collections.Generic.List[object]]::new()
    foreach($k in $b.Keys){
        if(-not$a.ContainsKey($k)){$out.Add([pscustomobject]@{Change='Added';Kind=$Kind;Key=$k;Before=$null;After=$b[$k]})}
        elseif((Get-EntraTopologySemanticFingerprint -Item $a[$k] -Kind $Kind)-ne(Get-EntraTopologySemanticFingerprint -Item $b[$k] -Kind $Kind)){$out.Add([pscustomobject]@{Change='Changed';Kind=$Kind;Key=$k;Before=$a[$k];After=$b[$k]})}
    }
    foreach($k in $a.Keys){if(-not$b.ContainsKey($k)){$out.Add([pscustomobject]@{Change='Removed';Kind=$Kind;Key=$k;Before=$a[$k];After=$null})}}
    @($out)
}

function Compare-EntraTopologyGraph {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$ReferenceGraph,[Parameter(Mandatory)][object]$DifferenceGraph)
    if($ReferenceGraph.TenantId-ne$DifferenceGraph.TenantId){throw 'Graphs belong to different tenants.'}
    $changes=@();$changes+=Compare-EntraTopologySet $ReferenceGraph.Nodes $DifferenceGraph.Nodes 'Node';$changes+=Compare-EntraTopologySet $ReferenceGraph.Edges $DifferenceGraph.Edges 'Edge';$changes+=Compare-EntraTopologySet $ReferenceGraph.Signals $DifferenceGraph.Signals 'Signal'
    [pscustomobject][ordered]@{TenantId=$ReferenceGraph.TenantId;ComparedAtUtc=[datetime]::UtcNow.ToString('o');Summary=@{Added=@($changes|Where-Object Change -eq 'Added').Count;Removed=@($changes|Where-Object Change -eq 'Removed').Count;Changed=@($changes|Where-Object Change -eq 'Changed').Count};Changes=@($changes)}
}
