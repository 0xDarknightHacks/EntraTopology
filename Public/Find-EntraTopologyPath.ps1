function Find-EntraTopologyPath {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Graph,[Parameter(Mandatory)][string]$From,[Parameter(Mandatory)][string]$To,[ValidateRange(1,12)][int]$MaxDepth=6,[switch]$Undirected)
    $fromNode=@($Graph.Nodes|Where-Object{$_.Id-eq$From -or $_.Key-eq$From}|Select-Object -First 1);$toNode=@($Graph.Nodes|Where-Object{$_.Id-eq$To -or $_.Key-eq$To}|Select-Object -First 1);if(-not$fromNode -or -not$toNode){return $null}
    $adj=Get-EntraTopologyAdjacency -Graph $Graph -Undirected:$Undirected;$q=[Collections.Generic.Queue[object]]::new();$q.Enqueue([pscustomobject]@{Key=$fromNode.Key;Nodes=@($fromNode.Key);Edges=@()});$seen=@{$fromNode.Key=$true}
    while($q.Count){$cur=$q.Dequeue();if($cur.Key-eq$toNode.Key){return $cur};if($cur.Edges.Count-ge$MaxDepth){continue};foreach($step in @($adj[$cur.Key])){if($seen.ContainsKey($step.Next)){continue};$seen[$step.Next]=$true;$q.Enqueue([pscustomobject]@{Key=$step.Next;Nodes=@($cur.Nodes)+$step.Next;Edges=@($cur.Edges)+$step.Edge})}}
    return $null
}
