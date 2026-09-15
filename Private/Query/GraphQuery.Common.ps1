function Get-EntraTopologyAdjacency { param([Parameter(Mandatory)][object]$Graph,[switch]$Undirected)
    $a=@{};foreach($n in @($Graph.Nodes)){$a[$n.Key]=[System.Collections.Generic.List[object]]::new()};foreach($e in @($Graph.Edges)){if(-not$a.ContainsKey($e.From)){$a[$e.From]=[System.Collections.Generic.List[object]]::new()};$a[$e.From].Add([pscustomobject]@{Next=$e.To;Edge=$e});if($Undirected){if(-not$a.ContainsKey($e.To)){$a[$e.To]=[System.Collections.Generic.List[object]]::new()};$a[$e.To].Add([pscustomobject]@{Next=$e.From;Edge=$e})}};$a
}
