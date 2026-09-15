function New-EntraTopologyGraph {
    [CmdletBinding(DefaultParameterSetName='Object')]
    param(
        [Parameter(Mandatory,ParameterSetName='Object',ValueFromPipeline)][object]$Snapshot,
        [Parameter(Mandatory,ParameterSetName='Path')][string]$SnapshotPath,
        [switch]$IncludeSignals,
        [string]$Path
    )
    process {
        $s=if($PSCmdlet.ParameterSetName-eq'Path'){Read-EntraTopologyJson $SnapshotPath}else{$Snapshot}
        $before=Get-EntraTopologyGraphTransportCallCount
        $g=ConvertTo-EntraTopologyGraphInternal -Snapshot $s -IncludeSignals:$IncludeSignals
        $after=Get-EntraTopologyGraphTransportCallCount
        $callsAfterSnapshot=[long]($after-$before)
        if($callsAfterSnapshot -ne 0){throw "Offline topology construction violated the Graph boundary: $callsAfterSnapshot Graph HTTP request(s) occurred after snapshot input."}
        $g.Metadata.GraphCallsAfterSnapshot=$callsAfterSnapshot
        if($Path){Save-EntraTopologyJson -InputObject $g -Path $Path|Out-Null}
        $g
    }
}
