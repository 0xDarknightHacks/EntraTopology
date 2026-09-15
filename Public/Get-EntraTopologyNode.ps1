function Get-EntraTopologyNode {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Graph,[string]$Id,[string]$DisplayName,[string]$Kind,[string]$SignalType)
    $nodes=@($Graph.Nodes);if($Id){$nodes=@($nodes|Where-Object{$_.Id-eq$Id -or $_.Key-eq$Id})};if($DisplayName){$nodes=@($nodes|Where-Object{$_.DisplayName-like$DisplayName})};if($Kind){$nodes=@($nodes|Where-Object{$_.Kind-eq$Kind})};if($SignalType){$keys=@($Graph.Signals|Where-Object Type -eq $SignalType|ForEach-Object TargetKey);$nodes=@($nodes|Where-Object{$keys-contains$_.Key})};$nodes
}
