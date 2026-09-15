function Export-EntraTopologyGraph {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Graph,[Parameter(Mandatory)][string]$Path,[ValidateSet('Json','GraphML','OpenGraph')][string]$Format='Json')
    switch($Format){
        'Json'{Save-EntraTopologyJson -InputObject $Graph -Path $Path|Out-Null}
        'GraphML'{ConvertTo-EntraTopologyGraphML -Graph $Graph|Set-Content -LiteralPath $Path -Encoding utf8}
        'OpenGraph'{
            $payload=[pscustomobject]@{metadata=@{source='EntraTopology';tenantId=$Graph.TenantId;schemaVersion=$Graph.SchemaVersion};nodes=@($Graph.Nodes|ForEach-Object{[pscustomobject]@{id=$_.Key;kind=$_.Kind;label=$_.DisplayName;properties=$_.Properties}});edges=@($Graph.Edges|ForEach-Object{[pscustomobject]@{id=$_.Key;source=$_.From;target=$_.To;kind=$_.Relationship;properties=$_.State}})}
            Save-EntraTopologyJson -InputObject $payload -Path $Path|Out-Null
        }
    };Get-Item -LiteralPath $Path
}
