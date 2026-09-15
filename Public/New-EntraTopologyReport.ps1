function New-EntraTopologyReport {
    [CmdletBinding(DefaultParameterSetName='Object')]
    param(
        [Parameter(Mandatory,ParameterSetName='Object',ValueFromPipeline)]
        [object]$Graph,

        [Parameter(Mandatory,ParameterSetName='Path')]
        [string]$GraphPath,

        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Title='EntraTopology Tenant Topology Report'
    )

    process {
        $g = if($PSCmdlet.ParameterSetName -eq 'Path') { Read-EntraTopologyJson $GraphPath } else { $Graph }
        $hasNodes = if($g -is [System.Collections.IDictionary]) { $g.Contains('Nodes') } else { $null -ne ($g.PSObject.Properties | Where-Object Name -IEQ 'Nodes' | Select-Object -First 1) }
        $hasEdges = if($g -is [System.Collections.IDictionary]) { $g.Contains('Edges') } else { $null -ne ($g.PSObject.Properties | Where-Object Name -IEQ 'Edges' | Select-Object -First 1) }
        if(-not (Get-EntraTopologyProperty $g 'TenantId') -or -not $hasNodes -or -not $hasEdges) {
            throw 'Input is not a valid EntraTopology graph object.'
        }

        $before = Get-EntraTopologyGraphTransportCallCount
        $html = ConvertTo-EntraTopologyReportHtml -Graph $g -Title $Title
        $after = Get-EntraTopologyGraphTransportCallCount
        if(($after - $before) -ne 0) {
            throw 'Offline report generation violated the Graph boundary.'
        }

        $parent = Split-Path -Parent $Path
        if($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        Set-Content -LiteralPath $Path -Value $html -Encoding utf8
        Get-Item -LiteralPath $Path
    }
}
