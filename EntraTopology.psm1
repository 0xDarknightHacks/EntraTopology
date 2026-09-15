Set-StrictMode -Version Latest

$privateFiles = @(
    'Private/Telemetry/Telemetry.Common.ps1',
    'Private/Diagnostics/Diagnostics.Common.ps1',
    'Private/Cli/Cli.Common.ps1',
    'Private/Graph/GraphContext.Common.ps1',
    'Private/Graph/Invoke-EntraTopologyGraphRequest.ps1',
    'Private/Graph/Invoke-EntraTopologyGraphBatch.ps1',
    'Private/Model/TopologyModel.ps1',
    'Private/Navigation/Portal.Common.ps1',
    'Private/Collectors/Collector.Common.ps1',
    'Private/Collectors/Get-EntraTopologyUsers.ps1',
    'Private/Collectors/Get-EntraTopologyGroups.ps1',
    'Private/Collectors/Get-EntraTopologyApplications.ps1',
    'Private/Collectors/Get-EntraTopologyDevices.ps1',
    'Private/Collectors/Get-EntraTopologyRoles.ps1',
    'Private/Collectors/Resolve-EntraTopologyDirectoryObjects.ps1',
    'Private/Collectors/Invoke-EntraTopologyCollection.ps1',
    'Private/Snapshot/Snapshot.Common.ps1',
    'Private/Normalization/ConvertTo-EntraTopologyGraph.ps1',
    'Private/Signals/Add-EntraTopologySignals.ps1',
    'Private/Recommendations/Recommendations.Common.ps1',
    'Private/Comparison/Comparison.Common.ps1',
    'Private/Query/GraphQuery.Common.ps1',
    'Private/Export/Export.Common.ps1',
    'Private/Reporting/Report.Common.ps1'
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
