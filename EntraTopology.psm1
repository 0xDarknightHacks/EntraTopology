Set-StrictMode -Version Latest

$privateFiles = @(
    'Private/Common.ps1',
    'Private/Graph.ps1',
    'Private/Collection.ps1',
    'Private/Topology.ps1',
    'Private/Comparison.ps1',
    'Private/Reporting.ps1'
)

$publicFiles = @(
    'Public/Connect-EntraTopologyGraph.ps1',
    'Public/New-EntraTopologySnapshot.ps1',
    'Public/New-EntraTopologyGraph.ps1',
    'Public/Invoke-EntraTopology.ps1',
    'Public/Get-EntraTopologyNode.ps1',
    'Public/Find-EntraTopologyPath.ps1',
    'Public/Compare-EntraTopologyGraph.ps1',
    'Public/Export-EntraTopologyGraph.ps1',
    'Public/New-EntraTopologyReport.ps1'
)

foreach ($relativePath in ($privateFiles + $publicFiles)) {
    $path = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "Required module file was not found: $path" }
    . $path
}

Export-ModuleMember -Function @(
    'Connect-EntraTopologyGraph', 'New-EntraTopologySnapshot', 'New-EntraTopologyGraph',
    'Invoke-EntraTopology', 'Get-EntraTopologyNode', 'Find-EntraTopologyPath',
    'Compare-EntraTopologyGraph', 'Export-EntraTopologyGraph', 'New-EntraTopologyReport'
)
