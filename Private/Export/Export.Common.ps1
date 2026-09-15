function ConvertTo-EntraTopologyGraphML {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Graph)
    $enc=[System.Security.SecurityElement];$sb=[Text.StringBuilder]::new();[void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>');[void]$sb.AppendLine('<graphml xmlns="http://graphml.graphdrawing.org/xmlns"><graph edgedefault="directed">')
    foreach($n in @($Graph.Nodes)){[void]$sb.AppendLine(('<node id="{0}"><data key="kind">{1}</data><data key="label">{2}</data></node>' -f $enc::Escape([string]$n.Key), $enc::Escape([string]$n.Kind), $enc::Escape([string]$n.DisplayName)))}
    foreach($e in @($Graph.Edges)){[void]$sb.AppendLine(('<edge id="{0}" source="{1}" target="{2}"><data key="relationship">{3}</data></edge>' -f $enc::Escape([string]$e.Key), $enc::Escape([string]$e.From), $enc::Escape([string]$e.To), $enc::Escape([string]$e.Relationship)))}
    [void]$sb.AppendLine('</graph></graphml>');$sb.ToString()
}
